/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Prepares photos and adds their items through the Counter order view's assistant gateway.
 *
 * The photo is prepared on the device the way the side chat prepares one: redrawn as a JPEG on a white
 * background, at most 1600 pixels on its longest side and about 400 KB. That keeps the request inside what the
 * gateway can read, and leaves the photo's metadata, such as where it was taken, behind.
 *
 * Photo additions run outside the side chat conversation. Commerce tools resolve and add the items to the
 * active cart; POS reloads that cart and checks the changes before reporting the result. The separate
 * read-only item-list reader remains available to callers that only need extraction.
 *
 * Files are read into data URLs rather than object URLs, because Cloud POS's content security policy allows
 * data: images but not blob: ones.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ProxyEntities } from "PosApi/Entities";
import {
    CreateEmptyCartServiceRequest,
    CreateEmptyCartServiceResponse,
    GetCurrentCartClientRequest,
    GetCurrentCartClientResponse,
    RefreshCartClientRequest,
    RefreshCartClientResponse
} from "PosApi/Consume/Cart";
import {
    IAgentPosAction,
    IAgentRequestEnvelope,
    IAgentStoreContext,
    ISideChatAttachment,
    ISideChatReply
} from "ContosoSideChat";
import CsuAgentSideChatClient, { IPhotoCartChange, IPhotoCartReply } from "../../../Extend/Agent/CsuAgentSideChatClient";
import { getCurrentStoreAsync } from "../../../Extend/Agent/CurrentStoreHelper";
import { READ_ITEM_LIST_ACTION } from "../../../Extend/Agent/posActionCatalogue";
import { describeError, IPhotoItemLine, PhotoLineProblem } from "./BulkItemEntry";
import { MAX_BULK_QUANTITY } from "./BulkItemParser";

const KB: number = 1024;
const MB: number = 1024 * KB;

/** The largest photo the dialog opens. A bigger one takes too long to shrink on a POS device. */
const MAX_PHOTO_INPUT_BYTES: number = 20 * MB;

/** What a photo is shrunk to, at most, when it can be. */
const MAX_PHOTO_BYTES: number = 400 * KB;

/**
 * Sizes and qualities to try, largest first, until a photo is small enough. Even the last keeps a typed or
 * handwritten list legible.
 */
const PHOTO_ATTEMPTS: Array<{ edge: number; quality: number }> = [
    { edge: 1600, quality: 0.85 },
    { edge: 1600, quality: 0.72 },
    { edge: 1280, quality: 0.72 },
    { edge: 1024, quality: 0.7 },
    { edge: 800, quality: 0.65 }
];

/** The longest side of the copy shown while the list is read, in pixels. */
const PREVIEW_EDGE_PX: number = 320;

/** How long a photo's name can be, in characters. */
const MAX_NAME_LENGTH: number = 80;

/** The media types a photo can arrive as. Every one is sent as JPEG. */
const PHOTO_TYPES: string[] = ["image/png", "image/jpeg", "image/jpg", "image/pjpeg", "image/webp", "image/gif"];

/** The extensions of those types, for devices that don't report a file's type. */
const PHOTO_EXTENSIONS: string[] = ["png", "jpg", "jpeg", "webp", "gif"];

const SUPPORTED_PHOTOS_HINT: string = "Choose a photo (PNG, JPEG, WebP or GIF).";

/** What the associate asks the agent. Nothing shows it; the agent reads it with the photo. */
const READ_REQUEST_TEXT: string = "Read the item list in this photo so I can add the items to the cart.";

const ADD_REQUEST_TEXT: string = "Add the items in this photo to the active POS cart identified by cartId, "
    + "using this request's store.channelId. The associate has requested these additions. "
    + "Read each item ID exactly, preserving leading zeros, and its quantity. "
    + "Use extension_search_products_with_variants to find products whose ItemId exactly matches each photo ID; "
    + "never substitute similar items. Use get_cart to read this cart before changing it. "
    + "For a new product call add_product_to_cart with the quantity in the photo. "
    + "For a product already in the cart, use update_cart_line with its existing quantity PLUS the photo quantity. "
    + "Combine repeated items from the photo. Only use this existing cart; never create another cart. "
    + "Do not remove items, change fulfillment, apply discounts, or check out. "
    + "Do not guess unreadable IDs, quantities or variant options; skip those lines and explain what was not added. "
    + "Perform the additions with Commerce tools, not POS actions or recommendation cards. "
    + "Then briefly report what was added and anything that could not be added. Do not ask for another confirmation.";

