/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Replies grounded in the knowledge base. The knowledge base's search tool tells the agent to cite each
 * passage it used as `【message_idx:search_idx†source_name】`, and the agent writes those markers into its
 * reply. Shown as they are, they are long and break the reply up, so each one becomes a small numbered
 * marker, numbered by document, and the documents are listed under the reply.
 *
 * A reply grounded in the knowledge base, because it cites a document or because the agent searched the
 * knowledge base for it, also gets a Copy button, which copies the reply without its markers, such as to
 * paste a policy into a note for the customer.
 */

import * as React from "react";
import { Button, makeStyles, shorthands, tokens, useId } from "@fluentui/react-components";
import { CheckmarkRegular, CopyRegular, ErrorCircleRegular } from "@fluentui/react-icons";
import { IAgentToolActivity } from "./agentContracts";

/** A document the reply cites. */
export interface IKnowledgeSource {
    /** The document's number, in the order the reply first cites it, from 1. */
    readonly number: number;
    /** The document's name as the knowledge base gave it, such as "Returns_Policy.docx". */
    readonly fileName: string;
    /** The name to show, such as "Returns Policy". */
    readonly title: string;
}

/** A part of a reply: its own words, or a citation. */
export type KnowledgeReplySegment = string | IKnowledgeSource;

/** A reply read for its citations. */
export interface IKnowledgeReply {
    /** The reply's words and citations, in order. */
    readonly segments: ReadonlyArray<KnowledgeReplySegment>;
    /** The documents the reply cites, by number. Empty when it cites none. */
    readonly sources: ReadonlyArray<IKnowledgeSource>;
    /** The reply without its citations, as it is copied. */
    readonly plainText: string;
}

/** What the footer under a reply needs. */
export interface IKnowledgeReplyFooterProps {
    /** The reply's text, with its citations. */
    text: string;
    /** The tools the agent used for the reply. */
    toolActivities?: ReadonlyArray<IAgentToolActivity>;
}

type CopyState = "idle" | "copied" | "failed";

/**
 * A citation: `【4:0†Returns_Policy.docx】`, as the knowledge base asks for, or with square brackets,
 * without the indexes, or with a further `†` part such as a line range. Group 1 is the document's name.
 */
const CITATION_PATTERN: RegExp = /[\u3010[](?:\d+(?::\d+)?)?\u2020([^\u3011\]\u2020]+)(?:\u2020[^\u3011\]]*)?[\u3011\]]/g;

/** Words that follow a citation without a space before them. */
const CLOSING_PUNCTUATION: RegExp = /^[.,;:!?)\]}\u2026'"\u2019\u201d]/;

/** File extensions left off a document's name. */
const DOCUMENT_EXTENSION: RegExp = /\.(docx?|pdf|txt|md|pptx?|xlsx?|html?|json|csv|rtf)$/i;

/** How long the Copy button says it copied, or could not. */
const COPY_FEEDBACK_MS: number = 2000;

