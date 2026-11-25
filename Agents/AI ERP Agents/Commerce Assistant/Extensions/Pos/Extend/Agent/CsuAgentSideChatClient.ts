/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The side panel's backend: the assistant gateway in Azure API Management (APIM), which passes each
 * request on to the AI Foundry agent.
 *
 * Asks Commerce Runtime for the gateway's address, uploads any attached files to its /attachments
 * route, then posts what the operator said, where they are, and the names of the actions POS can run
 * to its /chat route. Gets back something to say and the actions to run.
 *
 * This is a POS (SystemJS) module — it has access to `PosApi/*` and the generated proxies, and is
 * NOT part of the React/webpack bundle.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { GetCurrentCartClientRequest, GetCurrentCartClientResponse } from "PosApi/Consume/Cart";
import {
    GetAuthenticationTokenClientRequest,
    GetAuthenticationTokenClientResponse
} from "PosApi/Consume/Device";
import { ObjectExtensions, StringExtensions } from "PosApi/TypeExtensions";
import {
    getPosError,
    ICartSuggestionReply,
    ICartSuggestionRequest,
    IAgentAttachmentInfo,
    IAgentPosAction,
    IAgentPosErrorContext,
    IAgentRequestEnvelope,
    IAgentResponseEnvelope,
    IAgentToolActivity,
    ISideChatAttachment,
    ISideChatClient,
    ISideChatReply,
    SideChatMessage
} from "ContosoSideChat";
import {
    getCartSuggestionActionNames,
    getSupportedActionNames,
    PRODUCT_RECOMMENDATIONS_ACTION
} from "./posActionCatalogue";
import { buildCartSuggestionEnvelope } from "./cartSuggestionEnvelope";
import { getCurrentStoreAsync } from "./CurrentStoreHelper";
import { addSale, describeSale } from "./saleContext";
import { StoreOperations } from "../../DataService/DataServiceRequests.g";

/** Most files one message can carry. The panel holds its box to the same number. */
const MAX_ATTACHMENTS: number = 3;

/** The files the assistant can read: photos and PDFs. */
const ATTACHMENT_TYPES: string[] = ["image/png", "image/jpeg", "image/webp", "image/gif", "application/pdf"];

/**
 * Most base64 characters of files one message can carry, about 1.3 MB once decoded. The panel uses
 * the same conservative cap before the files are uploaded separately.
 */
const MAX_ATTACHMENT_DATA_LENGTH: number = 1800000;

/** Longest file name the agent is told about. */
const MAX_ATTACHMENT_NAME_LENGTH: number = 80;

/** The longest gateway error body shown as it is. Longer ones are usually pages, not messages. */
const MAX_SHOWN_ERROR_LENGTH: number = 300;

/**
 * Matches the Commerce tools that change something, such as add_product_to_cart or create_cart, and
 * tools that apply or redeem a discount or coupon, should Commerce add any. An automatic cart check only
 * looks things up, so a check that called one is reported, not shown.
 */
const CHANGING_TOOL_PATTERN: RegExp = /^(?:add|create|update|remove|set|delete|apply|redeem)_/;

/** A reply read from the gateway's response, and the conversation it belongs to. */
interface IAssistantReply {
    reply: ISideChatReply;
    /** Absent when the response had no text at all. */
    conversationId?: string;
}

export interface IPhotoCartChange {
    action: "add_product_to_cart" | "update_cart_line";
    productId: number;
    quantity: number;
}

export interface IPhotoCartReply {
    displayMessage: string;
    changes: ReadonlyArray<IPhotoCartChange>;
    hasFailures: boolean;
}

/** One file uploaded to the assistant gateway, ready to reference from the chat request. */
interface IUploadedAttachment {
    file_id: string;
    name: string;
    type: string;
}

/** One category Azure's content filter blocked a response for. */
interface IContentFilterHit {
    /** What was checked: "prompt" or "completion". */
    source: string;
    /** For example "sexual" or "protected material text". */
    category: string;
    /** For example "medium". Absent for categories that are detected rather than graded. */
    severity?: string;
}

/**
 * Sends side panel prompts to the AI Foundry agent through the APIM gateway.
 */
export default class CsuAgentSideChatClient implements ISideChatClient {
    /** Photos and PDFs the operator attaches go to the agent with their message. */
    public readonly acceptsAttachments: boolean = true;

    private readonly _context: IExtensionContext;

    /** Read once for this client, then reused for the rest of its conversation. */
    private _apimEndpoint: string;

    /** Issued by the backend on the first turn and echoed on every later one. */
    private _conversationId: string;

    /** Issued by the APIM Responses API and used to resume its server-side thread. */
    private _previousResponseId: string;

    /** Counts the operator's messages, so a cart check can tell whether one was sent while it ran. */
    private _userTurnSequence: number;

    /** How many of the operator's messages are still waiting for a reply. */
    private _pendingUserTurns: number;

    /**
     * Counts the conversations started, so a reply to a conversation the operator has since left
     * doesn't carry it on.
     */
    private _conversationNumber: number;

    /**
     * Initializes a new instance of the CsuAgentSideChatClient class.
     * @param {IExtensionContext} context The POS extension context.
     */
    constructor(context: IExtensionContext) {
        this._context = context;
        this._apimEndpoint = StringExtensions.EMPTY;
        this._conversationId = StringExtensions.EMPTY;
        this._previousResponseId = StringExtensions.EMPTY;
        this._userTurnSequence = 0;
        this._pendingUserTurns = 0;
        this._conversationNumber = 0;
    }

