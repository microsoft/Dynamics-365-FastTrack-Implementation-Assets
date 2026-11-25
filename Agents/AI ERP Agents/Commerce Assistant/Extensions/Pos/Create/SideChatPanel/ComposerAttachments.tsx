/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Attachments for the side chat's message box. The associate adds photos or PDFs with the paperclip,
 * by pasting them, or by dropping them on the panel. Each shows as a chip above the box, where it can
 * be removed, and goes with the next message, which can also be files alone.
 *
 * Photos are prepared on the device before they are sent. Each is redrawn as a JPEG on a white
 * background, at most 1600 pixels on its longest side and about 400 KB. That keeps uploads quick on
 * a POS device, and leaves the photo's metadata, such as where it was taken, behind. A PDF is sent
 * as it is, so it has to be small.
 *
 * Files are read into data URLs rather than object URLs, because Cloud POS's content security policy
 * allows data: images but not blob: ones.
 */

import * as React from "react";
import { Button, Spinner, makeStyles, mergeClasses, shorthands, tokens } from "@fluentui/react-components";
import { AddRegular, AttachRegular, DismissRegular, DocumentPdfRegular, ErrorCircleRegular } from "@fluentui/react-icons";
import { ISideChatAttachment, ISideChatAttachmentPreview } from "./sideChatClient";

/** The most files one message can carry. */
export const MAX_ATTACHMENTS: number = 3;

const KB: number = 1024;
const MB: number = 1024 * KB;

/** The largest photo the panel opens. A bigger one takes too long to shrink on a POS device. */
const MAX_PHOTO_INPUT_BYTES: number = 20 * MB;

/** A PDF is sent as it is, so it has to be small. */
const MAX_PDF_BYTES: number = MB;

/** What a photo is shrunk to, at most, when it can be. */
const MAX_PHOTO_BYTES: number = 400 * KB;

/** Everything one message uploads, kept conservative for POS device memory and network use. */
const MAX_TOTAL_BYTES: number = 1.25 * MB;

/** Sizes and qualities to try, largest first, until a photo is small enough. */
const PHOTO_ATTEMPTS: ReadonlyArray<{ edge: number; quality: number }> = [
    { edge: 1600, quality: 0.85 },
    { edge: 1600, quality: 0.72 },
    { edge: 1280, quality: 0.72 },
    { edge: 1024, quality: 0.7 },
    { edge: 800, quality: 0.65 }
];

/** The longest side of the small copy shown in the chips and the conversation, in pixels. */
const THUMBNAIL_EDGE_PX: number = 160;

/** How long a file's name can be, in characters. */
const MAX_NAME_LENGTH: number = 80;

/** The media types a photo can arrive as. Every one is sent as JPEG. */
const PHOTO_TYPES: ReadonlyArray<string> = ["image/png", "image/jpeg", "image/jpg", "image/pjpeg", "image/webp", "image/gif"];

/** The extensions of those types, for devices that don't report a file's type. */
const PHOTO_EXTENSIONS: ReadonlyArray<string> = ["png", "jpg", "jpeg", "webp", "gif"];

/** What the file picker offers. */
const PICKER_ACCEPT: string =
    "image/png,image/jpeg,image/webp,image/gif,application/pdf,.png,.jpg,.jpeg,.webp,.gif,.pdf";

const SUPPORTED_FILES_HINT: string = "Attach a photo (PNG, JPEG, WebP or GIF) or a PDF.";
const FULL_MESSAGE: string = `A message can carry up to ${MAX_ATTACHMENTS} files. Send these first, or remove one.`;

type AttachmentKind = "photo" | "pdf";

/** One file in the message box. */
export interface IComposerAttachment {
    id: string;
    name: string;
    kind: AttachmentKind;
    /** The file as it will be sent. Absent while it is being prepared. */
    prepared?: ISideChatAttachment;
    /** A small copy of a photo, as a data URL. */
    thumbnailUrl?: string;
}

/** The files taken from the message box for sending. */
export interface ITakenAttachments {
    attachments: ISideChatAttachment[];
    /** What the conversation shows of each, in the same order. */
    previews: ISideChatAttachmentPreview[];
}