export interface IPhotoCartResult {
    cart: ProxyEntities.Cart;
    summary: string;
    message: string;
    needsAttention: boolean;
}

/** The view the request comes from, named the way POS names extension views to the side chat. */
const COUNTER_ORDER_VIEW_NAME: string = "Contoso_Contoso.PosExtensions_CounterOrderView";

/**
 * The most lines read from one reply. More than one bulk add takes are kept, so the associate is told the list
 * is too long and can trim it, rather than losing lines without knowing.
 */
const MAX_LINES_READ: number = 500;

/** The most characters of a line as written that are kept. */
const MAX_LINE_TEXT_LENGTH: number = 120;

/** The longest item ID accepted. A longer one is not an item ID, and shortening it would make it another one. */
const MAX_ITEM_ID_LENGTH: number = 40;

/** The most characters of the agent's message shown. */
const MAX_MESSAGE_LENGTH: number = 600;

/** The largest whole number a double holds exactly, as Number.MAX_SAFE_INTEGER, which ES5 doesn't have. */
const MAX_SAFE_INTEGER: number = 9007199254740991;

/** Shown when the agent read no list and said nothing. */
const NO_LIST_MESSAGE: string = "Copilot didn't find an item list in the photo. Try a clearer photo, or paste the list.";

/** Shown when the agent returned a list with no line POS can use. */
const UNUSABLE_LIST_MESSAGE: string = "Copilot couldn't read any items from the photo. Try a clearer photo, or paste the list.";

/** Why a line can't be added as written, as the agent may give it. */
const PROBLEMS: PhotoLineProblem[] = ["unreadable", "noQuantity", "notFound", "ambiguous"];

/**
 * A photo of an item list, ready to send.
 */
export interface IItemListPhoto {
    /** The photo's name, as the associate's device gave it, tidied. */
    readonly name: string;
    /** The photo as it is sent: a JPEG of about 400 KB at most. */
    readonly attachment: ISideChatAttachment;
    /** A small copy of the photo, as a data URL, or an empty string when none could be drawn. */
    readonly previewUrl: string;
}

/**
 * The item list read from a photo.
 */
export interface IItemListReading {
    /** The lines that name an item, in the order written. Empty when no list was read. */
    readonly lines: IPhotoItemLine[];
    /** What to tell the associate when no list was read, as plain text. Empty when lines were read. */
    readonly message: string;
}

/**
 * Says whether a file is a photo the dialog can read.
 * @param file The file.
 * @returns True for a PNG, JPEG, WebP or GIF, by its type or, when the device gives none, its extension.
 */
export function isPhotoFile(file: File): boolean {
    if (!file) {
        return false;
    }

    const type: string = (file.type || "").toLowerCase();
    if (PHOTO_TYPES.indexOf(type) >= 0) {
        return true;
    }

    if (type.length > 0 && type !== "application/octet-stream") {
        return false;
    }

    const match: RegExpExecArray | null = /\.([a-z0-9]+)$/i.exec(file.name || "");
    return !!match && PHOTO_EXTENSIONS.indexOf(match[1].toLowerCase()) >= 0;
}

/**
 * Gets a photo ready to send: redrawn as a JPEG of about 400 KB at most, with a small copy to show.
 * @param file The photo.
 * @returns The photo as it will be sent.
 * @throws An Error whose message can be shown to the associate as it is.
 */