    /**
     * Forgets the conversation so far, so the next prompt starts a new thread with the agent. The
     * panel calls this when the operator starts a new chat.
     */
    public startNewConversation(): void {
        this._conversationId = StringExtensions.EMPTY;
        this._previousResponseId = StringExtensions.EMPTY;
        this._conversationNumber += 1;
    }

    /**
     * Asks the agent what to say and what POS should do.
     * @param {string} prompt The latest operator prompt. Empty when they sent only files.
     * @param {ReadonlyArray<SideChatMessage>} history The conversation so far, including this prompt.
     * @param {string | null} viewContext The POS view that was open when the prompt was sent.
     * @param {ReadonlyArray<ISideChatAttachment>} [attachments] The photos and PDFs sent with the prompt.
     * @returns {Promise<ISideChatReply>} The reply and any actions POS should run.
     */
    public async sendAsync(
        prompt: string,
        history: ReadonlyArray<SideChatMessage>,
        viewContext: string | null,
        attachments?: ReadonlyArray<ISideChatAttachment>
    ): Promise<ISideChatReply> {
        void history;

        const correlationId: string = this._context.logger.getNewCorrelationId();
        const conversationNumber: number = this._conversationNumber;
        this._userTurnSequence += 1;
        this._pendingUserTurns += 1;

        try {
            const files: ISideChatAttachment[] = CsuAgentSideChatClient.checkAttachments(attachments);
            if (CsuAgentSideChatClient.startsNewProductSearch(prompt)) {
                this._conversationId = StringExtensions.EMPTY;
                this._previousResponseId = StringExtensions.EMPTY;
            }

            const cart: ProxyEntities.Cart | undefined = await this._getCurrentCartAsync(correlationId);
            const cartId: string = ObjectExtensions.isNullOrUndefined(cart) || ObjectExtensions.isNullOrUndefined(cart.Id)
                ? StringExtensions.EMPTY
                : cart.Id;
            let requestEnvelope: IAgentRequestEnvelope = {
                text: prompt,
                conversationId: this._conversationId,
                cartId: cartId,
                currentView: viewContext ?? StringExtensions.EMPTY,
                supportedActions: getSupportedActionNames(),
                // Lets the agent check stock at this store and find the closest other stores. Left
                // out, and so not serialized, when POS cannot read it.
                store: await getCurrentStoreAsync(this._context, correlationId)
            };

            // Tells the agent which files came with the turn; the files themselves travel beside the
            // envelope, where the gateway hands them to the model as images and documents.
            if (files.length > 0) {
                requestEnvelope.attachments = files.map((file: ISideChatAttachment): IAgentAttachmentInfo => ({
                    name: file.name,
                    type: file.type
                }));
            }

            // A POS operation that just failed on the associate's screen, so the agent can help with it
            // from the IT support guide. Added before the sale, which is fitted to the space left.
            const posError: IAgentPosErrorContext | null = getPosError();
            if (posError) {
                requestEnvelope.posError = posError;
            }

            // Tells the agent which products are on the sale, so that it can act on them (for example,
            // ship them) without reading the cart. Left out when the sale is empty or too large to fit.
            requestEnvelope = addSale(requestEnvelope, describeSale(cart));

            const result: any = await this._postAsync(requestEnvelope, this._previousResponseId, files);

            // Checked first, so the next turn continues from the last reply the operator actually saw.
            this._throwIfUnfinished(result, correlationId);

            // A new chat started while this one waited; the reply belongs to the conversation left behind.
            const isCurrentConversation: boolean = this._conversationNumber === conversationNumber;
            if (isCurrentConversation) {
                this._previousResponseId = result.id || this._previousResponseId;
            }

            const assistantReply: IAssistantReply | null =
                CsuAgentSideChatClient.readReply(result, requestEnvelope.supportedActions);
            if (!assistantReply) {
                throw new Error("The assistant returned a response that did not contain a valid response envelope.");
            }

            // Remembered so the backend can tie later turns to the same conversation.
            if (isCurrentConversation && !StringExtensions.isNullOrWhitespace(assistantReply.conversationId)) {
                this._conversationId = assistantReply.conversationId;
            }

            return assistantReply.reply;
        } catch (error) {
            const detail: string = CsuAgentSideChatClient.describeError(error);
            this._context.logger.logError(`CsuAgentSideChatClient.sendAsync failed: ${detail}`, correlationId);
            throw new Error(detail);
        } finally {
            this._pendingUserTurns -= 1;
        }
    }