/** The message box's files and what can be done with them. */
export interface IComposerAttachments {
    items: ReadonlyArray<IComposerAttachment>;
    /** Why the last file couldn't be attached, or an empty string. */
    error: string;
    /** What just changed, for screen readers. It isn't shown. */
    notice: string;
    /** True when the message can't take another file. */
    isFull: boolean;
    /** True while any file is still being prepared. */
    isPreparing: boolean;
    /** Checks the files and prepares the ones that can be sent. */
    add: (files: ReadonlyArray<File>) => void;
    remove: (id: string) => void;
    /** Says the message can't take more files, as when the paperclip is tapped with the box full. */
    reportFull: () => void;
    /** Reads, without waiting for a render, how many files there are and whether any isn't ready. */
    peek: () => { count: number; isPreparing: boolean };
    /** Hands over the files for sending and empties the box. */
    take: () => ITakenAttachments;
}

/** A file that can't be attached, with the reason to show the associate. */
class AttachmentError extends Error { }

/** A file ready to send, and its small copy. */
interface IPreparedFile {
    attachment: ISideChatAttachment;
    thumbnailUrl?: string;
}

/**
 * Works out whether a file is a photo, a PDF or neither.
 * @param file The file.
 * @returns Its kind, or undefined when it can't be sent.
 */
function getKind(file: File): AttachmentKind | undefined {
    const type: string = (file.type || "").toLowerCase();
    if (type === "application/pdf") {
        return "pdf";
    }

    if (PHOTO_TYPES.indexOf(type) >= 0) {
        return "photo";
    }

    if (type.length > 0 && type !== "application/octet-stream") {
        return undefined;
    }

    const match: RegExpExecArray | null = /\.([a-z0-9]+)$/i.exec(file.name || "");
    const extension: string = match ? match[1].toLowerCase() : "";
    if (extension === "pdf") {
        return "pdf";
    }

    return PHOTO_EXTENSIONS.indexOf(extension) >= 0 ? "photo" : undefined;
}

/**
 * Tidies a file's name for the chip and the agent, keeping its extension when it is shortened.
 * @param name The name the device gave the file.
 * @param kind What the file is, for a name to use when it has none, as a pasted picture may not.
 * @returns The name.
 */
function cleanName(name: string, kind: AttachmentKind | undefined): string {
    const cleaned: string = (name || "").replace(/[\u0000-\u001f\u007f]+/g, "").replace(/\s+/g, " ").trim();
    const value: string = cleaned.length > 0 ? cleaned : kind === "pdf" ? "Document.pdf" : "Pasted image";
    if (value.length <= MAX_NAME_LENGTH) {
        return value;
    }

    const dot: number = value.lastIndexOf(".");
    const extension: string = dot > 0 && value.length - dot <= 6 ? value.slice(dot) : "";
    return `${value.slice(0, MAX_NAME_LENGTH - extension.length - 1)}\u2026${extension}`;
}

/**
 * Formats a size the way file pickers do.
 * @param bytes The size in bytes.
 * @returns For example "240 KB" or "1.2 MB".
 */
export function formatFileSize(bytes: number): string {
    if (bytes < KB) {
        return `${bytes} B`;
    }

    return bytes < MB ? `${Math.max(1, Math.round(bytes / KB))} KB` : `${(bytes / MB).toFixed(1)} MB`;
}

/**
 * Reads a file into a data URL.
 * @param file The file.
 * @returns The data URL.
 */
function readAsDataUrl(file: Blob): Promise<string> {
    return new Promise<string>((resolve, reject) => {
        const reader: FileReader = new FileReader();
        reader.onload = () => resolve(typeof reader.result === "string" ? reader.result : "");
        reader.onerror = () => reject(reader.error || new Error("The file couldn't be read."));
        reader.readAsDataURL(file);
    });
}

/**
 * Takes the base64 content out of a data URL.
 * @param dataUrl The data URL.
 * @returns The content, or an empty string when there is none.
 */
function base64Of(dataUrl: string): string {
    const comma: number = dataUrl.indexOf(",");
    return comma >= 0 && /;base64,/.test(dataUrl.slice(0, comma + 1)) ? dataUrl.slice(comma + 1) : "";
}

/**
 * Works out how many bytes base64 content holds.
 * @param base64 The content.
 * @returns Its size before encoding.
 */
function decodedSize(base64: string): number {
    const padding: number = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
    return Math.floor(base64.length * 3 / 4) - padding;
}

/**
 * Checks for the "%PDF-" header, which a PDF has within its first kilobyte.
 * @param base64 The file's content.
 * @returns True when the file looks like a PDF.
 */