export async function preparePhotoAsync(file: File): Promise<IItemListPhoto> {
    const name: string = cleanName(file ? file.name : "");
    if (!isPhotoFile(file)) {
        throw new Error(`"${name}" can't be read. ${SUPPORTED_PHOTOS_HINT}`);
    }

    if (file.size > MAX_PHOTO_INPUT_BYTES) {
        throw new Error(`"${name}" is larger than 20 MB. Choose a smaller photo.`);
    }

    let dataUrl: string;
    try {
        dataUrl = await readAsDataUrl(file);
    } catch {
        throw new Error(`"${name}" couldn't be read. Try choosing it again.`);
    }

    let image: HTMLImageElement;
    try {
        image = await loadImage(dataUrl);
    } catch {
        throw new Error(`"${name}" couldn't be opened as a photo. ${SUPPORTED_PHOTOS_HINT}`);
    }

    let data: string = "";
    for (const attempt of PHOTO_ATTEMPTS) {
        data = base64Of(drawJpeg(image, attempt.edge, attempt.quality));
        if (data.length > 0 && decodedSize(data) <= MAX_PHOTO_BYTES) {
            break;
        }
    }

    if (data.length === 0) {
        throw new Error(`"${name}" couldn't be prepared. Try another photo.`);
    }

    return {
        name: name,
        attachment: { name: name, type: "image/jpeg", data: data, size: decodedSize(data) },
        previewUrl: drawJpeg(image, PREVIEW_EDGE_PX, 0.8)
    };
}

/**
 * Asks the agent to read the item list in a photo. The request is one of its own: it leaves the side chat's
 * conversation as it is, and offers the agent only the readItemList action.
 * @param context The extension context.
 * @param photo The photo, prepared.
 * @param correlationId The correlation identifier for logging.
 * @returns The lines read, or what to tell the associate when there are none.
 * @throws An Error saying why the agent couldn't be asked or didn't answer.
 */
export async function readItemListAsync(
    context: IExtensionContext,
    photo: IItemListPhoto,
    correlationId: string
): Promise<IItemListReading> {
    const envelope: IAgentRequestEnvelope = {
        text: READ_REQUEST_TEXT,
        conversationId: "",
        cartId: "",
        currentView: COUNTER_ORDER_VIEW_NAME,
        supportedActions: [READ_ITEM_LIST_ACTION]
    };

    // The agent looks up a line that names a product without an item ID in this store's catalog.
    const store: IAgentStoreContext | undefined = await getCurrentStoreAsync(context, correlationId);
    if (store) {
        envelope.store = store;
    }

    const reply: ISideChatReply = await CsuAgentSideChatClient.askOnceAsync(context, envelope, [photo.attachment], correlationId);
    return readItemListReply(reply);
}