    /**
     * Asks the agent which products go best with the cart, after an item was added to it. The
     * operator did not type anything, so the request carries its own instruction and the cart.
     *
     * The check continues the current conversation, so the agent knows what the operator has been
     * looking for and a follow-up question can refer to its suggestions. The conversation moves on
     * only when the panel shows the reply, and only if the operator has not sent a message since the
     * check started; otherwise the reply is left out of it.
     * @param {ICartSuggestionRequest} request The cart to ask about.
     * @param {string | null} viewContext The POS view that is open.
     * @returns {Promise<ICartSuggestionReply>} The reply and the actions that show the suggestions.
     */
    public async suggestForCartAsync(
        request: ICartSuggestionRequest,
        viewContext: string | null
    ): Promise<ICartSuggestionReply> {
        const correlationId: string = this._context.logger.getNewCorrelationId();
        const userTurnSequence: number = this._userTurnSequence;
        const previousResponseId: string = this._previousResponseId;
        const conversationNumber: number = this._conversationNumber;

        try {
            const requestEnvelope: IAgentRequestEnvelope = buildCartSuggestionEnvelope({
                conversationId: this._conversationId,
                cartId: request.cartId,
                currentView: viewContext ?? StringExtensions.EMPTY,
                supportedActions: getCartSuggestionActionNames(),
                cart: request.cart
            });
            const result: any = await this._postAsync(requestEnvelope, previousResponseId);
            this._throwIfUnfinished(result, correlationId);

            const changingTools: string[] = CsuAgentSideChatClient.getChangingToolCalls(result.output || []);
            if (changingTools.length > 0) {
                throw new Error(`The assistant called ${changingTools.join(", ")} while looking for suggestions, `
                    + "which can change the cart. Check the cart.");
            }

            const assistantReply: IAssistantReply | null = CsuAgentSideChatClient.readReply(result);
            if (!assistantReply) {
                throw new Error("The assistant returned a response that did not contain a valid response envelope.");
            }

            const responseId: string = result.id || StringExtensions.EMPTY;

            return {
                ...assistantReply.reply,
                acceptIntoConversation: (): void => {
                    const hasConversationMovedOn: boolean = this._pendingUserTurns > 0
                        || this._userTurnSequence !== userTurnSequence
                        || this._previousResponseId !== previousResponseId
                        || this._conversationNumber !== conversationNumber;
                    if (hasConversationMovedOn) {
                        return;
                    }

                    if (!StringExtensions.isNullOrWhitespace(responseId)) {
                        this._previousResponseId = responseId;
                    }

                    if (!StringExtensions.isNullOrWhitespace(assistantReply.conversationId)) {
                        this._conversationId = assistantReply.conversationId;
                    }
                }
            };
        } catch (error) {
            const detail: string = CsuAgentSideChatClient.describeError(error);
            this._context.logger.logError(`CsuAgentSideChatClient.suggestForCartAsync failed: ${detail}`, correlationId);
            throw new Error(detail);
        }
    }

    /**
     * Asks the agent one question outside the side panel's conversation, such as a view asking it to
     * read an item list from a photo. Each call starts a new thread and leaves the panel's conversation
     * as it is. The agent may only look things up: a reply from a response that called a tool that can
     * change something, such as the cart, is reported, not returned.
     * @param {IExtensionContext} context The POS extension context.
     * @param {IAgentRequestEnvelope} requestEnvelope What to send. Its attachments are filled in from the files.
     * @param {ReadonlyArray<ISideChatAttachment>} [attachments] The photos and PDFs to send with it.
     * @param {string} [correlationId] The correlation identifier for logging. A new one is used when absent.
     * @returns {Promise<ISideChatReply>} The reply and the actions the agent asked for, which the caller
     * checks and runs itself.
     */
    public static async askOnceAsync(
        context: IExtensionContext,
        requestEnvelope: IAgentRequestEnvelope,
        attachments?: ReadonlyArray<ISideChatAttachment>,
        correlationId?: string
    ): Promise<ISideChatReply> {
        const logCorrelationId: string = StringExtensions.isNullOrWhitespace(correlationId)
            ? context.logger.getNewCorrelationId()
            : correlationId;

        try {
            const files: ISideChatAttachment[] = CsuAgentSideChatClient.checkAttachments(attachments);
            const envelope: IAgentRequestEnvelope = files.length > 0
                ? {
                    ...requestEnvelope,
                    attachments: files.map((file: ISideChatAttachment): IAgentAttachmentInfo => ({
                        name: file.name,
                        type: file.type
                    }))
                }
                : requestEnvelope;
            const client: CsuAgentSideChatClient = new CsuAgentSideChatClient(context);
            const result: any = await client._postAsync(envelope, StringExtensions.EMPTY, files);
            client._throwIfUnfinished(result, logCorrelationId);

            const changingTools: string[] = CsuAgentSideChatClient.getChangingToolCalls(result.output || []);
            if (changingTools.length > 0) {
                throw new Error(`The assistant called ${changingTools.join(", ")}, which can change the cart. `
                    + "Check the cart.");
            }

            const assistantReply: IAssistantReply | null = CsuAgentSideChatClient.readReply(result);
            if (!assistantReply) {
                throw new Error("The assistant returned a response that did not contain a valid response envelope.");
            }

            return assistantReply.reply;
        } catch (error) {
            const detail: string = CsuAgentSideChatClient.describeError(error);
            context.logger.logError(`CsuAgentSideChatClient.askOnceAsync failed: ${detail}`, logCorrelationId);
            throw new Error(detail);
        }
    }