function looksLikePdf(base64: string): boolean {
    try {
        // 1,368 characters are 1,026 bytes, and a whole number of base64 groups.
        return atob(base64.slice(0, 1368)).indexOf("%PDF-") >= 0;
    } catch {
        return false;
    }
}

/**
 * Opens a photo.
 * @param source The photo, as a data URL.
 * @returns The photo, once the engine has decoded it.
 */
function loadImage(source: string): Promise<HTMLImageElement> {
    return new Promise<HTMLImageElement>((resolve, reject) => {
        const image: HTMLImageElement = new Image();
        image.onload = () => {
            if (image.naturalWidth > 0 && image.naturalHeight > 0) {
                resolve(image);
            } else {
                reject(new Error("The photo has no size."));
            }
        };
        image.onerror = () => reject(new Error("The photo couldn't be decoded."));
        image.src = source;
    });
}

/**
 * Redraws a photo as a JPEG no larger than the given size. Engines turn a photo upright from its
 * metadata as they draw it, and the metadata is not copied.
 * @param image The photo.
 * @param maxEdge The longest side, in pixels. A smaller photo is not enlarged.
 * @param quality The JPEG quality, from 0 to 1.
 * @returns The JPEG as a data URL, or an empty string when the engine couldn't draw it.
 */
function drawJpeg(image: HTMLImageElement, maxEdge: number, quality: number): string {
    const scale: number = Math.min(1, maxEdge / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas: HTMLCanvasElement = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context: CanvasRenderingContext2D | null = canvas.getContext("2d");
    if (!context) {
        return "";
    }

    // JPEG has no transparency, so a transparent PNG would otherwise turn black.
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.drawImage(image, 0, 0, canvas.width, canvas.height);

    let url: string = "";
    try {
        url = canvas.toDataURL("image/jpeg", quality);
    } catch {
        url = "";
    }

    // Released straight away: mobile engines limit how much canvas memory a page can hold.
    canvas.width = 0;
    canvas.height = 0;
    return url.indexOf("data:image/jpeg") === 0 ? url : "";
}

/**
 * Gets a file ready to send.
 * @param file The file.
 * @param kind What it is.
 * @param name Its tidied name.
 * @returns The file as it will be sent, and a small copy of a photo.
 */
async function prepareAsync(file: File, kind: AttachmentKind, name: string): Promise<IPreparedFile> {
    let dataUrl: string;
    try {
        dataUrl = await readAsDataUrl(file);
    } catch {
        throw new AttachmentError(`"${name}" couldn't be read. Try attaching it again.`);
    }

    if (kind === "pdf") {
        const pdf: string = base64Of(dataUrl);
        if (!looksLikePdf(pdf)) {
            throw new AttachmentError(`"${name}" couldn't be opened as a PDF. ${SUPPORTED_FILES_HINT}`);
        }

        return { attachment: { name, type: "application/pdf", data: pdf, size: decodedSize(pdf) } };
    }

    let image: HTMLImageElement;
    try {
        image = await loadImage(dataUrl);
    } catch {
        throw new AttachmentError(`"${name}" couldn't be opened as a photo. ${SUPPORTED_FILES_HINT}`);
    }

    let data: string = "";
    for (const attempt of PHOTO_ATTEMPTS) {
        data = base64Of(drawJpeg(image, attempt.edge, attempt.quality));
        if (data.length > 0 && decodedSize(data) <= MAX_PHOTO_BYTES) {
            break;
        }
    }

    if (data.length === 0) {
        throw new AttachmentError(`"${name}" couldn't be prepared. Try another photo.`);
    }

    const thumbnailUrl: string = drawJpeg(image, THUMBNAIL_EDGE_PX, 0.8);
    return {
        attachment: { name, type: "image/jpeg", data, size: decodedSize(data) },
        thumbnailUrl: thumbnailUrl.length > 0 ? thumbnailUrl : undefined
    };
}

/**
 * The files in a paste, unless it also holds text. Copying from a document can put a picture of the
 * selection on the clipboard beside the text, and the associate meant the text.
 * @param data The paste's clipboard data.
 * @returns The files to attach; empty when the paste is text.
 */
export function readPastedFiles(data: DataTransfer | null): File[] {
    if (!data || !data.files || data.files.length === 0) {
        return [];
    }

    return Array.from(data.types || []).indexOf("text/plain") >= 0 ? [] : Array.from(data.files);
}

/**
 * Tells whether a drag carries files, as opposed to text or a link.
 * @param data The drag's data.
 * @returns True when files are being dragged.
 */
export function isDraggingFiles(data: DataTransfer | null): boolean {
    return !!data && Array.from(data.types || []).indexOf("Files") >= 0;
}

/**
 * The files in a drop.
 * @param data The drop's data.
 * @returns The files.
 */
export function readDroppedFiles(data: DataTransfer | null): File[] {
    return data && data.files ? Array.from(data.files) : [];
}

let attachmentSequence: number = 0;

/**
 * Holds the files attached to the next message, and prepares each for sending as it is added.
 * @returns The files and what can be done with them.
 */
export function useComposerAttachments(): IComposerAttachments {
    const [items, setItems] = React.useState<ReadonlyArray<IComposerAttachment>>([]);
    const [error, setError] = React.useState<string>("");
    const [notice, setNotice] = React.useState<string>("");

    // Up to date as soon as it changes, for preparations finishing and for send, which runs before
    // the next render.
    const itemsRef = React.useRef<ReadonlyArray<IComposerAttachment>>([]);
    // Photos are prepared one at a time: decoding several large ones at once can run a POS device out
    // of memory.
    const queueRef = React.useRef<Promise<void>>(Promise.resolve());
    const isMountedRef = React.useRef<boolean>(true);

    React.useEffect(() => {
        isMountedRef.current = true;
        return () => {
            isMountedRef.current = false;
        };
    }, []);

    const commit = React.useCallback((next: ReadonlyArray<IComposerAttachment>): void => {
        itemsRef.current = next;
        setItems(next);
    }, []);

    const prepareInTurn = React.useCallback((file: File, item: IComposerAttachment): void => {
        const isStillAttached = (): boolean =>
            isMountedRef.current && itemsRef.current.some((current: IComposerAttachment) => current.id === item.id);
        const drop = (message: string): void => {
            commit(itemsRef.current.filter((current: IComposerAttachment) => current.id !== item.id));
            setError(message);
            setNotice("");
        };

        queueRef.current = queueRef.current
            .then(async (): Promise<void> => {
                // Removed while it waited.
                if (!isStillAttached()) {
                    return;
                }

                let prepared: IPreparedFile;
                try {
                    prepared = await prepareAsync(file, item.kind, item.name);
                } catch (reason) {
                    if (isStillAttached()) {
                        drop(reason instanceof AttachmentError
                            ? reason.message
                            : `"${item.name}" couldn't be attached. Try again.`);
                    }

                    return;
                }

                if (!isStillAttached()) {
                    return;
                }

                const readyBytes: number = itemsRef.current.reduce(
                    (total: number, current: IComposerAttachment) => total + (current.prepared ? current.prepared.size : 0), 0);
                if (readyBytes + prepared.attachment.size > MAX_TOTAL_BYTES) {
                    drop(`"${item.name}" wasn't attached: with the other files, it's more than one message can `
                        + "send. Send it in a message of its own.");
                    return;
                }

                commit(itemsRef.current.map((current: IComposerAttachment) => current.id === item.id
                    ? { ...current, prepared: prepared.attachment, thumbnailUrl: prepared.thumbnailUrl }
                    : current));
                setNotice(`Attached ${item.name}.`);
            })
            .catch(() => undefined);
    }, [commit]);

    const add = React.useCallback((files: ReadonlyArray<File>): void => {
        if (files.length === 0) {
            return;
        }

        let message: string = "";
        const accepted: Array<{ file: File; item: IComposerAttachment }> = [];
        for (const file of files) {
            const kind: AttachmentKind | undefined = getKind(file);
            const name: string = cleanName(file.name, kind);
            if (!kind) {
                message = `"${name}" can't be attached. ${SUPPORTED_FILES_HINT}`;
                continue;
            }

            if (itemsRef.current.length + accepted.length >= MAX_ATTACHMENTS) {
                message = FULL_MESSAGE;
                break;
            }

            if (file.size === 0) {
                message = `"${name}" is empty.`;
                continue;
            }

            if (kind === "pdf" && file.size > MAX_PDF_BYTES) {
                message = `"${name}" is too large to send. Attach a PDF under 1 MB, or a photo of the page.`;
                continue;
            }

            if (kind === "photo" && file.size > MAX_PHOTO_INPUT_BYTES) {
                message = `"${name}" is too large to open. Attach a photo under 20 MB.`;
                continue;
            }

            attachmentSequence += 1;
            accepted.push({ file, item: { id: `side-attachment-${attachmentSequence}`, name, kind } });
        }

        setError(message);
        setNotice("");
        if (accepted.length === 0) {
            return;
        }

        commit([...itemsRef.current, ...accepted.map((entry) => entry.item)]);
        accepted.forEach((entry) => prepareInTurn(entry.file, entry.item));
    }, [commit, prepareInTurn]);

    const remove = React.useCallback((id: string): void => {
        const removed: IComposerAttachment | undefined =
            itemsRef.current.find((current: IComposerAttachment) => current.id === id);
        if (!removed) {
            return;
        }

        commit(itemsRef.current.filter((current: IComposerAttachment) => current.id !== id));
        setError("");
        setNotice(`Removed ${removed.name}.`);
    }, [commit]);

    const reportFull = React.useCallback((): void => {
        setError(FULL_MESSAGE);
        setNotice("");
    }, []);

    const peek = React.useCallback((): { count: number; isPreparing: boolean } => ({
        count: itemsRef.current.length,
        isPreparing: itemsRef.current.some((current: IComposerAttachment) => !current.prepared)
    }), []);

    const take = React.useCallback((): ITakenAttachments => {
        const taken: ITakenAttachments = { attachments: [], previews: [] };
        itemsRef.current.forEach((current: IComposerAttachment) => {
            if (!current.prepared) {
                return;
            }

            taken.attachments.push(current.prepared);
            taken.previews.push(current.thumbnailUrl
                ? { name: current.name, type: current.prepared.type, thumbnailUrl: current.thumbnailUrl }
                : { name: current.name, type: current.prepared.type });
        });

        commit([]);
        setError("");
        setNotice("");
        return taken;
    }, [commit]);

    return React.useMemo((): IComposerAttachments => ({
        items,
        error,
        notice,
        isFull: items.length >= MAX_ATTACHMENTS,
        isPreparing: items.some((current: IComposerAttachment) => !current.prepared),
        add,
        remove,
        reportFull,
        peek,
        take
    }), [items, error, notice, add, remove, reportFull, peek, take]);
}

const useStyles = makeStyles({
    chips: {
        display: "flex",
        flexWrap: "wrap",
        columnGap: "8px",
        rowGap: "8px",
        ...shorthands.padding("10px", "10px", "0")
    },

    /* Two to a row, so a long name still has room. */
    chip: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px",
        flexGrow: 0,
        flexShrink: 1,
        flexBasis: "calc(50% - 4px)",
        minWidth: 0,
        boxSizing: "border-box",
        ...shorthands.padding("4px", "2px", "4px", "4px"),
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderRadius("10px"),
        backgroundColor: tokens.colorNeutralBackground2
    },

    chipTile: {
        flexShrink: 0,
        width: "36px",
        height: "36px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        ...shorthands.overflow("hidden"),
        ...shorthands.borderRadius("6px"),
        backgroundColor: tokens.colorNeutralBackground4,
        color: tokens.colorNeutralForeground3
    },

    pdfTile: {
        backgroundColor: tokens.colorPaletteRedBackground1,
        color: tokens.colorPaletteRedForeground1
    },

    chipImage: {
        display: "block",
        width: "100%",
        height: "100%",
        objectFit: "cover"
    },

    chipText: {
        flexGrow: 1,
        minWidth: 0,
        display: "flex",
        flexDirection: "column"
    },

    chipName: {
        ...shorthands.overflow("hidden"),
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase200,
        fontWeight: tokens.fontWeightSemibold,
        lineHeight: tokens.lineHeightBase200
    },

    chipMeta: {
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase100,
        lineHeight: tokens.lineHeightBase100
    },

    chipRemove: {
        flexShrink: 0,
        minWidth: "24px"
    },

    error: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "6px",
        ...shorthands.padding("8px", "14px", "0"),
        color: tokens.colorPaletteRedForeground1,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    errorIcon: {
        flexShrink: 0,
        fontSize: "16px"
    },

    visuallyHidden: {
        position: "absolute",
        width: "1px",
        height: "1px",
        ...shorthands.margin("-1px"),
        ...shorthands.padding("0"),
        ...shorthands.overflow("hidden"),
        ...shorthands.borderStyle("none"),
        clipPath: "inset(50%)",
        whiteSpace: "nowrap"
    },

    /* Covers the panel while files are dragged over it. Events pass through to the panel. */
    dropOverlay: {
        position: "absolute",
        top: "8px",
        right: "8px",
        bottom: "8px",
        left: "8px",
        zIndex: 1,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        rowGap: "10px",
        pointerEvents: "none",
        ...shorthands.border("2px", "dashed", tokens.colorBrandStroke1),
        ...shorthands.borderRadius("12px"),
        backgroundColor: `color-mix(in srgb, ${tokens.colorBrandBackground2} 92%, transparent)`,
        color: tokens.colorBrandForeground1,
        fontSize: tokens.fontSizeBase400,
        fontWeight: tokens.fontWeightSemibold
    },

    messageAttachments: {
        display: "flex",
        flexWrap: "wrap",
        justifyContent: "flex-end",
        columnGap: "6px",
        rowGap: "6px"
    },

    messageAttachmentsWithText: {
        marginBottom: "8px"
    },

    messagePhoto: {
        display: "block",
        width: "76px",
        height: "76px",
        objectFit: "cover",
        boxSizing: "border-box",
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderRadius("8px"),
        backgroundColor: tokens.colorNeutralBackground1
    },

    messageFile: {
        display: "flex",
        alignItems: "center",
        columnGap: "6px",
        minWidth: 0,
        maxWidth: "100%",
        boxSizing: "border-box",
        ...shorthands.padding("6px", "10px"),
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderRadius("8px"),
        backgroundColor: tokens.colorNeutralBackground1,
        fontSize: tokens.fontSizeBase200,
        whiteSpace: "nowrap"
    },

    messageFileIcon: {
        flexShrink: 0,
        fontSize: "20px",
        color: tokens.colorPaletteRedForeground1
    },

    messageFileName: {
        minWidth: 0,
        ...shorthands.overflow("hidden"),
        textOverflow: "ellipsis"
    }
});