export async function addPhotoItemsToCartAsync(
    context: IExtensionContext,
    photo: IItemListPhoto,
    correlationId: string
): Promise<IPhotoCartResult> {
    const store: IAgentStoreContext | undefined = await getCurrentStoreAsync(context, correlationId);
    if (!store || !(store.channelId > 0)) {
        throw new Error("POS couldn't identify the store. No photo items were added.");
    }

    let current = await context.runtime.executeAsync<GetCurrentCartClientResponse>(
        new GetCurrentCartClientRequest<GetCurrentCartClientResponse>(correlationId));
    if (current.canceled) {
        throw new Error("Reading the active cart was canceled. No photo items were added.");
    }

    if (!current.data?.result?.Id) {
        const created = await context.runtime.executeAsync<CreateEmptyCartServiceResponse>(
            new CreateEmptyCartServiceRequest(correlationId));
        if (created.canceled) {
            throw new Error("Starting the active cart was canceled. No photo items were added.");
        }

        current = await context.runtime.executeAsync<GetCurrentCartClientResponse>(
            new GetCurrentCartClientRequest<GetCurrentCartClientResponse>(correlationId));
        if (current.canceled || !created.data?.cart?.Id || current.data?.result?.Id !== created.data.cart.Id) {
            throw new Error("POS couldn't start an active cart. No photo items were added.");
        }
    }

    if ((current.data.result.CartLines || []).some((line: ProxyEntities.CartLine): boolean =>
        !line.IsVoided && line.Quantity < 0)) {
        throw new Error("Finish the return before adding items from a photo. No photo items were added.");
    }

    const cartId: string = current.data.result.Id;
    const before: { [productId: number]: number } = cartQuantities(current.data.result);
    let reply: IPhotoCartReply | undefined;
    let failure: string = "";
    try {
        reply = await CsuAgentSideChatClient.addPhotoItemsToCartAsync(context, {
            text: ADD_REQUEST_TEXT,
            conversationId: "",
            cartId: cartId,
            currentView: COUNTER_ORDER_VIEW_NAME,
            supportedActions: [],
            store: store
        }, photo.attachment, correlationId);
    } catch (error) {
        failure = describeError(error) || "The photo request did not complete.";
    }

    // A failed or interrupted response can still have added items. Always reload; never retry the write.
    let cart: ProxyEntities.Cart | undefined;
    try {
        const refreshed = await context.runtime.executeAsync<RefreshCartClientResponse>(
            new RefreshCartClientRequest<RefreshCartClientResponse>(correlationId));
        cart = refreshed.canceled ? undefined : refreshed.data?.result;
    } catch {
        cart = undefined;
    }

    if (!cart) {
        throw new Error("The photo request may have changed the cart, but POS couldn't refresh it. "
            + "Check the transaction before trying the photo again.");
    }

    if (cart.Id !== cartId) {
        throw new Error("The active transaction changed while Copilot was adding items. "
            + "Check the original transaction before trying the photo again.");
    }

    const expected: { [productId: number]: number } = { ...before };
    let needsAttention: boolean = !reply || reply.hasFailures || reply.changes.length === 0;
    (reply?.changes || []).forEach((change: IPhotoCartChange): void => {
        const previous: number = expected[change.productId] || 0;
        if (change.action === "update_cart_line" && change.quantity <= previous) {
            needsAttention = true;
        }

        expected[change.productId] = change.action === "add_product_to_cart"
            ? previous + change.quantity
            : change.quantity;
    });

    const after: { [productId: number]: number } = cartQuantities(cart);
    const productIds: string[] = Object.keys(expected).concat(Object.keys(after));
    let addedQuantity: number = 0;
    Object.keys(after).forEach((id: string): void => {
        addedQuantity += Math.max(0, after[+id] - (before[+id] || 0));
    });
    if (productIds.some((id: string): boolean => Math.abs((expected[+id] || 0) - (after[+id] || 0)) > 0.0001)
        || addedQuantity <= 0) {
        needsAttention = true;
    }

    const summary: string = addedQuantity > 0
        ? `Cart refreshed: ${addedQuantity} additional ${addedQuantity === 1 ? "unit" : "units"}.`
        : "Cart refreshed. No added quantities were confirmed.";
    const message: string = cleanMessage(failure || reply?.displayMessage || "Review the updated cart.");
    return {
        cart: cart,
        summary: summary,
        message: needsAttention
            ? `${message} Some or all additions could not be verified. Check the cart before trying again.`
            : message,
        needsAttention: needsAttention
    };
}

function cartQuantities(cart: ProxyEntities.Cart): { [productId: number]: number } {
    const quantities: { [productId: number]: number } = {};
    (cart.CartLines || []).forEach((line: ProxyEntities.CartLine): void => {
        if (!line.IsVoided && line.ProductId > 0 && typeof line.Quantity === "number" && isFinite(line.Quantity)
            && line.Quantity > 0) {
            quantities[line.ProductId] = (quantities[line.ProductId] || 0) + line.Quantity;
        }
    });
    return quantities;
}

/**
 * Reads the item list out of the agent's reply. Every value is checked, because the reply is the agent's
 * reading of a photo: a line with anything POS can't use is kept with what can be used, so the associate sees it.
 * @param reply The agent's reply.
 * @returns The lines read, or what to tell the associate when there are none.
 */
export function readItemListReply(reply: ISideChatReply | undefined): IItemListReading {
    const actions: IAgentPosAction[] = reply && Array.isArray(reply.posActions) ? reply.posActions : [];
    let found: boolean = false;
    let lines: IPhotoItemLine[] = [];
    for (const action of actions) {
        if (lines.length === 0 && isReadItemListAction(action)) {
            found = true;
            lines = readLines(action.details);
        }
    }

    if (lines.length > 0) {
        return { lines: lines, message: "" };
    }

    // The agent's words say why it found no list; a list it returned with nothing usable in it says nothing useful.
    const message: string = found ? "" : cleanMessage(reply ? reply.displayMessage : "");
    return { lines: [], message: message.length > 0 ? message : found ? UNUSABLE_LIST_MESSAGE : NO_LIST_MESSAGE };
}

