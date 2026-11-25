/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The backend contract for the docked chat side panel.
 */

import { IAgentCartSnapshot, IAgentPosAction, IAgentToolActivity } from "./agentContracts";

/** A file the operator attached to a message, ready to send. */
export interface ISideChatAttachment {
    /** The file's name, as the operator's device named it. */
    name: string;
    /**
     * The media type of `data`: "image/jpeg", "image/png", "image/webp", "image/gif" or
     * "application/pdf". The panel sends every photo as JPEG, shrunk on the device.
     */
    type: string;
    /** The content, base64 encoded, without a `data:` prefix. */
    data: string;
    /** The size of the content before encoding, in bytes. */
    size: number;
}

/** What the conversation shows of a file sent with a message. */
export interface ISideChatAttachmentPreview {
    name: string;
    type: string;
    /** A small copy of a photo, as a data URL. Absent for a PDF. */
    thumbnailUrl?: string;
}

/** A single message in the side panel conversation. */
export interface SideChatMessage {
    id: string;
    role: "user" | "assistant";
    /** Empty on an operator's message that only sent files. */
    text: string;
    toolActivities?: ReadonlyArray<IAgentToolActivity>;
    /** Set on an assistant message that POS asked for on its own, rather than one answering the operator. */
    origin?: "cartSuggestion";
    /** The files the operator sent with the message. Only on the operator's messages. */
    attachments?: ReadonlyArray<ISideChatAttachmentPreview>;
}

/**
 * What a backend answers with: something to say, and optionally what POS should do about it.
 */
export interface ISideChatReply {
    /** The conversational reply shown in the panel. */
    displayMessage: string;
    /** Actions for POS to run. Empty when the reply is purely conversational. */
    posActions?: IAgentPosAction[];
    /** Sanitized Commerce tool calls made while producing the reply. */
    toolActivities?: ReadonlyArray<IAgentToolActivity>;
}

/** What POS asks about when it checks the cart on its own, without the operator typing anything. */
export interface ICartSuggestionRequest {
    /** The transaction the snapshot was taken from. */
    cartId: string;
    /** The cart when the check started. */
    cart: IAgentCartSnapshot;
}

/** The agent's answer to an automatic cart check. */
export interface ICartSuggestionReply extends ISideChatReply {
    /**
     * Makes this reply part of the agent conversation, so a follow-up question can refer to it. Call it
     * once the reply is shown; a reply that is never shown leaves the conversation as it was. Does
     * nothing when the operator has sent a message since the check started, because the conversation
     * has moved on without it.
     */
    acceptIntoConversation?: () => void;
}

/** Backend used to answer prompts typed into the side panel. */
export interface ISideChatClient {
    /**
     * Optional. True when sendAsync can send files with a prompt. The panel only lets the operator
     * attach files when it is.
     */
    readonly acceptsAttachments?: boolean;

    /**
     * Answers a prompt.
     * @param prompt The text the operator typed. Empty when they only sent files.
     * @param history The conversation so far, including the prompt.
     * @param viewContext The POS view that was open when the prompt was sent, or null when unknown.
     * @param attachments The files the operator attached, when the client accepts attachments and
     * there are any.
     * @returns The reply and any actions POS should run.
     */
    sendAsync(
        prompt: string,
        history: ReadonlyArray<SideChatMessage>,
        viewContext: string | null,
        attachments?: ReadonlyArray<ISideChatAttachment>
    ): Promise<ISideChatReply>;

    /**
     * Optional. Asks which products would go well with the current cart. The panel calls this when POS
     * reports that an item was added to the cart; the operator did not type anything.
     * @param request The cart to ask about.
     * @param viewContext The POS view that is open, or null when unknown.
     * @returns The reply and the actions that show the suggestions.
     */
    suggestForCartAsync?(request: ICartSuggestionRequest, viewContext: string | null): Promise<ICartSuggestionReply>;

    /**
     * Optional. Forgets the conversation so far, so the next prompt starts a new one. The panel calls
     * this when the operator starts a new chat. A reply to an earlier prompt that arrives afterwards is
     * not shown, and should not carry the old conversation on.
     */
    startNewConversation?(): void;
}

/** A starter prompt that needs a file, such as a photo, before it can be sent. */
export interface ISideChatSuggestion {
    /** The prompt, as shown and as put in the message box. */
    text: string;
    /**
     * A word in the text that names the file to attach. It is shown as a link, and choosing the
     * suggestion puts the text in the message box and opens the file picker rather than sending it.
     * The suggestion is hidden when the client can't take files.
     */
    attachmentWord?: string;
}

/** A starter prompt: plain text that is sent as it is, or one that needs a file first. */
export type SideChatSuggestion = string | ISideChatSuggestion;

/**
 * Starter prompts shown in the panel's rest state. The first three show at once, and the rest behind
 * "See more".
 *
 * These are the ones the sample backend recognises, so the demo works from a standing start without
 * anyone having to guess what to type. "Which one is best?" is a follow-up to the skiing prompt, which
 * is what exercises the conversation id and the comparison action.
 */
export const DEFAULT_SIDE_CHAT_SUGGESTIONS: ReadonlyArray<SideChatSuggestion> = [
    "Find gear needed for skiing",
    { text: "Find products like the one in this photo", attachmentWord: "photo" },
    "Create a beach vacation cart for me with things I could wear for it",
    "Which one is best?"
];