/** What the attach button needs. */
export interface IAttachButtonProps {
    /** True when the message can't take another file. */
    isFull: boolean;
    /** Receives the files the associate picked. */
    onFiles: (files: File[]) => void;
    /** Called instead of opening the picker when the message is full. */
    onFull: () => void;
}

/** What the panel can ask of the attach button. */
export interface IAttachButtonHandle {
    /** Opens the file picker, as a press of the button does. */
    openPicker: () => void;
}

/**
 * The round plus under the message box, which opens the device's file picker. On phones and tablets
 * the picker also offers the camera.
 * @param props What happens with the files picked.
 * @returns The rendered button and its hidden file input.
 */
export const AttachButton = React.forwardRef<IAttachButtonHandle, IAttachButtonProps>((props, ref) => {
    const inputRef = React.useRef<HTMLInputElement>(null);

    const openPicker = (): void => {
        if (props.isFull) {
            props.onFull();
        } else if (inputRef.current) {
            inputRef.current.click();
        }
    };

    React.useImperativeHandle(ref, () => ({ openPicker }));

    return (
        <>
            <Button
                appearance="subtle"
                shape="circular"
                icon={<AddRegular />}
                aria-label="Attach files"
                title={props.isFull ? `A message can carry up to ${MAX_ATTACHMENTS} files` : "Attach a photo or PDF"}
                onClick={openPicker}
            />
            <input
                ref={inputRef}
                type="file"
                accept={PICKER_ACCEPT}
                multiple
                hidden
                // POS styles can override the hidden attribute and show the browser's own file button.
                style={{ display: "none" }}
                tabIndex={-1}
                aria-hidden="true"
                onChange={(event: React.ChangeEvent<HTMLInputElement>) => {
                    const files: File[] = event.target.files ? Array.from(event.target.files) : [];
                    // Cleared, so choosing the same file again still counts as a change.
                    event.target.value = "";
                    props.onFiles(files);
                }}
            />
        </>
    );
});