    /**
     * Adds a photo's items through Commerce tools, outside the chat conversation. No returned POS
     * actions are executed; the caller must refresh the active cart and verify the tool's changes.
     */
    public static async addPhotoItemsToCartAsync(
        context: IExtensionContext,
        requestEnvelope: IAgentRequestEnvelope,
        attachment: ISideChatAttachment,
        correlationId: string
    ): Promise<IPhotoCartReply> {
        const channelId: number | undefined = requestEnvelope.store?.channelId;
        if (StringExtensions.isNullOrWhitespace(requestEnvelope.cartId)
            || typeof channelId !== "number" || !isFinite(channelId) || channelId <= 0) {
            throw new Error("The active cart and store are required before adding the photo's items.");
        }

        const files: ISideChatAttachment[] = CsuAgentSideChatClient.checkAttachments([attachment]);
        const client: CsuAgentSideChatClient = new CsuAgentSideChatClient(context);
        const result: any = await client._postAsync({
            ...requestEnvelope,
            attachments: files.map((file: ISideChatAttachment): IAgentAttachmentInfo => ({
                name: file.name,
                type: file.type
            }))
        }, StringExtensions.EMPTY, files);
        client._throwIfUnfinished(result, correlationId);

        const changes: IPhotoCartChange[] = [];
        let hasFailures: boolean = false;
        (result.output || []).forEach((item: any): void => {
            if (item?.type !== "mcp_call" || typeof item.name !== "string"
                || !CHANGING_TOOL_PATTERN.test(item.name)) {
                return;
            }

            let args: any;
            try {
                args = JSON.parse(item.arguments);
            } catch {
                hasFailures = true;
                return;
            }

            const quantity: unknown = args?.quantity === undefined && item.name === "add_product_to_cart"
                ? 1
                : args?.quantity;
            if ((item.name !== "add_product_to_cart" && item.name !== "update_cart_line")
                || item.status !== "completed" || item.error || item.isError
                || args?.cartId !== requestEnvelope.cartId
                || args?.channelId !== channelId
                || typeof args?.productId !== "number" || !isFinite(args.productId)
                || Math.floor(args.productId) !== args.productId || args.productId <= 0
                || args.productId > 9007199254740991
                || typeof quantity !== "number" || !isFinite(quantity)
                || quantity <= 0 || quantity > 9007199254740991
                || CsuAgentSideChatClient.hasToolError(item.output)) {
                hasFailures = true;
                return;
            }

            changes.push({ action: item.name, productId: args.productId, quantity: quantity });
        });

        const reply: IAssistantReply | null = CsuAgentSideChatClient.readReply(result, []);
        return {
            displayMessage: reply?.reply.displayMessage || "Review the updated cart.",
            changes: changes,
            hasFailures: hasFailures
        };
    }

    private static hasToolError(output: unknown): boolean {
        let value: any = output;
        if (typeof value === "string") {
            try {
                value = JSON.parse(value);
            } catch {
                return /^\s*(?:error|failed)\b/i.test(value);
            }
        }

        if (!value || typeof value !== "object") {
            return false;
        }

        if (Array.isArray(value)) {
            return value.some((entry: unknown): boolean => CsuAgentSideChatClient.hasToolError(entry));
        }

        return !!(value.isError || value.error || value.Error
            || value.success === false || value.Success === false
            || (Array.isArray(value.errors) && value.errors.length > 0))
            || (value.type === "text" && CsuAgentSideChatClient.hasToolError(value.text))
            || (Array.isArray(value.content) && CsuAgentSideChatClient.hasToolError(value.content));
    }

    /**
     * Sends one request to the assistant gateway.
     * @param {IAgentRequestEnvelope} requestEnvelope What to send.
     * @param {string} previousResponseId The response to continue from, or empty to start a new thread.
     * @param {ReadonlyArray<ISideChatAttachment>} [attachments] Files to send with the request.
     * @returns {Promise<any>} The gateway's Responses API result.
     */
    private async _postAsync(
        requestEnvelope: IAgentRequestEnvelope,
        previousResponseId: string,
        attachments?: ReadonlyArray<ISideChatAttachment>
    ): Promise<any> {
        const apimEndpoint: string = await this._getApimEndpointAsync();
        const authenticationResponse: ClientEntities.ICancelableDataResult<GetAuthenticationTokenClientResponse> =
            await this._context.runtime.executeAsync(
                new GetAuthenticationTokenClientRequest<GetAuthenticationTokenClientResponse>());
        const authenticationToken: any = authenticationResponse.data?.result;
        const userToken: string = authenticationToken?.token ?? StringExtensions.EMPTY;

        if (StringExtensions.isNullOrWhitespace(userToken)) {
            throw new Error("Could not get the signed-in user's authentication token.");
        }

        const tokenType: string = authenticationToken.tokenType || "id_token";
        const authorization: string = `${tokenType} ${userToken}`;
        const commerceGlobal: any = (window as any).Commerce;
        const authentication: any = commerceGlobal?.Authentication;
        const deviceTokenResult: any = authentication?.AuthenticationProviderManager
            ? await authentication.AuthenticationProviderManager.instance
                .acquireToken(authentication.AuthenticationProviderResourceType.DEVICE)
                .getPromise()
            : null;
        const deviceToken: string = deviceTokenResult?.token ?? StringExtensions.EMPTY;
        const body: any = { message: JSON.stringify(requestEnvelope) };

        if (!StringExtensions.isNullOrWhitespace(previousResponseId)) {
            body.previous_response_id = previousResponseId;
        }

        const files: ReadonlyArray<ISideChatAttachment> = attachments ?? [];
        const hasAttachments: boolean = files.length > 0;
        const headers: Record<string, string> = {
            Authorization: authorization,
            "Content-Type": "application/json"
        };

        if (!StringExtensions.isNullOrWhitespace(deviceToken)) {
            headers.DeviceToken = deviceToken;
        }

        if (hasAttachments) {
            const uploadedAttachments: IUploadedAttachment[] = [];
            for (const attachment of files) {
                uploadedAttachments.push(await CsuAgentSideChatClient._uploadAttachmentAsync(
                    attachment,
                    headers,
                    `${apimEndpoint}/attachments`));
            }

            body.attachments = uploadedAttachments;
        }

        const response: Response = await fetch(`${apimEndpoint}/chat`, {
            method: "POST",
            headers: headers,
            body: JSON.stringify(body)
        });
        const responseText: string = await response.text();

        // Gateways answer some failures, such as a request that is too large, with a page, not JSON.
        let result: any = null;
        let isJson: boolean = false;
        if (!StringExtensions.isNullOrWhitespace(responseText)) {
            try {
                result = JSON.parse(responseText);
                isJson = true;
            } catch {
                result = null;
            }
        }

        if (!response.ok) {
            throw new Error(CsuAgentSideChatClient.describeGatewayFailure(response, result, responseText, hasAttachments));
        }

        if (!StringExtensions.isNullOrWhitespace(responseText) && !isJson) {
            throw new Error("The assistant gateway returned a response that wasn't valid JSON.");
        }

        if (!result) {
            throw new Error("The assistant gateway returned an empty response.");
        }

        return result;
    }