const useStyles = makeStyles({
    /*
     * A citation in the reply: a small number in the brand's colours, raised like a footnote. It is moved
     * up rather than aligned up, so the lines it sits on keep the same height as the rest of the reply.
     */
    citation: {
        position: "relative",
        top: "-4px",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        minWidth: "16px",
        height: "16px",
        boxSizing: "border-box",
        ...shorthands.margin("0", "1px", "0", "2px"),
        ...shorthands.padding("0", "4px"),
        ...shorthands.borderRadius(tokens.borderRadiusCircular),
        backgroundColor: tokens.colorBrandBackground2,
        color: tokens.colorBrandForeground2,
        fontSize: "10px",
        lineHeight: "16px",
        fontWeight: tokens.fontWeightSemibold,
        verticalAlign: "baseline",
        whiteSpace: "nowrap",
        cursor: "default",
        // Copying the reply by selecting it leaves the numbers out.
        userSelect: "none",
        "@media (forced-colors: active)": {
            ...shorthands.border("1px", "solid", "CanvasText"),
            backgroundColor: "Canvas",
            color: "CanvasText"
        }
    },

    /* The sources, then Copy under them, both lined up with the reply's text. */
    footer: {
        alignSelf: "stretch",
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-start",
        rowGap: "4px",
        marginTop: "-4px",
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    sources: {
        display: "flex",
        flexWrap: "wrap",
        alignItems: "center",
        columnGap: "8px",
        rowGap: "6px",
        minWidth: 0,
        maxWidth: "100%"
    },

    sourcesLabel: {
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        fontWeight: tokens.fontWeightSemibold
    },

    sourceList: {
        display: "flex",
        flexWrap: "wrap",
        columnGap: "6px",
        rowGap: "6px",
        minWidth: 0,
        maxWidth: "100%",
        ...shorthands.margin("0"),
        ...shorthands.padding("0"),
        listStyleType: "none"
    },

    source: {
        display: "flex",
        alignItems: "center",
        columnGap: "6px",
        minWidth: 0,
        maxWidth: "100%",
        boxSizing: "border-box",
        ...shorthands.margin("0"),
        ...shorthands.padding("3px", "10px", "3px", "3px"),
        ...shorthands.borderRadius(tokens.borderRadiusCircular),
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        backgroundColor: tokens.colorNeutralBackground1,
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    sourceNumber: {
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
        minWidth: "16px",
        height: "16px",
        boxSizing: "border-box",
        ...shorthands.padding("0", "4px"),
        ...shorthands.borderRadius(tokens.borderRadiusCircular),
        backgroundColor: tokens.colorBrandBackground2,
        color: tokens.colorBrandForeground2,
        fontSize: "10px",
        lineHeight: "16px",
        fontWeight: tokens.fontWeightSemibold,
        "@media (forced-colors: active)": {
            ...shorthands.border("1px", "solid", "CanvasText"),
            backgroundColor: "Canvas",
            color: "CanvasText"
        }
    },

    sourceName: {
        minWidth: 0,
        ...shorthands.overflow("hidden"),
        textOverflow: "ellipsis",
        whiteSpace: "nowrap"
    },

    /* A subtle button's icon sits inside its padding; this lines the icon up with the reply's text. */
    copyButton: {
        marginLeft: "-8px"
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
    }
});

/**
 * Turns a document's name into one to show: no folder, no extension, and spaces for underscores.
 * @param fileName The name the knowledge base gave, such as "Adventure_Works_Returns_Policy.docx".
 * @returns The name to show, such as "Adventure Works Returns Policy".
 */
function toSourceTitle(fileName: string): string {
    const parts: string[] = fileName.split(/[\\/]/);
    const title: string = (parts[parts.length - 1] || fileName)
        .replace(DOCUMENT_EXTENSION, "")
        .replace(/_+/g, " ")
        .replace(/\s+/g, " ")
        .trim();

    return title.length > 0 ? title : fileName;
}

/**
 * Reads a reply for its citations. Each document gets a number the first time the reply cites it, and
 * a run of citations with only spaces between them shows each document once. The space before a
 * citation goes, so the marker sits against the words it supports, and comes back after it when more
 * words follow.
 * @param text The reply.
 * @returns The reply's words and citations, the documents it cites, and the reply without citations.
 */
export function parseKnowledgeReply(text: string): IKnowledgeReply {
    const segments: KnowledgeReplySegment[] = [];
    const sources: IKnowledgeSource[] = [];
    const sourcesByKey: Map<string, IKnowledgeSource> = new Map<string, IKnowledgeSource>();
    const pattern: RegExp = new RegExp(CITATION_PATTERN.source, "g");
    let plainText: string = "";
    let index: number = 0;
    // The documents in the current run of citations, and the space that came before the run.
    let runNumbers: number[] = [];
    let droppedSpace: string = "";

    const addWords = (words: string): void => {
        if (words.length === 0) {
            return;
        }

        const needsSpace: boolean = runNumbers.length > 0
            && droppedSpace.length > 0
            && !/^\s/.test(words)
            && !CLOSING_PUNCTUATION.test(words);
        const added: string = needsSpace ? `${droppedSpace}${words}` : words;
        segments.push(added);
        plainText += added;
        runNumbers = [];
        droppedSpace = "";
    };

    let match: RegExpExecArray | null = pattern.exec(text);
    while (match !== null) {
        const before: string = text.slice(index, match.index);
        const words: string = before.replace(/\s+$/, "");
        if (words.length > 0) {
            addWords(words);
            droppedSpace = before.slice(words.length);
        } else if (runNumbers.length === 0) {
            droppedSpace = before;
        }

        const fileName: string = match[1].trim();
        const key: string = fileName.toLowerCase();
        let source: IKnowledgeSource | undefined = sourcesByKey.get(key);
        if (!source) {
            source = { number: sources.length + 1, fileName, title: toSourceTitle(fileName) };
            sources.push(source);
            sourcesByKey.set(key, source);
        }

        if (runNumbers.indexOf(source.number) < 0) {
            segments.push(source);
            runNumbers.push(source.number);
        }

        index = pattern.lastIndex;
        match = pattern.exec(text);
    }

    addWords(text.slice(index));

    return { segments, sources, plainText: plainText.trim() };
}

/**
 * Whether the agent searched the knowledge base for a reply.
 * @param toolActivities The tools the agent used for the reply.
 * @returns True when a knowledge base search completed.
 */
export function usedKnowledgeBase(toolActivities: ReadonlyArray<IAgentToolActivity> | undefined): boolean {
    return !!toolActivities && toolActivities.some((activity: IAgentToolActivity): boolean =>
        activity.status === "completed" && /knowledge/i.test(activity.name));
}

/**
 * Copies text by selecting it in a hidden text box, for when the page may not use the clipboard API.
 * Focus goes back to where it was.
 * @param text The text.
 * @returns Whether the engine copied it.
 */
function copyWithSelection(text: string): boolean {
    const focused: Element | null = document.activeElement;
    const box: HTMLTextAreaElement = document.createElement("textarea");
    box.value = text;
    box.setAttribute("readonly", "");
    box.setAttribute("aria-hidden", "true");
    box.tabIndex = -1;
    box.style.position = "fixed";
    box.style.top = "0";
    box.style.left = "-10000px";
    box.style.opacity = "0";
    document.body.appendChild(box);

    let copied: boolean = false;
    try {
        box.select();
        copied = document.execCommand("copy");
    } catch {
        copied = false;
    } finally {
        box.remove();
        if (focused instanceof HTMLElement) {
            focused.focus();
        }
    }

    return copied;
}

/**
 * Copies text to the clipboard.
 * @param text The text.
 * @returns Whether it was copied.
 */
async function copyToClipboard(text: string): Promise<boolean> {
    try {
        if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
            await navigator.clipboard.writeText(text);
            return true;
        }
    } catch {
        // The page may not use the clipboard API, so the copy is made by selection instead.
    }

    return copyWithSelection(text);
}

/**
 * A citation in the reply. Screen readers hear "source 1" in place of the number.
 * @param props The document cited.
 * @returns The rendered marker.
 */
const CitationMarker: React.FC<{ source: IKnowledgeSource }> = (props) => {
    const styles = useStyles();

    return (
        <span className={styles.citation} title={`Source ${props.source.number}: ${props.source.title}`}>
            <span aria-hidden="true">{props.source.number}</span>
            <span className={styles.visuallyHidden}>{` (source ${props.source.number})`}</span>
        </span>
    );
};

/**
 * A reply's text, with each citation shown as a small numbered marker. A reply without citations is
 * its text, exactly as before.
 * @param props The reply's text.
 * @returns The rendered text.
 */
export const KnowledgeReplyText: React.FC<{ text: string }> = (props) => {
    const reply: IKnowledgeReply = React.useMemo(() => parseKnowledgeReply(props.text), [props.text]);
    if (reply.sources.length === 0) {
        return <>{props.text}</>;
    }

    return (
        <>
            {reply.segments.map((segment: KnowledgeReplySegment, index: number) => typeof segment === "string"
                ? <React.Fragment key={index}>{segment}</React.Fragment>
                : <CitationMarker key={index} source={segment} />)}
        </>
    );
};

/**
 * Under a reply grounded in the knowledge base: the documents it cites, numbered as in the reply, and a
 * Copy button. Other replies get nothing.
 * @param props The reply and the tools used for it.
 * @returns The rendered footer, or null.
 */
export const KnowledgeReplyFooter: React.FC<IKnowledgeReplyFooterProps> = (props) => {
    const styles = useStyles();
    const labelId: string = useId("knowledge-sources-");
    const reply: IKnowledgeReply = React.useMemo(() => parseKnowledgeReply(props.text), [props.text]);
    const [copyState, setCopyState] = React.useState<CopyState>("idle");

    React.useEffect(() => {
        if (copyState === "idle") {
            return undefined;
        }

        const timer: number = window.setTimeout(() => setCopyState("idle"), COPY_FEEDBACK_MS);
        return () => window.clearTimeout(timer);
    }, [copyState]);

    if (reply.plainText.length === 0 || (reply.sources.length === 0 && !usedKnowledgeBase(props.toolActivities))) {
        return null;
    }

    const copy = async (): Promise<void> => {
        setCopyState(await copyToClipboard(reply.plainText) ? "copied" : "failed");
    };

    let copyIcon: JSX.Element = <CopyRegular />;
    let copyLabel: string = "Copy";
    if (copyState === "copied") {
        copyIcon = <CheckmarkRegular />;
        copyLabel = "Copied";
    } else if (copyState === "failed") {
        copyIcon = <ErrorCircleRegular />;
        copyLabel = "Couldn't copy";
    }

    return (
        <div className={styles.footer}>
            {reply.sources.length > 0 && (
                <div className={styles.sources}>
                    <span className={styles.sourcesLabel} id={labelId}>Sources</span>
                    <ol className={styles.sourceList} aria-labelledby={labelId}>
                        {reply.sources.map((source: IKnowledgeSource) => (
                            <li key={source.number} className={styles.source}>
                                <span className={styles.sourceNumber} aria-hidden="true">{source.number}</span>
                                <span className={styles.visuallyHidden}>{`Source ${source.number}: `}</span>
                                <span className={styles.sourceName} title={source.fileName}>{source.title}</span>
                            </li>
                        ))}
                    </ol>
                </div>
            )}
            <Button
                className={styles.copyButton}
                appearance="subtle"
                size="small"
                icon={copyIcon}
                title="Copy this response"
                onClick={() => {
                    void copy();
                }}>
                {copyLabel}
            </Button>
        </div>
    );
};