AttachButton.displayName = "AttachButton";

/** What the chips above the message box need. */
export interface IAttachmentChipsProps {
    items: ReadonlyArray<IComposerAttachment>;
    onRemove: (id: string) => void;
}

/**
 * The files attached to the next message, each with a small copy or a PDF icon, its name and size,
 * and a button to remove it. Renders nothing when there are none.
 * @param props The files and what removing one does.
 * @returns The rendered chips.
 */
export const AttachmentChips: React.FC<IAttachmentChipsProps> = (props) => {
    const styles = useStyles();
    if (props.items.length === 0) {
        return null;
    }

    return (
        <div className={styles.chips} role="list" aria-label="Attached files">
            {props.items.map((item: IComposerAttachment) => {
                const detail: string = item.prepared
                    ? `${item.kind === "pdf" ? "PDF" : "Photo"} \u00b7 ${formatFileSize(item.prepared.size)}`
                    : "Preparing\u2026";

                return (
                    <div key={item.id} className={styles.chip} role="listitem">
                        <div className={mergeClasses(styles.chipTile, item.kind === "pdf" && styles.pdfTile)} aria-hidden="true">
                            {!item.prepared ? (
                                <Spinner size="extra-tiny" />
                            ) : item.thumbnailUrl ? (
                                <img className={styles.chipImage} src={item.thumbnailUrl} alt="" />
                            ) : (
                                <DocumentPdfRegular fontSize={20} />
                            )}
                        </div>
                        <div className={styles.chipText}>
                            <span className={styles.chipName} title={item.name}>{item.name}</span>
                            <span className={styles.chipMeta}>{detail}</span>
                        </div>
                        <Button
                            className={styles.chipRemove}
                            appearance="subtle"
                            shape="circular"
                            size="small"
                            icon={<DismissRegular />}
                            aria-label={`Remove ${item.name}`}
                            title="Remove"
                            onClick={() => props.onRemove(item.id)}
                        />
                    </div>
                );
            })}
        </div>
    );
};