    /**
     * Gets the APIM base endpoint from Commerce Runtime and caches it for this client.
     * @returns {Promise<string>} The configured APIM base endpoint without a trailing slash.
     */
    private async _getApimEndpointAsync(): Promise<string> {
        if (!StringExtensions.isNullOrWhitespace(this._apimEndpoint)) {
            return this._apimEndpoint;
        }

        const response: ClientEntities.ICancelableDataResult<StoreOperations.GetApimEndpointResponse> =
            await this._context.runtime.executeAsync(
                new StoreOperations.GetApimEndpointRequest<StoreOperations.GetApimEndpointResponse>());
        const apimEndpoint: string = response.canceled ? StringExtensions.EMPTY : response.data.result;
        if (StringExtensions.isNullOrWhitespace(apimEndpoint)) {
            throw new Error("Commerce Runtime did not return an APIM endpoint.");
        }

        this._apimEndpoint = apimEndpoint.trim().replace(/\/+$/, StringExtensions.EMPTY);
        return this._apimEndpoint;
    }

    /**
     * Uploads one file to the gateway so the chat request can refer to it by file ID.
     * @param {ISideChatAttachment} attachment The validated base64 file from the POS composer.
     * @param {Record<string, string>} chatHeaders The authenticated chat headers.
     * @param {string} attachmentEndpoint The configured attachment upload endpoint.
     * @returns {Promise<IUploadedAttachment>} The file reference for the chat request.
     */
    private static async _uploadAttachmentAsync(
        attachment: ISideChatAttachment,
        chatHeaders: Record<string, string>,
        attachmentEndpoint: string
    ): Promise<IUploadedAttachment> {
        const formData: FormData = new FormData();
        const bytes: ArrayBuffer = CsuAgentSideChatClient._decodeBase64(attachment.data);
        const file: Blob = new Blob([bytes], { type: attachment.type });
        formData.append("file", file, attachment.name);
        formData.append("purpose", "assistants");

        // The browser supplies multipart/form-data with its boundary. Copy only authentication
        // headers; copying the chat Content-Type would make the upload unreadable.
        const uploadHeaders: Record<string, string> = {
            Authorization: chatHeaders.Authorization
        };
        if (!StringExtensions.isNullOrWhitespace(chatHeaders.DeviceToken)) {
            uploadHeaders.DeviceToken = chatHeaders.DeviceToken;
        }

        const response: Response = await fetch(attachmentEndpoint, {
            method: "POST",
            headers: uploadHeaders,
            body: formData
        });
        const responseText: string = await response.text();
        let result: any = null;
        let isJson: boolean = false;
        if (!StringExtensions.isNullOrWhitespace(responseText)) {
            try {
                result = JSON.parse(responseText);
                isJson = true;
            } catch {
                result = null;
            }
        }

        if (!response.ok) {
            const detail: string =
                CsuAgentSideChatClient.describeGatewayFailure(response, result, responseText, true);
            throw new Error(`Could not upload "${attachment.name}". ${detail}`);
        }

        if (!StringExtensions.isNullOrWhitespace(responseText) && !isJson) {
            throw new Error(`Could not upload "${attachment.name}". The attachment gateway returned a response `
                + "that wasn't valid JSON.");
        }

        const fileId: string = typeof result?.file_id === "string"
            ? result.file_id
            : typeof result?.id === "string" ? result.id : StringExtensions.EMPTY;
        if (StringExtensions.isNullOrWhitespace(fileId)) {
            throw new Error(`Could not upload "${attachment.name}". The attachment gateway did not return a file ID.`);
        }

        return {
            file_id: fileId,
            name: attachment.name,
            type: attachment.type
        };
    }

    /**
     * Decodes a validated base64 attachment into bytes for multipart upload.
     * @param {string} data The base64 file content.
     * @returns {ArrayBuffer} The decoded file.
     */
    private static _decodeBase64(data: string): ArrayBuffer {
        const binary: string = atob(data);
        const bytes: Uint8Array = new Uint8Array(binary.length);
        for (let index: number = 0; index < binary.length; index++) {
            bytes[index] = binary.charCodeAt(index);
        }

        return bytes.buffer;
    }

    /**
     * Says why the gateway turned a request down, in words an associate can act on.
     * @param {Response} response The gateway's response.
     * @param {any} result The response body, when it was JSON.
     * @param {string} responseText The response body as text.
     * @param {boolean} hasAttachments True when the request carried files.
     * @returns {string} A message suitable for display.
     */
    private static describeGatewayFailure(
        response: Response,
        result: any,
        responseText: string,
        hasAttachments: boolean
    ): string {
        if (response.status === 413) {
            return hasAttachments
                ? "The attached files are too large to send. Remove one, or attach a smaller file."
                : "The message is too large to send.";
        }

        // Foundry puts the message under error; APIM's own errors put it at the top.
        const message: unknown = result?.error?.message || result?.message;
        if (typeof message === "string" && !StringExtensions.isNullOrWhitespace(message)) {
            return message;
        }

        const text: string = (responseText || StringExtensions.EMPTY).trim();
        if (text.length > 0 && text.length <= MAX_SHOWN_ERROR_LENGTH && text.charAt(0) !== "<") {
            return text;
        }

        return `Assistant gateway returned ${response.status} ${response.statusText}.`;
    }