function isReadItemListAction(action: IAgentPosAction): boolean {
    return !!action
        && typeof action.action === "string"
        && action.action.trim().toLowerCase() === READ_ITEM_LIST_ACTION.toLowerCase();
}

function readLines(details: unknown): IPhotoItemLine[] {
    const itemList: unknown = isObject(details) ? (details as { [name: string]: unknown }).itemList : undefined;
    const rawLines: unknown = isObject(itemList) ? (itemList as { [name: string]: unknown }).lines : undefined;
    if (!Array.isArray(rawLines)) {
        return [];
    }

    const lines: IPhotoItemLine[] = [];
    for (const rawLine of rawLines.slice(0, MAX_LINES_READ)) {
        const line: IPhotoItemLine | undefined = readLine(rawLine, lines.length + 1);
        if (line) {
            lines.push(line);
        }
    }

    return lines;
}

function readLine(rawLine: unknown, position: number): IPhotoItemLine | undefined {
    if (!isObject(rawLine)) {
        return undefined;
    }

    const fields: { [name: string]: unknown } = rawLine as { [name: string]: unknown };
    const itemId: string | undefined = readItemId(fields.itemId);
    const problem: PhotoLineProblem | undefined = readProblem(fields.problem);
    const text: string = clamp(cleanText(fields.text), MAX_LINE_TEXT_LENGTH);
    if (text.length === 0 && !itemId && !problem) {
        return undefined;
    }

    return {
        text: text.length > 0 ? text : itemId || `Line ${position}`,
        itemId: itemId,
        productId: isRecordId(fields.productId) ? fields.productId : undefined,
        quantity: readQuantity(fields.quantity),
        problem: problem
    };
}

function readItemId(value: unknown): string | undefined {
    // An item ID of digits may come back as a number.
    const raw: unknown = typeof value === "number" && isRecordId(value) ? String(value) : value;
    const itemId: string = cleanText(raw);
    return itemId.length > 0 && itemId.length <= MAX_ITEM_ID_LENGTH ? itemId : undefined;
}

function readQuantity(value: unknown): number | undefined {
    let quantity: number = NaN;
    if (typeof value === "number") {
        quantity = value;
    } else if (typeof value === "string" && /^\s*\d+\s*$/.test(value)) {
        quantity = parseInt(value, 10);
    }

    return Math.floor(quantity) === quantity && quantity >= 1 && quantity <= MAX_BULK_QUANTITY ? quantity : undefined;
}

function readProblem(value: unknown): PhotoLineProblem | undefined {
    if (value === undefined || value === null || value === "") {
        return undefined;
    }

    const wanted: string = typeof value === "string" ? value.trim().toLowerCase() : "";
    for (const problem of PROBLEMS) {
        if (problem.toLowerCase() === wanted) {
            return problem;
        }
    }

    // A reason POS doesn't know still means the line can't be added as written.
    return "unreadable";
}

/** Makes text one line with no control characters, or an empty string when it isn't text. */
function cleanText(value: unknown): string {
    return typeof value === "string"
        ? value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
        : "";
}