/** What the attachment status line needs. */
export interface IAttachmentStatusProps {
    error: string;
    notice: string;
}

/**
 * Says why a file couldn't be attached, and tells screen readers when one is attached or removed. The
 * live region is always rendered, so each change to it is announced. Empty, it takes no space.
 * @param props The last error and notice.
 * @returns The rendered status line.
 */
export const AttachmentStatus: React.FC<IAttachmentStatusProps> = (props) => {
    const styles = useStyles();

    return (
        <div role="status">
            {props.error.length > 0 ? (
                <div className={styles.error}>
                    <ErrorCircleRegular className={styles.errorIcon} aria-hidden="true" />
                    <span>{props.error}</span>
                </div>
            ) : props.notice.length > 0 ? (
                <span className={styles.visuallyHidden}>{props.notice}</span>
            ) : null}
        </div>
    );
};

/**
 * Shown over the panel while files are dragged over it.
 * @returns The rendered overlay.
 */
export const AttachmentDropOverlay: React.FC = () => {
    const styles = useStyles();

    return (
        <div className={styles.dropOverlay} aria-hidden="true">
            <AttachRegular fontSize={32} />
            <span>Drop photos or PDFs to attach</span>
        </div>
    );
};

/** What a message's files need. */
export interface IMessageAttachmentsProps {
    attachments: ReadonlyArray<ISideChatAttachmentPreview>;
    /** True when text follows the files in the message. */
    hasText: boolean;
}

/**
 * The files an associate sent, at the top of their message: photos as small squares, PDFs by name.
 * @param props The files.
 * @returns The rendered files.
 */
export const MessageAttachments: React.FC<IMessageAttachmentsProps> = (props) => {
    const styles = useStyles();

    return (
        <div
            className={mergeClasses(styles.messageAttachments, props.hasText && styles.messageAttachmentsWithText)}
            role="list"
            aria-label="Attached files">
            {props.attachments.map((attachment: ISideChatAttachmentPreview, index: number) => (
                <div
                    key={`${index}-${attachment.name}`}
                    className={attachment.thumbnailUrl ? undefined : styles.messageFile}
                    role="listitem"
                    title={attachment.name}>
                    {attachment.thumbnailUrl ? (
                        <img className={styles.messagePhoto} src={attachment.thumbnailUrl} alt={attachment.name} />
                    ) : (
                        <>
                            <DocumentPdfRegular className={styles.messageFileIcon} aria-hidden="true" />
                            <span className={styles.messageFileName}>{attachment.name}</span>
                        </>
                    )}
                </div>
            ))}
        </div>
    );
};