    /**
     * Checks the files for a message before anything is sent, so a problem is reported rather than
     * sent on. The panel already keeps to these limits.
     * @param {ReadonlyArray<ISideChatAttachment>} [attachments] The files, if any.
     * @returns {ISideChatAttachment[]} The files, each with a name the agent can be told.
     */
    private static checkAttachments(attachments?: ReadonlyArray<ISideChatAttachment>): ISideChatAttachment[] {
        if (ObjectExtensions.isNullOrUndefined(attachments) || attachments.length === 0) {
            return [];
        }

        if (attachments.length > MAX_ATTACHMENTS) {
            throw new Error(`A message can carry up to ${MAX_ATTACHMENTS} files.`);
        }

        let dataLength: number = 0;
        const files: ISideChatAttachment[] = attachments.map((attachment: ISideChatAttachment): ISideChatAttachment => {
            const name: string = CsuAgentSideChatClient.cleanAttachmentName(attachment?.name);
            if (ATTACHMENT_TYPES.indexOf(attachment?.type) < 0) {
                throw new Error(`"${name}" can't be sent. Attach a photo (PNG, JPEG, WebP or GIF) or a PDF.`);
            }

            if (typeof attachment.data !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(attachment.data)) {
                throw new Error(`"${name}" couldn't be read. Attach it again.`);
            }

            dataLength += attachment.data.length;
            return { name: name, type: attachment.type, data: attachment.data, size: attachment.size };
        });

        if (dataLength > MAX_ATTACHMENT_DATA_LENGTH) {
            throw new Error("The attached files are too large to send. Remove one, or attach a smaller file.");
        }

        return files;
    }

    /**
     * Makes a file name safe to put in the agent's instructions: one line, and not too long.
     * @param {string} [name] The name the file had.
     * @returns {string} The name to use.
     */
    private static cleanAttachmentName(name?: string): string {
        const cleaned: string = (typeof name === "string" ? name : StringExtensions.EMPTY)
            .replace(/[\u0000-\u001f\u007f]+/g, StringExtensions.EMPTY)
            .replace(/\s+/g, " ")
            .trim();
        if (cleaned.length === 0) {
            return "Attachment";
        }

        return cleaned.length > MAX_ATTACHMENT_NAME_LENGTH ? cleaned.substring(0, MAX_ATTACHMENT_NAME_LENGTH) : cleaned;
    }

    /**
     * Rejects a response that ended before the assistant finished its reply, such as one Azure's content
     * filter blocked. Whatever text such a response holds is not the assistant's answer: a blocked reply
     * reads "I'm sorry, but I cannot assist with that request."
     * @param {any} result The gateway's Responses API result.
     * @param {string} correlationId The correlation identifier for logging.
     */
    private _throwIfUnfinished(result: any, correlationId: string): void {
        const status: string = typeof result.status === "string" ? result.status : StringExtensions.EMPTY;
        if (status !== "incomplete" && status !== "failed" && status !== "cancelled") {
            return;
        }

        const reason: string = result.incomplete_details?.reason || result.error?.code || StringExtensions.EMPTY;
        const hits: IContentFilterHit[] = CsuAgentSideChatClient.getContentFilterHits(result);
        const blockedBy: string = hits
            .map((hit: IContentFilterHit) => `${hit.source} ${hit.category}${hit.severity ? ` (${hit.severity})` : ""}`)
            .join(", ");
        this._context.logger.logError(
            `CsuAgentSideChatClient: response ${result.id || "(no id)"} ended ${status}`
            + (StringExtensions.isNullOrWhitespace(reason) ? StringExtensions.EMPTY : ` (${reason})`)
            + (StringExtensions.isNullOrWhitespace(blockedBy)
                ? StringExtensions.EMPTY
                : `; blocked by the content filter for ${blockedBy}`),
            correlationId);

        if (reason === "content_filter") {
            const categories: string[] = hits
                .map((hit: IContentFilterHit) => hit.category)
                .filter((category: string, index: number, all: string[]) => all.indexOf(category) === index);
            throw new Error(categories.length > 0
                ? `Azure's content filter blocked the assistant's reply (flagged: ${categories.join(", ")}).`
                : "Azure's content filter blocked the assistant's reply.");
        }

        if (reason === "max_output_tokens") {
            throw new Error("The assistant's reply was cut off before it finished.");
        }

        throw new Error(result.error?.message
            || `The assistant's reply ended early (${StringExtensions.isNullOrWhitespace(reason) ? status : reason}).`);
    }

    /**
     * Lists what Azure's content filter blocked, from the annotations Foundry adds to a response.
     * @param {any} result The gateway's Responses API result.
     * @returns {IContentFilterHit[]} One entry per blocked category; empty when nothing was blocked.
     */
    private static getContentFilterHits(result: any): IContentFilterHit[] {
        const hits: IContentFilterHit[] = [];
        const filters: any[] = Array.isArray(result.content_filters) ? result.content_filters : [];
        filters.forEach((filter: any): void => {
            const verdicts: any = filter?.content_filter_results;
            if (!filter?.blocked || ObjectExtensions.isNullOrUndefined(verdicts)) {
                return;
            }

            Object.keys(verdicts).forEach((category: string): void => {
                const verdict: any = verdicts[category];
                if (verdict?.filtered) {
                    hits.push({
                        source: filter.source_type || "response",
                        category: category.replace(/_/g, " "),
                        severity: typeof verdict.severity === "string" ? verdict.severity : undefined
                    });
                }
            });
        });

        return hits;
    }