/** Makes the agent's message plain text: no Markdown, links or citation marks. */
function cleanMessage(value: unknown): string {
    if (typeof value !== "string") {
        return "";
    }

    const text: string = value
        .replace(/\u3010[^\u3011]*\u3011/g, "")
        .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
        .replace(/^\s*(?:[-*+]|#{1,6}|\d+\.)\s+/gm, "")
        .replace(/\*\*|__|`/g, "");
    return clamp(cleanText(text), MAX_MESSAGE_LENGTH);
}

function clamp(text: string, maxLength: number): string {
    return text.length > maxLength ? `${text.slice(0, maxLength - 1)}\u2026` : text;
}

function isObject(value: unknown): boolean {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

function isRecordId(value: unknown): value is number {
    return typeof value === "number" && isFinite(value) && value > 0 && value <= MAX_SAFE_INTEGER && Math.floor(value) === value;
}

/**
 * Tidies a photo's name for the dialog and the agent, keeping its extension when it is shortened.
 */
function cleanName(name: string): string {
    const cleaned: string = (typeof name === "string" ? name : "").replace(/[\u0000-\u001f\u007f]+/g, "").replace(/\s+/g, " ").trim();
    const value: string = cleaned.length > 0 ? cleaned : "Pasted image";
    if (value.length <= MAX_NAME_LENGTH) {
        return value;
    }

    const dot: number = value.lastIndexOf(".");
    const extension: string = dot > 0 && value.length - dot <= 6 ? value.slice(dot) : "";
    return `${value.slice(0, MAX_NAME_LENGTH - extension.length - 1)}\u2026${extension}`;
}

function readAsDataUrl(file: Blob): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: unknown) => void): void => {
        const reader: FileReader = new FileReader();
        reader.onload = (): void => resolve(typeof reader.result === "string" ? reader.result : "");
        reader.onerror = (): void => reject(reader.error || new Error("The file couldn't be read."));
        reader.readAsDataURL(file);
    });
}

/** Takes the base64 content out of a data URL, or returns an empty string when there is none. */
function base64Of(dataUrl: string): string {
    const comma: number = dataUrl.indexOf(",");
    return comma >= 0 && /;base64,/.test(dataUrl.slice(0, comma + 1)) ? dataUrl.slice(comma + 1) : "";
}

/** Works out how many bytes base64 content holds before encoding. */
function decodedSize(base64: string): number {
    const length: number = base64.length;
    let padding: number = 0;
    if (length > 0 && base64.charAt(length - 1) === "=") {
        padding = length > 1 && base64.charAt(length - 2) === "=" ? 2 : 1;
    }

    return Math.floor(length * 3 / 4) - padding;
}

/** Opens a photo, once the engine has decoded it. */
function loadImage(source: string): Promise<HTMLImageElement> {
    return new Promise<HTMLImageElement>((resolve: (value: HTMLImageElement) => void, reject: (reason: unknown) => void): void => {
        const image: HTMLImageElement = new Image();
        image.onload = (): void => {
            if (image.naturalWidth > 0 && image.naturalHeight > 0) {
                resolve(image);
            } else {
                reject(new Error("The photo has no size."));
            }
        };
        image.onerror = (): void => reject(new Error("The photo couldn't be decoded."));
        image.src = source;
    });
}

/**
 * Redraws a photo as a JPEG no larger than the given size. Engines turn a photo upright from its metadata as they
 * draw it, and the metadata is not copied.
 * @returns The JPEG as a data URL, or an empty string when the engine couldn't draw it.
 */
function drawJpeg(image: HTMLImageElement, maxEdge: number, quality: number): string {
    const canvas: HTMLCanvasElement = document.createElement("canvas");
    let url: string = "";
    try {
        const scale: number = Math.min(1, maxEdge / Math.max(image.naturalWidth, image.naturalHeight));
        canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
        canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
        const context: CanvasRenderingContext2D | null = canvas.getContext("2d");
        if (context) {
            // JPEG has no transparency, so a transparent PNG would otherwise turn black.
            context.fillStyle = "#ffffff";
            context.fillRect(0, 0, canvas.width, canvas.height);
            context.imageSmoothingEnabled = true;
            context.imageSmoothingQuality = "high";
            context.drawImage(image, 0, 0, canvas.width, canvas.height);
            url = canvas.toDataURL("image/jpeg", quality);
        }
    } catch {
        // An engine throws when it can't draw or encode the photo, for example when the canvas would be too large.
        url = "";
    } finally {
        // Released straight away: mobile engines limit how much canvas memory a page can hold.
        canvas.width = 0;
        canvas.height = 0;
    }

    return typeof url === "string" && url.indexOf("data:image/jpeg") === 0 ? url : "";
}