    /**
     * Names the tools a response called that can change something, such as the cart.
     * @param {any[]} output The Responses API output items.
     * @returns {string[]} The distinct tool names; empty when the response only looked things up.
     */
    private static getChangingToolCalls(output: any[]): string[] {
        const names: string[] = [];
        output.forEach((item: any): void => {
            if (item?.type === "mcp_call"
                && typeof item.name === "string"
                && CHANGING_TOOL_PATTERN.test(item.name)
                && names.indexOf(item.name) < 0) {
                names.push(item.name);
            }
        });

        return names;
    }

    /**
     * Reads the reply out of the gateway's response, without changing the conversation.
     * @param {any} result The gateway's Responses API result.
     * @param {ReadonlyArray<string>} [supportedActions] Enables prose fallback for interactive chat only.
     * @returns {IAssistantReply | null} The reply, or null when no message held a valid envelope.
     */
    private static readReply(result: any, supportedActions?: ReadonlyArray<string>): IAssistantReply | null {
        const output: any[] = result.output || [];
        const toolActivities: IAgentToolActivity[] = CsuAgentSideChatClient.getToolActivities(output);
        const parts: string[] = [];
        output.forEach((item: any): void => {
            if (item?.type === "message" && (!item.role || item.role === "assistant")) {
                (item.content || []).forEach((content: any): void => {
                    if (typeof content?.text === "string") {
                        parts.push(content.text);
                    }
                });
            }
        });

        const outputText: string = result.output_text || parts.join("\n");
        if (StringExtensions.isNullOrWhitespace(outputText)) {
            return { reply: { displayMessage: "The assistant did not return a response.", posActions: [] } };
        }

        // Responses API output_text concatenates every assistant message. Tool-driven responses
        // can contain conversational text around the final JSON envelope, so inspect individual
        // messages from newest to oldest before trying the aggregate value.
        const candidates: string[] = parts.slice().reverse();
        if (candidates.indexOf(outputText) < 0) {
            candidates.push(outputText);
        }

        for (const candidate of candidates) {
            const envelope: IAgentResponseEnvelope | null = CsuAgentSideChatClient.tryParseEnvelope(candidate);
            if (envelope) {
                return {
                    reply: {
                        displayMessage: envelope.displayMessage,
                        posActions: envelope.posActions,
                        toolActivities: toolActivities
                    },
                    conversationId: envelope.conversationId
                };
            }
        }

        // A structured reply owns the product selection, even when it deliberately has no actions.
        // Do not recover actions from a malformed envelope or from background/one-off requests.
        if (!supportedActions || candidates.some((candidate: string): boolean =>
            /^\s*(?:\{|\[|```)/.test(candidate))) {
            return null;
        }

        return {
            reply: {
                displayMessage: outputText,
                posActions: supportedActions.indexOf(PRODUCT_RECOMMENDATIONS_ACTION) >= 0
                    ? CsuAgentSideChatClient.readPreparedSearchActions(output)
                    : [],
                toolActivities: toolActivities
            }
        };
    }

    /**
     * Reads display-only candidates from the latest search call, never from an older failed refinement.
     */
    private static readPreparedSearchActions(output: any[]): IAgentPosAction[] {
        let search: any;
        for (let index: number = output.length - 1; index >= 0; index--) {
            const item: any = output[index];
            if (item?.type === "mcp_call"
                && (item.name === "extension_search_products_with_variants"
                    || item.name === "search_products_with_variants")) {
                search = item;
                break;
            }
        }
        if (!search || search.status !== "completed" || search.error || typeof search.output !== "string") {
            return [];
        }

        let result: any;
        try {
            result = JSON.parse(search.output);
        } catch {
            return [];
        }

        if (!result || result.error || result.isError
            || !Array.isArray(result.products) || result.products.length > 20
            || !Array.isArray(result.posActions) || result.posActions.length !== 1) {
            return [];
        }

        const action: any = result.posActions[0];
        const productIds: any = action?.details?.productIds;
        if (action?.action !== PRODUCT_RECOMMENDATIONS_ACTION
            || !Array.isArray(productIds) || productIds.length === 0 || productIds.length > 20
            || !productIds.every((id: unknown): boolean =>
                typeof id === "number" && id > 0 && id <= 9007199254740991 && Math.floor(id) === id
                && result.products.some((product: any): boolean => product?.productId === id))) {
            return [];
        }

        // Only identifiers cross into the executor; Commerce still owns card data and Add to cart.
        return [{ action: PRODUCT_RECOMMENDATIONS_ACTION, details: { productIds: productIds.slice() } }];
    }

    /**
     * Reads and validates one possible reply envelope.
     * @param {string} responseJson The serialized reply.
     * @returns {IAgentResponseEnvelope | null} The envelope, or null when the candidate is not a valid one.
     */
    private static tryParseEnvelope(responseJson: string): IAgentResponseEnvelope | null {
        if (StringExtensions.isNullOrWhitespace(responseJson)) {
            return null;
        }

        let envelope: IAgentResponseEnvelope;
        try {
            envelope = JSON.parse(responseJson) as IAgentResponseEnvelope;
        } catch {
            return null;
        }

        if (ObjectExtensions.isNullOrUndefined(envelope)
            || (envelope.conversationId !== undefined && typeof envelope.conversationId !== "string")
            || typeof envelope.displayMessage !== "string"
            || StringExtensions.isNullOrWhitespace(envelope.displayMessage)
            || !Array.isArray(envelope.posActions)) {
            return null;
        }

        return envelope;
    }

    /**
     * Identifies an explicit product-discovery turn that should start a new Foundry thread instead
     * of inheriting assumptions from the previous search. Short follow-ups intentionally do not
     * match, so requests such as "Which one is best?" retain conversation context.
     * @param prompt The operator's current message.
     * @returns True when the prompt clearly starts a new product search.
     */
    private static startsNewProductSearch(prompt: string): boolean {
        return /^\s*(?:find\b|search(?:\s+for)?\b|look(?:ing)?\s+for\b|the\s+(?:\d+|one|two|three|four|five)\s+best\b)/i
            .test(prompt);
    }

    /**
     * Extracts safe, display-only metadata for Commerce MCP calls. Tool output and arbitrary
     * arguments are never exposed in the chat.
     * @param output The Responses API output items.
     * @returns Completed and failed tool activities, grouped by tool name and safe detail.
     */
    private static getToolActivities(output: any[]): IAgentToolActivity[] {
        const activitiesByKey: { [key: string]: IAgentToolActivity } = {};

        output.forEach((item: any): void => {
            if (item?.type !== "mcp_call" || typeof item.name !== "string") {
                return;
            }

            const detail: string | undefined = CsuAgentSideChatClient.getSafeToolDetail(item.arguments);
            const status: "completed" | "failed" = item.status === "completed" ? "completed" : "failed";
            const key: string = `${item.name}|${detail ?? StringExtensions.EMPTY}|${status}`;
            const existing: IAgentToolActivity | undefined = activitiesByKey[key];

            if (existing) {
                existing.count += 1;
            } else {
                activitiesByKey[key] = {
                    name: item.name,
                    detail: detail,
                    count: 1,
                    status: status
                };
            }
        });

        return Object.keys(activitiesByKey).map((key: string) => activitiesByKey[key]);
    }

    /**
     * Reads only non-sensitive numeric tuning arguments that are useful to an associate.
     * @param argumentsJson The serialized MCP tool arguments.
     * @returns A short detail string, or undefined when there is nothing safe and useful to show.
     */
    private static getSafeToolDetail(argumentsJson: unknown): string | undefined {
        if (typeof argumentsJson !== "string" || StringExtensions.isNullOrWhitespace(argumentsJson)) {
            return undefined;
        }

        let args: any;
        try {
            args = JSON.parse(argumentsJson);
        } catch {
            return undefined;
        }

        const safeKeys: string[] = ["maxStores", "radius", "top", "quantity"];
        const details: string[] = [];
        safeKeys.forEach((key: string): void => {
            const value: unknown = args?.[key];
            if (typeof value === "number" && isFinite(value)) {
                details.push(`${key} ${value}`);
            }
        });

        return details.length > 0 ? details.join(" \u00b7 ") : undefined;
    }

    /**
     * Reads the current cart so the agent can ground answers in the active transaction.
     * @param {string} correlationId The correlation identifier for logging.
     * @returns {Promise<ProxyEntities.Cart | undefined>} The current cart, or undefined when there is no cart.
     */
    private async _getCurrentCartAsync(correlationId: string): Promise<ProxyEntities.Cart | undefined> {
        const request: GetCurrentCartClientRequest<GetCurrentCartClientResponse> =
            new GetCurrentCartClientRequest<GetCurrentCartClientResponse>();

        try {
            const result: ClientEntities.ICancelableDataResult<GetCurrentCartClientResponse> =
                await this._context.runtime.executeAsync(request);

            if (result.canceled || ObjectExtensions.isNullOrUndefined(result.data)) {
                return undefined;
            }

            return result.data.result ?? undefined;
        } catch (error) {
            // A missing cart is normal (the operator may be on the home screen), so this is not fatal.
            this._context.logger.logInformational(
                `CsuAgentSideChatClient could not read the current cart: ${JSON.stringify(error)}`,
                correlationId);

            return undefined;
        }
    }

    /**
     * Extracts a readable message from whatever POS rejected with.
     * @param {unknown} error The rejection value.
     * @returns {string} A message suitable for display.
     */
    private static describeError(error: unknown): string {
        if (ObjectExtensions.isNullOrUndefined(error)) {
            return "The assistant endpoint did not return a response.";
        }

        // Errors surface either as a single error entity or as an array of them.
        const candidate: any = Array.isArray(error) ? error[0] : error;
        if (ObjectExtensions.isNullOrUndefined(candidate)) {
            return "The assistant endpoint did not return a response.";
        }

        const message: string = candidate.formattedMessage
            || candidate.LocalizedMessage
            || candidate.ErrorMessage
            || candidate.message
            || StringExtensions.EMPTY;
        const code: string = candidate.ErrorCode || candidate.errorCode || StringExtensions.EMPTY;

        if (!StringExtensions.isNullOrWhitespace(message)) {
            return StringExtensions.isNullOrWhitespace(code) ? message : `${message} (${code})`;
        }

        if (!StringExtensions.isNullOrWhitespace(code)) {
            return code;
        }

        try {
            return JSON.stringify(error);
        } catch (serializationError) {
            return "An unreadable error was returned by the assistant endpoint.";
        }
    }
}
