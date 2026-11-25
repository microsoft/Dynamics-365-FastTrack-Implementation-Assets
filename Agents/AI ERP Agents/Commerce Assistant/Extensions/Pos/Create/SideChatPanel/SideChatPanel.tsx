/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * SideChatPanel — a Copilot-style chat docked to the right edge of POS, under the POS header, that
 * stays put while the operator moves between views.
 *
 * It renders into a container appended to document.body by SideChatPanelTrigger, which is why it
 * survives view navigation: POS swaps the children of #contenthost, never the body.
 *
 * Opening and closing is driven from the POS header icon (a Knockout header packing item), which the
 * panel leaves in view, so the open state lives in panelState rather than in component state. The
 * panel's More options menu can close it too. While closed the panel renders nothing at all, so it
 * adds no tab stops and no screen reader output to the view behind it.
 */

import * as React from "react";
import {
    Button,
    Badge,
    Checkbox,
    FluentProvider,
    IdPrefixProvider,
    Menu,
    MenuItem,
    MenuList,
    MenuPopover,
    MenuTrigger,
    Spinner,
    ToggleButton,
    buttonClassNames,
    makeStyles,
    mergeClasses,
    shorthands,
    tokens,
    useId,
    webLightTheme
} from "@fluentui/react-components";
import {
    CartRegular,
    CheckmarkCircleFilled,
    CheckmarkCircleRegular,
    ChevronDownRegular,
    ChevronRightRegular,
    ChevronUpRegular,
    ComposeRegular,
    DismissRegular,
    ErrorCircleRegular,
    ImageOffRegular,
    InfoRegular,
    ItemCompareFilled,
    ItemCompareRegular,
    LightbulbRegular,
    MoreHorizontalRegular,
    SendFilled,
    ShieldTaskRegular,
    SparkleFilled,
    SparkleRegular,
    TextAlignLeftRegular,
    WarningRegular
} from "@fluentui/react-icons";
import {
    DEFAULT_SIDE_CHAT_SUGGESTIONS,
    ICartSuggestionReply,
    ICartSuggestionRequest,
    ISideChatAttachmentPreview,
    ISideChatClient,
    ISideChatReply,
    SideChatMessage,
    SideChatSuggestion
} from "./sideChatClient";
import {
    IActionReceipt,
    IAgentActionExecutionOptions,
    IAgentCartLine,
    IAgentCartPlanReceipt,
    IAgentCartPlanReceiptItem,
    IAgentCustomerOrderReceipt,
    IAgentPosAction,
    IAgentPosErrorContext,
    IAgentProductCard,
    IAgentProductFilterRequest,
    IAgentProductFilterSelection,
    IAgentProductInventory,
    IAgentProductPreview,
    IAgentProductReason,
    IAgentShippingReceipt,
    IAgentShippingReceiptLine,
    IAgentToolActivity
} from "./agentContracts";
import { PANEL_WIDTH, getIsOpen, setIsOpen, subscribe } from "./panelState";
import { CommerceLogo } from "./CommerceLogo";
import { ProductStock } from "./ProductStock";
import { IVoiceInput, VoiceInputButton, VoiceInputStatus, useVoiceInput } from "./VoiceInput";
import { KnowledgeReplyFooter, KnowledgeReplyText } from "./KnowledgeCitations";
import {
    AttachButton,
    AttachmentChips,
    AttachmentDropOverlay,
    AttachmentStatus,
    IAttachButtonHandle,
    IComposerAttachments,
    ITakenAttachments,
    MessageAttachments,
    isDraggingFiles,
    readDroppedFiles,
    readPastedFiles,
    useComposerAttachments
} from "./ComposerAttachments";
import {
    IVersionedCartSuggestionRequest,
    getLatestCartSuggestionVersion,
    subscribeToCartSuggestionRequests,
    takeCartSuggestionRequest
} from "./cartSuggestionState";
import {
    IVersionedPosError,
    POS_ERROR_LIFETIME_MS,
    getPosError,
    subscribeToPosError,
    takePosErrorHelpRequest
} from "./posErrorState";
import { IProductFilters, useProductFilters } from "./productFilters/useProductFilters";
import { ProductFacetFilters, focusFirstTag } from "./productFilters/ProductFacetFilters";
import { hasRecommendationCards } from "./productResults/recommendationMessage";

/**
 * Sits above ordinary view content but below the POS app bar (1008), the page loader and dialogs
 * (1020/1022) and the header search overlays (1040/1050), so the panel can never cover a modal or
 * the command bar. Values come from src/pos/app/common/Stylesheets/Common/_Constants.scss.
 */
const PANEL_Z_INDEX: number = 1007;

/**
 * POS sets `body { font-size: 4px }` (Stylesheets/Parts/_Pos.scss), which every descendant inherits.
 * Fluent sizes a lot of things in em, so the panel restores a sane base before rendering anything.
 */
const BASE_FONT_SIZE: string = "14px";

/**
 * Prefix applied to every id Fluent UI generates for this bundle, including the id of the `<style>`
 * element FluentProvider uses to publish its theme as CSS custom properties.
 *
 * POS hosts its own React + Fluent UI v9 copy and the full-page chat sample bundles another, and
 * React's `useId()` counter is per React instance. Without a distinct prefix all three generate the
 * same `fui-FluentProviderr0` id; Fluent then adopts the element it finds instead of writing its own
 * theme rule, every `var(--...)` becomes invalid, and the panel loses all of its design tokens.
 * @see https://aka.ms/fluentui-conflicting-ids
 */
const FLUENT_ID_PREFIX: string = "contoso-side-chat-";

/** Padding around the conversation, also kept between its edge and anything scrolled into view. */
const CONVERSATION_PADDING_PX: number = 16;

/** Most products the chat card shows before View all, as in the design. */
const MAX_PREVIEW_PRODUCTS: number = 3;

/** How many starter prompts show before See more. */
const SUGGESTIONS_SHOWN: number = 3;

/** The name shown over an empty conversation, next to the Commerce icon. */
const BRAND_NAME: string = "Commerce";

/** What the message box says before the first message. */
const EMPTY_PLACEHOLDER: string = "Message Store commerce assistant";

/** Shown under the message box once a conversation has started. */
const AI_DISCLAIMER: string = "AI-generated content may be incorrect";

/** What the shield in the toolbar stands for. */
const SIGN_IN_NOTE: string = "Requests run under your POS sign-in";

/**
 * The POS header bar. POS renders one for the whole app and gives it this class only while the open
 * view shows a title and search, so a view without a header has no match.
 */
const POS_HEADER_SELECTOR: string = ".headerSplitViewHeader";

/** One cell of the progress glyph. */
interface IProgressCell {
    /** Its opacity when motion is reduced, so the still glyph keeps a shape. */
    opacity: number;
    /** Where in the pulse it starts, so the cells don't fade in step. */
    delay: string;
}

/** The progress glyph's three by three grid, read row by row. */
const PROGRESS_CELLS: ReadonlyArray<IProgressCell> = [
    { opacity: 1, delay: "0s" },
    { opacity: 1, delay: "-0.9s" },
    { opacity: 0.25, delay: "-0.3s" },
    { opacity: 0.25, delay: "-1.2s" },
    { opacity: 1, delay: "-0.6s" },
    { opacity: 1, delay: "-0.15s" },
    { opacity: 1, delay: "-1.05s" },
    { opacity: 0.25, delay: "-0.45s" },
    { opacity: 1, delay: "-0.75s" }
];

const useStyles = makeStyles({
    /* Anchored to the right edge, from under the POS header to the bottom, but only as wide as its
       content so the rest of the screen keeps receiving pointer events. The top follows the header,
       which is measured while the panel is open. */
    root: {
        position: "fixed",
        top: 0,
        right: 0,
        bottom: 0,
        zIndex: PANEL_Z_INDEX,
        display: "flex",
        alignItems: "center",
        fontSize: BASE_FONT_SIZE,
        // The wrapper itself must never swallow clicks meant for POS.
        pointerEvents: "none"
    },

    panel: {
        pointerEvents: "auto",
        // Positions the overlay shown while files are dragged over the panel, and the toolbar menus.
        position: "relative",
        width: PANEL_WIDTH,
        maxWidth: "100vw",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        minHeight: 0,
        backgroundColor: tokens.colorNeutralBackground2,
        ...shorthands.borderLeft("1px", "solid", tokens.colorNeutralStroke2),
        boxShadow: tokens.shadow8
    },

    toolbar: {
        display: "flex",
        alignItems: "center",
        columnGap: "4px",
        flexShrink: 0,
        ...shorthands.padding("8px", "10px")
    },

    /* Pushes New chat and More options to the end of the toolbar. */
    toolbarSpacer: {
        flexGrow: 1
    },

    /* The size of the buttons beside it, so the row lines up. */
    signInBadge: {
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        width: "32px",
        height: "32px",
        fontSize: "20px",
        color: tokens.colorPaletteGreenForeground1
    },

    /* The toolbar menus render inside the panel, below its z-index, so they are lifted over any card in
       the conversation that is positioned. */
    menuPopover: {
        zIndex: 10
    },

    brand: {
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        columnGap: "12px",
        flexShrink: 0,
        ...shorthands.padding("24px", "16px", "48px")
    },

    brandName: {
        fontSize: tokens.fontSizeHero800,
        lineHeight: tokens.lineHeightHero800,
        fontWeight: tokens.fontWeightBold,
        color: tokens.colorNeutralForeground1
    },

    messages: {
        flexGrow: 1,
        minHeight: 0,
        overflowY: "auto",
        display: "flex",
        flexDirection: "column",
        rowGap: "12px",
        ...shorthands.padding("8px", `${CONVERSATION_PADDING_PX}px`, `${CONVERSATION_PADDING_PX}px`),
        // A flex column shrinks its items to fit before it overflows, and an item that clips its own
        // content, like the product preview, can shrink to nothing. Without this a tall preview or an
        // open comparison is cut off and the conversation is left with nothing to scroll.
        "& > *": {
            flexShrink: 0
        }
    },

    /* Before the first message the conversation can only hold the progress of an automatic cart
       check, so it takes no room until there is one. */
    messagesEmpty: {
        flexGrow: 0,
        ...shorthands.padding("0", `${CONVERSATION_PADDING_PX}px`),
        ":not(:empty)": {
            paddingBottom: "12px"
        }
    },

    /* The day the conversation started, ruled off from it. */
    dayDivider: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px",
        marginBottom: "8px",
        paddingLeft: "12px",
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        "::after": {
            content: "\"\"",
            flexGrow: 1,
            height: "1px",
            backgroundColor: tokens.colorNeutralStroke2
        }
    },

    /* What the operator sent, on a card at the end of the line. */
    bubbleUser: {
        alignSelf: "flex-end",
        maxWidth: "92%",
        boxSizing: "border-box",
        marginBottom: "8px",
        ...shorthands.padding("10px", "16px"),
        ...shorthands.borderRadius(tokens.borderRadiusXLarge),
        backgroundColor: tokens.colorNeutralBackground1,
        boxShadow: tokens.shadow2,
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300,
        whiteSpace: "pre-wrap",
        wordBreak: "break-word"
    },

    /* Replies are plain text across the conversation, with their cards beneath. */
    bubbleAssistant: {
        alignSelf: "stretch",
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300,
        whiteSpace: "pre-wrap",
        wordBreak: "break-word"
    },

    progress: {
        alignSelf: "flex-start",
        display: "flex",
        alignItems: "center",
        columnGap: "10px",
        ...shorthands.padding("2px", "0")
    },

    progressGlyph: {
        display: "grid",
        gridTemplateColumns: "repeat(3, 4px)",
        gridAutoRows: "4px",
        rowGap: "1px",
        columnGap: "1px",
        flexShrink: 0
    },

    progressCell: {
        backgroundColor: tokens.colorNeutralForeground1,
        animationName: {
            "0%": { opacity: 1 },
            "50%": { opacity: 0.15 },
            "100%": { opacity: 1 }
        },
        animationDuration: "1.5s",
        animationTimingFunction: "ease-in-out",
        animationIterationCount: "infinite",
        "@media (prefers-reduced-motion: reduce)": {
            animationName: "none"
        },
        "@media (forced-colors: active)": {
            backgroundColor: "CanvasText"
        }
    },

    /* A lighter band sweeps across the words while the assistant works. */
    progressLabel: {
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300,
        color: "transparent",
        backgroundImage: `linear-gradient(90deg, ${tokens.colorNeutralForeground1} 30%, `
            + `${tokens.colorNeutralForeground4} 50%, ${tokens.colorNeutralForeground1} 70%)`,
        backgroundSize: "200% 100%",
        backgroundClip: "text",
        WebkitBackgroundClip: "text",
        animationName: {
            from: { backgroundPosition: "100% 0" },
            to: { backgroundPosition: "-100% 0" }
        },
        animationDuration: "2s",
        animationTimingFunction: "linear",
        animationIterationCount: "infinite",
        "@media (prefers-reduced-motion: reduce)": {
            animationName: "none",
            backgroundImage: "none",
            color: tokens.colorNeutralForeground2
        },
        "@media (forced-colors: active)": {
            animationName: "none",
            backgroundImage: "none",
            color: "CanvasText"
        }
    },

    /* Marks a reply POS asked for on its own, so it is not mistaken for an answer to the operator. */
    suggestionCaption: {
        alignSelf: "flex-start",
        display: "flex",
        alignItems: "center",
        columnGap: "4px",
        marginBottom: "-4px",
        color: tokens.colorBrandForeground1,
        fontSize: tokens.fontSizeBase200,
        fontWeight: tokens.fontWeightSemibold
    },

    /* Action receipts sit under the reply, visually quieter than a message. */
    receipt: {
        alignSelf: "stretch",
        display: "flex",
        alignItems: "flex-start",
        columnGap: "6px",
        ...shorthands.padding("6px", "8px"),
        ...shorthands.borderRadius("6px"),
        backgroundColor: tokens.colorNeutralBackground1,
        ...shorthands.borderLeft("3px", "solid", tokens.colorBrandStroke1),
        fontSize: tokens.fontSizeBase200,
        color: tokens.colorNeutralForeground2
    },

    receiptFailed: {
        ...shorthands.borderLeft("3px", "solid", tokens.colorPaletteRedBorder1)
    },

    receiptUnsupported: {
        ...shorthands.borderLeft("3px", "solid", tokens.colorNeutralStroke1)
    },

    orderReceipt: {
        alignSelf: "stretch",
        display: "flex",
        flexDirection: "column",
        rowGap: "10px",
        ...shorthands.padding("12px"),
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderRadius(tokens.borderRadiusLarge),
        backgroundColor: tokens.colorNeutralBackground1,
        boxShadow: tokens.shadow4
    },

    orderReceiptHeader: {
        display: "flex",
        flexWrap: "wrap",
        alignItems: "center",
        justifyContent: "space-between",
        columnGap: "8px",
        rowGap: "4px",
        // Pulled out to the card edges so the divider under the header spans the whole card.
        marginLeft: "-12px",
        marginRight: "-12px",
        ...shorthands.padding("0", "12px", "10px"),
        ...shorthands.borderBottom("1px", "solid", tokens.colorNeutralStroke2),
        fontSize: tokens.fontSizeBase400,
        fontWeight: tokens.fontWeightSemibold
    },

    orderReceiptSuccess: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px",
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase400,
        fontWeight: tokens.fontWeightSemibold
    },

    orderReceiptSuccessIcon: {
        flexShrink: 0,
        color: tokens.colorPaletteGreenForeground1
    },

    orderReceiptRows: {
        display: "grid",
        gridTemplateColumns: "88px minmax(0, 1fr)",
        columnGap: "8px",
        rowGap: "6px",
        fontSize: tokens.fontSizeBase200
    },

    orderReceiptLabel: {
        color: tokens.colorNeutralForeground3
    },

    orderReceiptValue: {
        color: tokens.colorNeutralForeground1,
        fontWeight: tokens.fontWeightSemibold,
        overflowWrap: "anywhere"
    },

    /* The products a shipping card lists, between dividers: name and quantity, then where each ships from. */
    shippingLines: {
        listStyleType: "none",
        display: "flex",
        flexDirection: "column",
        rowGap: "8px",
        ...shorthands.margin("0"),
        ...shorthands.padding("10px", "0"),
        ...shorthands.borderTop("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderBottom("1px", "solid", tokens.colorNeutralStroke2),
        fontSize: tokens.fontSizeBase200
    },

    shippingLine: {
        display: "grid",
        gridTemplateColumns: "minmax(0, 1fr) auto",
        columnGap: "8px",
        rowGap: "2px"
    },

    shippingLineName: {
        color: tokens.colorNeutralForeground1,
        fontWeight: tokens.fontWeightSemibold,
        overflowWrap: "anywhere"
    },

    shippingLineQuantity: {
        color: tokens.colorNeutralForeground1,
        fontWeight: tokens.fontWeightSemibold,
        textAlign: "right"
    },

    shippingLineSource: {
        gridColumn: "1 / -1",
        color: tokens.colorNeutralForeground3,
        overflowWrap: "anywhere"
    },

    /* The products the agent picked, as one card: a heading, the agent's summary, then a row per
       product. Follows the Commerce selling agent design. */
    preview: {
        alignSelf: "stretch",
        display: "flex",
        flexDirection: "column",
        ...shorthands.padding("10px", "20px"),
        backgroundColor: tokens.colorNeutralBackground1,
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderRadius("24px")
    },

    previewHeader: {
        display: "flex",
        alignItems: "center",
        columnGap: "12px",
        ...shorthands.padding("2px", "0", "8px")
    },

    previewHeaderIcon: {
        flexShrink: 0,
        width: "20px",
        height: "20px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: tokens.colorNeutralForeground1,
        fontSize: "16px"
    },

    previewTitle: {
        flexGrow: 1,
        minWidth: 0,
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase400,
        fontWeight: tokens.fontWeightBold,
        lineHeight: tokens.lineHeightBase400,
        overflowWrap: "anywhere"
    },

    /* Its chevron lines up with the right edge of the rows' buttons, and it adds no height to the
       heading, which the title sets. */
    previewViewAll: {
        flexShrink: 0,
        ...shorthands.margin("-1px", "-8px", "-1px", "0")
    },

    previewSummary: {
        ...shorthands.margin("0"),
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300,
        overflowWrap: "anywhere"
    },

    /* Under the summary, or the heading when there is none; the product list's divider follows. */
    previewFilters: {
        marginTop: "10px"
    },

    /* The heading already leaves 8px under itself. */
    previewFiltersUnderHeading: {
        marginTop: "2px"
    },

    /* Under the tags: how many products they leave, and Clear. Stays in the card while empty, taking
       no room, so screen readers announce what appears in it. */
    previewFilterStatus: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px",
        minWidth: 0
    },

    previewFilterStatusShown: {
        marginTop: "6px"
    },

    previewFilterStatusText: {
        flexGrow: 1,
        minWidth: 0,
        display: "flex",
        alignItems: "center",
        columnGap: "6px",
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    /* Its text lines up with the right edge of the rows' buttons. */
    previewFilterClear: {
        flexShrink: 0,
        minWidth: 0,
        ...shorthands.margin("-2px", "-8px", "-2px", "0")
    },

    /* Takes the product list's place, under the same divider, when the tags leave no product. */
    previewNoMatch: {
        ...shorthands.margin("10px", "0", "0"),
        ...shorthands.padding("10px", "0", "0"),
        ...shorthands.borderTop("1px", "solid", tokens.colorNeutralStroke2),
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300
    },

    /* Starts under a divider, 10px clear of it on both sides. */
    productList: {
        display: "flex",
        flexDirection: "column",
        listStyleType: "none",
        ...shorthands.margin("10px", "0", "0"),
        ...shorthands.padding("10px", "0", "0"),
        ...shorthands.borderTop("1px", "solid", tokens.colorNeutralStroke2)
    },

    /* Rows after the first open with a divider. With the 6px under each row's button, the line sits
       18px below the button and 12px above the next photo. */
    productRow: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "8px",
        minWidth: 0,
        ":not(:first-child)": {
            marginTop: "12px",
            paddingTop: "12px",
            ...shorthands.borderTop("1px", "solid", tokens.colorNeutralStroke2)
        }
    },

    /* The photo opens the product's details, so it is a button that looks like a plain photo. */
    productImageButton: {
        flexShrink: 0,
        display: "block",
        ...shorthands.margin("0"),
        ...shorthands.padding("0"),
        ...shorthands.border("0"),
        ...shorthands.borderRadius(tokens.borderRadiusMedium),
        backgroundColor: "transparent",
        cursor: "pointer",
        ":focus-visible": {
            outlineWidth: "2px",
            outlineStyle: "solid",
            outlineColor: tokens.colorStrokeFocus2,
            outlineOffset: "2px"
        }
    },

    productImage: {
        flexShrink: 0,
        width: "80px",
        height: "80px",
        ...shorthands.borderRadius(tokens.borderRadiusMedium)
    },

    thumbnail: {
        flexShrink: 0,
        width: "64px",
        height: "64px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: tokens.colorNeutralBackground3,
        color: tokens.colorNeutralForeground4,
        ...shorthands.borderRadius(tokens.borderRadiusLarge),
        ...shorthands.overflow("hidden")
    },

    /* Multiplied onto the tile, so the white around a product photo takes on the tile's colour. */
    thumbnailImage: {
        width: "100%",
        height: "100%",
        objectFit: "contain",
        mixBlendMode: "multiply"
    },

    productInfo: {
        flexGrow: 1,
        minWidth: 0,
        display: "flex",
        flexDirection: "column",
        rowGap: "2px"
    },

    /* Takes the line the design gives the brand, which Commerce does not send. */
    productBestMatch: {
        alignSelf: "flex-start"
    },

    /* The name, with the compare toggle at the top right of the rows the best match can be compared with. */
    productHeading: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "4px",
        minWidth: 0
    },

    /* Two lines, then an ellipsis. The full name is in the title. */
    productName: {
        flexGrow: 1,
        minWidth: 0,
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase400,
        fontWeight: tokens.fontWeightSemibold,
        lineHeight: tokens.lineHeightBase400,
        overflowWrap: "anywhere",
        display: "-webkit-box",
        WebkitLineClamp: 2,
        WebkitBoxOrient: "vertical",
        ...shorthands.overflow("hidden")
    },

    /* Centred on the name's first line, and its icon lines up with the right edge of Add to sale. */
    productCompare: {
        flexShrink: 0,
        ...shorthands.margin("-1px", "-2px", "0", "0")
    },

    productPrice: {
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    /* The variant Add to sale puts in the sale, such as "Cobalt, Medium". */
    productVariant: {
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        overflowWrap: "anywhere"
    },

    productStock: {
        marginTop: "1px"
    },

    /* The agent's own words about the product. The sparkle marks them as the assistant's, as on the
       Best match badge. */
    productReason: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "4px",
        marginTop: "2px",
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        overflowWrap: "anywhere"
    },

    productReasonIcon: {
        flexShrink: 0,
        marginTop: "1px",
        fontSize: "14px",
        color: tokens.colorBrandForeground1
    },

    productReasonText: {
        minWidth: 0
    },

    productActions: {
        ...shorthands.padding("10px", "0", "6px")
    },

    productAdd: {
        width: "100%",
        minWidth: 0
    },

    /* Takes the button's place and height once the product is in the sale. */
    productAdded: {
        minHeight: "32px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        columnGap: "4px",
        backgroundColor: tokens.colorPaletteGreenBackground1,
        color: tokens.colorPaletteGreenForeground1,
        ...shorthands.borderRadius(tokens.borderRadiusMedium),
        fontSize: tokens.fontSizeBase300,
        fontWeight: tokens.fontWeightSemibold
    },

    /* Under the rows: how many of the products show, and Compare options. */
    previewFooter: {
        display: "flex",
        flexDirection: "column",
        rowGap: "8px",
        marginTop: "12px"
    },

    previewMore: {
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    compareOptions: {
        width: "100%",
        minWidth: 0
    },

    /* A table in the card: the best match and the alternative a column each, divided by lines. */
    comparison: {
        display: "flex",
        flexDirection: "column",
        marginTop: "12px",
        backgroundColor: tokens.colorNeutralBackground1,
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderRadius(tokens.borderRadiusXLarge),
        ...shorthands.overflow("hidden")
    },

    comparisonHeader: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px",
        ...shorthands.padding("6px", "6px", "6px", "12px"),
        ...shorthands.borderBottom("1px", "solid", tokens.colorNeutralStroke2)
    },

    comparisonTitle: {
        flexGrow: 1,
        minWidth: 0,
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase300,
        fontWeight: tokens.fontWeightSemibold,
        lineHeight: tokens.lineHeightBase300
    },

    /* Each row's two cells share a grid row, so their tops line up however long either value is. */
    comparisonGrid: {
        display: "grid",
        gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)"
    },

    comparisonHead: {
        minWidth: 0,
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-start",
        rowGap: "6px",
        ...shorthands.padding("12px")
    },

    /* The line between the two columns. */
    comparisonSecondColumn: {
        ...shorthands.borderLeft("1px", "solid", tokens.colorNeutralStroke2)
    },

    comparisonThumbnail: {
        width: "56px",
        height: "56px",
        ...shorthands.borderRadius(tokens.borderRadiusMedium)
    },

    /* Never clipped: telling the two products apart is the point of the comparison. */
    comparisonName: {
        width: "100%",
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase300,
        fontWeight: tokens.fontWeightSemibold,
        lineHeight: tokens.lineHeightBase300,
        overflowWrap: "anywhere"
    },

    comparisonPrice: {
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    comparisonCell: {
        minWidth: 0,
        display: "flex",
        flexDirection: "column",
        rowGap: "2px",
        ...shorthands.padding("8px", "12px"),
        ...shorthands.borderTop("1px", "solid", tokens.colorNeutralStroke2)
    },

    comparisonLabel: {
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    comparisonValue: {
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        overflowWrap: "anywhere"
    },

    comparisonReason: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "4px",
        ...shorthands.padding("8px", "12px", "10px"),
        ...shorthands.borderTop("1px", "solid", tokens.colorNeutralStroke2),
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        overflowWrap: "anywhere"
    },

    composer: {
        flexShrink: 0,
        ...shorthands.padding("8px", `${CONVERSATION_PADDING_PX}px`, "0")
    },

    /* Before the first message the message box is the centre of the panel, under the Commerce name. */
    composerHero: {
        ...shorthands.padding("0", `${CONVERSATION_PADDING_PX}px`)
    },

    /* The message box and its buttons share one rounded frame, which takes the brand colour while any
       of them has focus. */
    composerBox: {
        display: "flex",
        flexDirection: "column",
        backgroundColor: tokens.colorNeutralBackground1,
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke1),
        ...shorthands.borderRadius("12px"),
        boxShadow: tokens.shadow4,
        transitionProperty: "border-color, box-shadow",
        transitionDuration: tokens.durationFaster,
        ":hover": {
            ...shorthands.borderColor(tokens.colorNeutralStroke1Hover)
        },
        ":focus-within": {
            ...shorthands.borderColor(tokens.colorBrandStroke1),
            boxShadow: `0 0 0 1px ${tokens.colorBrandStroke1}, ${tokens.shadow4}`
        }
    },

    /* A raised card with no outline until it has focus. */
    composerBoxHero: {
        ...shorthands.borderRadius("20px"),
        ...shorthands.borderColor("transparent"),
        boxShadow: tokens.shadow16,
        ":hover": {
            ...shorthands.borderColor("transparent")
        },
        ":focus-within": {
            ...shorthands.borderColor(tokens.colorBrandStroke1),
            boxShadow: `0 0 0 1px ${tokens.colorBrandStroke1}, ${tokens.shadow16}`
        }
    },

    /* A plain textarea, so the frame is its only border. It grows with the text to six lines, then
       scrolls. */
    input: {
        display: "block",
        width: "100%",
        boxSizing: "border-box",
        maxHeight: "136px",
        ...shorthands.margin("0"),
        ...shorthands.padding("12px", "14px", "4px"),
        ...shorthands.borderStyle("none"),
        outlineStyle: "none",
        backgroundColor: "transparent",
        color: tokens.colorNeutralForeground1,
        fontFamily: tokens.fontFamilyBase,
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300,
        resize: "none",
        overflowY: "auto",
        "::placeholder": {
            color: tokens.colorNeutralForeground4
        }
    },

    /* Room to start typing in, as on the card in the middle of an empty panel. */
    inputHero: {
        minHeight: "64px",
        ...shorthands.padding("16px", "20px", "4px")
    },

    composerToolbar: {
        display: "flex",
        alignItems: "center",
        columnGap: "4px",
        ...shorthands.padding("4px", "8px", "8px", "14px")
    },

    /* With the plus first, the row starts where the buttons at its end stop. */
    composerToolbarWithAttach: {
        paddingLeft: "8px"
    },

    /* Lines up with the text above it. */
    composerToolbarHero: {
        ...shorthands.padding("4px", "14px", "14px", "20px")
    },

    /* With the plus first, the row starts where the buttons at its end stop, as in the smaller box. */
    composerToolbarHeroWithAttach: {
        paddingLeft: "14px"
    },

    /* Takes the rest of the row, so the buttons stay at its end. Empty unless the mic has news. */
    composerStatus: {
        flexGrow: 1,
        minWidth: 0
    },

    /* Starter prompts fill the rest of an empty panel, and scroll when it is short. */
    suggestions: {
        flexGrow: 1,
        minHeight: 0,
        overflowY: "auto",
        display: "flex",
        flexDirection: "column",
        rowGap: "12px",
        ...shorthands.padding("28px", "32px", `${CONVERSATION_PADDING_PX}px`)
    },

    suggestionList: {
        display: "flex",
        flexDirection: "column",
        rowGap: "12px"
    },

    suggestionPill: {
        flexShrink: 0,
        justifyContent: "flex-start",
        minHeight: "46px",
        height: "auto",
        maxWidth: "none",
        ...shorthands.padding("10px", "16px"),
        ...shorthands.borderRadius("16px"),
        ...shorthands.borderColor(tokens.colorNeutralStroke2),
        backgroundColor: tokens.colorNeutralBackground1,
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        fontWeight: tokens.fontWeightSemibold,
        textAlign: "left",
        whiteSpace: "normal"
    },

    /* The file a starter prompt needs. The whole pill is the button; this only names what to pick. */
    suggestionFile: {
        color: tokens.colorBrandForegroundLink
    },

    seeMore: {
        alignSelf: "flex-end",
        minWidth: 0,
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        fontWeight: tokens.fontWeightRegular,
        [`& .${buttonClassNames.icon}`]: {
            width: "12px",
            height: "12px",
            fontSize: "12px"
        }
    },

    /* A cart plan's insight: how the agent chose, in a tinted box under the heading. */
    cartPlanInsight: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "8px",
        ...shorthands.padding("8px", "10px"),
        ...shorthands.borderRadius(tokens.borderRadiusLarge),
        backgroundColor: tokens.colorBrandBackground2,
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300,
        overflowWrap: "anywhere"
    },

    cartPlanInsightIcon: {
        flexShrink: 0,
        marginTop: "2px",
        fontSize: "16px",
        color: tokens.colorBrandForeground1
    },

    cartPlanInsightLabel: {
        fontWeight: tokens.fontWeightSemibold
    },

    /* The budget and what the plan leaves out, under the insight. */
    cartPlanMeta: {
        display: "flex",
        flexWrap: "wrap",
        alignItems: "center",
        columnGap: "8px",
        rowGap: "4px",
        marginTop: "8px",
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    /* Centred on the photo beside it. */
    cartPlanCheck: {
        flexShrink: 0,
        alignSelf: "flex-start",
        marginTop: "16px",
        marginLeft: "-6px"
    },

    cartPlanImage: {
        flexShrink: 0,
        width: "64px",
        height: "64px",
        ...shorthands.borderRadius(tokens.borderRadiusMedium)
    },

    cartPlanNeed: {
        alignSelf: "flex-start",
        maxWidth: "100%"
    },

    cartPlanWarning: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "4px",
        color: tokens.colorStatusWarningForeground1,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    cartPlanWarningIcon: {
        flexShrink: 0,
        marginTop: "1px",
        fontSize: "14px"
    },

    cartPlanItemActions: {
        display: "flex",
        alignItems: "center",
        minHeight: "24px",
        ...shorthands.padding("8px", "0", "2px")
    },

    cartPlanItemAdded: {
        display: "flex",
        alignItems: "center",
        columnGap: "4px",
        color: tokens.colorPaletteGreenForeground1,
        fontSize: tokens.fontSizeBase200,
        fontWeight: tokens.fontWeightSemibold
    },

    /* Under the rows, past a divider: what is selected, its total, and the button that adds it. */
    cartPlanFooter: {
        display: "flex",
        flexDirection: "column",
        rowGap: "8px",
        marginTop: "12px",
        ...shorthands.padding("12px", "0", "6px"),
        ...shorthands.borderTop("1px", "solid", tokens.colorNeutralStroke2)
    },

    cartPlanTotals: {
        display: "flex",
        alignItems: "baseline",
        justifyContent: "space-between",
        columnGap: "8px",
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300
    },

    cartPlanTotal: {
        flexShrink: 0,
        color: tokens.colorNeutralForeground1,
        fontWeight: tokens.fontWeightSemibold
    },

    cartPlanError: {
        color: tokens.colorStatusDangerForeground1,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    cartPlanAddAll: {
        width: "100%",
        minWidth: 0
    },

    /* A failure POS just reported, offered above the message box until the associate asks about it or
       dismisses it. */
    posErrorHelp: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px",
        marginBottom: "8px",
        ...shorthands.padding("6px", "6px", "6px", "10px"),
        ...shorthands.border("1px", "solid", tokens.colorStatusDangerBorder1),
        ...shorthands.borderRadius("12px"),
        backgroundColor: tokens.colorStatusDangerBackground1,
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    posErrorHelpIcon: {
        flexShrink: 0,
        fontSize: "16px",
        color: tokens.colorStatusDangerForeground1
    },

    posErrorHelpText: {
        flexGrow: 1,
        minWidth: 0,
        display: "flex",
        flexDirection: "column",
        overflowWrap: "anywhere"
    },

    posErrorHelpTitle: {
        fontWeight: tokens.fontWeightSemibold
    },

    posErrorHelpCode: {
        color: tokens.colorNeutralForeground2
    },

    posErrorHelpButton: {
        flexShrink: 0
    },

    footer: {
        flexShrink: 0,
        ...shorthands.padding("6px", `${CONVERSATION_PADDING_PX}px`, "10px"),
        textAlign: "center",
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    }
});

export interface SideChatPanelProps {
    /** Backend used to answer prompts. */
    client: ISideChatClient;
    /** Header text. */
    title?: string;
    /** Starter prompts shown before the first message. */
    suggestions?: ReadonlyArray<SideChatSuggestion>;
    /**
     * Reads the POS view that is open right now. Called at send time rather than once at mount, so
     * the context follows the operator as they navigate with the panel open.
     */
    getViewContext?: () => string | null;
    /**
     * Runs the actions the agent chose. Supplied by the POS extension, because only POS code can
     * reach the navigator and the runtime; this bundle deliberately knows nothing about either. The
     * panel passes `{ automatic: true }` for the actions of an automatic cart check.
     */
    executeActions?: (
        actions: ReadonlyArray<IAgentPosAction>,
        options?: IAgentActionExecutionOptions
    ) => Promise<ReadonlyArray<IActionReceipt>>;
    /** Opens one product from an inline Commerce-resolved preview. */
    onPreviewProductActivated?: (recordId: number) => void;
    /** Adds one Commerce-resolved product or variant to the current sale. */
    onPreviewAddToSale?: (recordId: number) => Promise<void>;
    /** Opens the full recommended-products view for an inline preview, with the filter tags selected in it. */
    onPreviewViewAll?: (preview: IAgentProductPreview, selection?: IAgentProductFilterSelection) => void;
    /**
     * Finds which of the products shown have the selected tags other than prices, as record
     * identifiers from the request. Without it, only the tags POS can match from the products shown filter.
     */
    onFilterProducts?: (request: IAgentProductFilterRequest) => Promise<ReadonlyArray<number>>;
    /**
     * Adds several Commerce-resolved products or variants to the current sale at once, from a cart
     * plan. Without it, a cart plan adds its products one at a time with `onPreviewAddToSale`.
     */
    onAddProductsToSale?: (recordIds: ReadonlyArray<number>) => Promise<void>;
    /** Formats an amount in the store's currency. Without it, amounts show with two decimals. */
    formatCurrency?: (amount: number) => string;
}

/** An automatic cart check whose suggestions are ready to show. */
interface IReadyCartSuggestion {
    /** The version of the request it answers. */
    version: number;
    reply: ICartSuggestionReply;
    /** Only the receipts that carry products to show. */
    receipts: ReadonlyArray<IActionReceipt>;
}

let messageSequence: number = 0;

/**
 * Reads the words of a starter prompt.
 * @param suggestion The starter prompt.
 * @returns Its text.
 */
function getSuggestionText(suggestion: SideChatSuggestion): string {
    return typeof suggestion === "string" ? suggestion : suggestion.text;
}

/**
 * Reads the word that names the file a starter prompt needs.
 * @param suggestion The starter prompt.
 * @returns The word, or null when the prompt can be sent as it is.
 */
function getSuggestionFileWord(suggestion: SideChatSuggestion): string | null {
    return typeof suggestion !== "string" && suggestion.attachmentWord ? suggestion.attachmentWord : null;
}

/**
 * Shows a starter prompt with the word that names the file it needs picked out.
 * @param suggestion The starter prompt.
 * @param fileClassName The class for that word.
 * @returns The prompt's content, in one span: the button lays out its children as flex items, which
 * would drop the spaces either side of the word.
 */
function renderSuggestionText(suggestion: SideChatSuggestion, fileClassName: string): React.ReactNode {
    const text: string = getSuggestionText(suggestion);
    const word: string | null = getSuggestionFileWord(suggestion);
    const index: number = word ? text.indexOf(word) : -1;
    if (!word || index < 0) {
        return text;
    }

    return (
        <span>
            {text.slice(0, index)}
            <span className={fileClassName}>{word}</span>
            {text.slice(index + word.length)}
        </span>
    );
}

/**
 * Names the day a conversation started, the way a chat app heads it.
 * @param day When the conversation started.
 * @returns Today, Yesterday, or the date.
 */
function formatConversationDay(day: Date): string {
    const startOfDay = (date: Date): number => new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
    const daysAgo: number = Math.round((startOfDay(new Date()) - startOfDay(day)) / 86400000);
    if (daysAgo === 0) {
        return "Today";
    }

    if (daysAgo === 1) {
        return "Yesterday";
    }

    return day.toLocaleDateString(undefined, { month: "long", day: "numeric" });
}

/**
 * Finds the POS header bar that is on screen.
 * @returns The header, or null when the open view has none.
 */
function findPosHeader(): HTMLElement | null {
    const headers: HTMLElement[] = Array.from(document.querySelectorAll<HTMLElement>(POS_HEADER_SELECTOR));
    return headers.find((header: HTMLElement) => header.getBoundingClientRect().height > 0) ?? null;
}

/**
 * Keeps the panel under the POS header, so the header and its Copilot button stay in reach while the
 * panel is open. It follows the header as the window resizes and as views show or hide it; a view
 * without one gives the panel the full height.
 * @param isOpen True while the panel is open. Nothing is measured while it is closed.
 * @returns How far down the window the panel starts, in pixels.
 */
function usePosHeaderOffset(isOpen: boolean): number {
    const [offset, setOffset] = React.useState<number>(0);

    React.useLayoutEffect(() => {
        if (!isOpen) {
            return undefined;
        }

        let observer: ResizeObserver | undefined;
        let observed: HTMLElement | null = null;
        const measure = (): void => {
            try {
                const header: HTMLElement | null = findPosHeader();
                setOffset(header ? Math.max(0, Math.round(header.getBoundingClientRect().bottom)) : 0);

                // POS keeps the element when a view hides its header and only changes its class and
                // size, so the one already watched stays watched.
                if (header && header !== observed && observer) {
                    if (observed) {
                        observer.unobserve(observed);
                    }

                    observer.observe(header);
                    observed = header;
                }
            } catch {
                setOffset(0);
            }
        };

        observer = typeof ResizeObserver === "function" ? new ResizeObserver(measure) : undefined;
        measure();
        window.addEventListener("resize", measure);
        return () => {
            window.removeEventListener("resize", measure);
            if (observer) {
                observer.disconnect();
            }
        };
    }, [isOpen]);

    return offset;
}

/**
 * Builds a conversation message with a stable unique id.
 * @param role Who authored the message.
 * @param text The message body.
 * @param toolActivities The tools the agent used for the message. They are not shown; a knowledge base
 * search gives the reply a Copy button.
 * @param origin Set when POS asked for the message on its own.
 * @param attachments The files the operator sent with the message.
 * @returns The message.
 */
function createMessage(
    role: SideChatMessage["role"],
    text: string,
    toolActivities?: ReadonlyArray<IAgentToolActivity>,
    origin?: SideChatMessage["origin"],
    attachments?: ReadonlyArray<ISideChatAttachmentPreview>
): SideChatMessage {
    messageSequence += 1;
    const message: SideChatMessage = { id: `side-msg-${Date.now()}-${messageSequence}`, role, text, toolActivities, origin };
    if (attachments && attachments.length > 0) {
        message.attachments = attachments;
    }

    return message;
}

/**
 * Lists every product in the cart a check was about, including the masters of variants in it.
 * @param request The automatic cart check.
 * @returns The distinct product record identifiers.
 */
function getProductIdsInCart(request: ICartSuggestionRequest): number[] {
    const ids: number[] = [...request.cart.productIds];
    request.cart.lines.forEach((line: IAgentCartLine) => {
        ids.push(line.productId);
        if (typeof line.masterProductId === "number") {
            ids.push(line.masterProductId);
        }
    });

    return ids.filter((id: number, index: number) => ids.indexOf(id) === index);
}

/** What a product thumbnail needs. */
interface IProductThumbnailProps {
    imageUrl?: string;
    className?: string;
    /** Size of the icon shown when there is no image, in pixels. Defaults to 24. */
    placeholderSize?: number;
}

/**
 * A product's image on a neutral tile, or a placeholder icon when it has none or it fails to load.
 * @param props The image and the tile's class.
 * @returns The rendered thumbnail.
 */
const ProductThumbnail: React.FC<IProductThumbnailProps> = (props) => {
    const styles = useStyles();
    // Remembered by address, so a different image gets its own chance to load.
    const [failedUrl, setFailedUrl] = React.useState<string | undefined>(undefined);
    const imageUrl: string | undefined = props.imageUrl;

    return (
        <div className={mergeClasses(styles.thumbnail, props.className)}>
            {imageUrl && imageUrl !== failedUrl ? (
                <img className={styles.thumbnailImage} src={imageUrl} alt="" onError={() => setFailedUrl(imageUrl)} />
            ) : (
                <ImageOffRegular fontSize={props.placeholderSize ?? 24} aria-hidden="true" />
            )}
        </div>
    );
};

/** What the inline comparison needs. */
interface IInlineProductComparisonProps {
    /** The comparison's element id, for the buttons that control it. */
    id: string;
    bestMatch: IAgentProductCard;
    comparedProduct: IAgentProductCard;
    bestMatchReason?: string;
    /** Called with the comparison's element each time a product is opened in it. */
    onShown?: (element: HTMLElement) => void;
    /** Closes the comparison. */
    onClose: () => void;
}

/**
 * The best match and one other recommended product side by side, as a table with a column each. The
 * compare toggle on each other product's row chooses which one fills the second column.
 * @param props The two products and the agent's reason for its pick.
 * @returns The rendered comparison.
 */
const InlineProductComparison: React.FC<IInlineProductComparisonProps> = (props) => {
    const styles = useStyles();
    const rootRef = React.useRef<HTMLElement>(null);
    const onShown: ((element: HTMLElement) => void) | undefined = props.onShown;
    const comparedProductId: number = props.comparedProduct.recordId;

    // The comparison opens at the bottom of the card, which is usually below the visible part of the
    // conversation. Runs before paint so the conversation moves only once.
    React.useLayoutEffect(() => {
        if (rootRef.current && onShown) {
            onShown(rootRef.current);
        }
    }, [comparedProductId, onShown]);

    // Price is left out: each column's heading shows it.
    const rows: ReadonlyArray<{ label: string; value: (product: IAgentProductCard) => string }> = [
        {
            label: "Variant",
            value: (product) => product.dimensionValues && product.dimensionValues.length > 0
                ? product.dimensionValues.join(", ")
                : "Not specified"
        },
        { label: "Item", value: (product) => product.itemId ?? "Unavailable" },
        { label: "Details", value: (product) => product.description ?? "Unavailable" }
    ];
    const columns: ReadonlyArray<{ product: IAgentProductCard; isBestMatch: boolean }> = [
        { product: props.bestMatch, isBestMatch: true },
        { product: props.comparedProduct, isBestMatch: false }
    ];

    return (
        <section id={props.id} ref={rootRef} className={styles.comparison} aria-label="Product comparison">
            <div className={styles.comparisonHeader}>
                <span className={styles.comparisonTitle}>Compare with best match</span>
                <Button
                    appearance="subtle"
                    size="small"
                    icon={<DismissRegular />}
                    aria-label="Close comparison"
                    title="Close comparison"
                    onClick={props.onClose}
                />
            </div>

            <div className={styles.comparisonGrid}>
                {columns.map((column, columnIndex: number) => (
                    <div
                        key={column.product.recordId}
                        className={mergeClasses(styles.comparisonHead, columnIndex > 0 && styles.comparisonSecondColumn)}
                    >
                        {column.isBestMatch ? (
                            <Badge appearance="filled" color="brand" size="small" icon={<SparkleFilled />}>Best match</Badge>
                        ) : (
                            <Badge appearance="tint" color="informative" size="small">Alternative</Badge>
                        )}
                        <ProductThumbnail
                            className={styles.comparisonThumbnail}
                            imageUrl={column.product.imageUrl}
                            placeholderSize={20}
                        />
                        <span className={styles.comparisonName}>{column.product.name}</span>
                        <span className={styles.comparisonPrice}>{column.product.priceText ?? "Price unavailable"}</span>
                    </div>
                ))}

                {rows.map((row) => columns.map((column, columnIndex: number) => (
                    <div
                        key={`${row.label}-${column.product.recordId}`}
                        className={mergeClasses(styles.comparisonCell, columnIndex > 0 && styles.comparisonSecondColumn)}
                    >
                        <span className={styles.comparisonLabel}>{row.label}</span>
                        <span className={styles.comparisonValue}>{row.value(column.product)}</span>
                    </div>
                )))}
            </div>

            {props.bestMatchReason && (
                <span className={styles.comparisonReason}>
                    <SparkleFilled className={styles.productReasonIcon} aria-hidden="true" />
                    <span className={styles.productReasonText}>{props.bestMatchReason}</span>
                </span>
            )}
        </section>
    );
};

/**
 * Joins the order card parts that are present, in order, with the card's separator.
 * @param parts The parts to show. Missing or blank parts are skipped.
 * @returns The joined text, or an empty string when no part is present.
 */
function joinReceiptParts(...parts: ReadonlyArray<string | undefined>): string {
    return parts
        .filter((part: string | undefined): part is string => typeof part === "string" && part.trim().length > 0)
        .join(" \u00b7 ");
}

/**
 * The Commerce-confirmed customer order, shown under the reply that created it.
 * @param props The receipt POS built from the concluded sales order.
 * @returns The rendered order card.
 */
const CustomerOrderReceipt: React.FC<{ receipt: IAgentCustomerOrderReceipt }> = ({ receipt }) => {
    const styles = useStyles();

    // Rows without a value, such as inventory context the agent did not supply, are left out.
    const rows: ReadonlyArray<{ label: string; value: string }> = [
        { label: "Item", value: receipt.itemName },
        { label: "Order #", value: receipt.orderNumber },
        {
            label: "Sourced from",
            value: joinReceiptParts(receipt.sourceStore, receipt.sourceStoreAvailability, receipt.sourceStoreDistance)
        },
        { label: "Current store", value: joinReceiptParts(receipt.currentStoreAvailability) },
        { label: "Ship to", value: joinReceiptParts(receipt.customerName, receipt.shippingAddress) },
        { label: "Method", value: receipt.deliveryMethod }
    ].filter((row: { label: string; value: string }) => typeof row.value === "string" && row.value.length > 0);

    return (
        <section className={styles.orderReceipt} aria-label={`Customer order ${receipt.orderNumber}`} data-message-card="">
            <div className={styles.orderReceiptHeader}>
                <span>Order created</span>
            </div>
            <div className={styles.orderReceiptSuccess}>
                <CheckmarkCircleFilled className={styles.orderReceiptSuccessIcon} fontSize={24} aria-hidden="true" />
                <span>Customer order created</span>
            </div>
            <div className={styles.orderReceiptRows}>
                {rows.map((row) => (
                    <React.Fragment key={row.label}>
                        <span className={styles.orderReceiptLabel}>{row.label}</span>
                        <span className={styles.orderReceiptValue}>{row.value}</span>
                    </React.Fragment>
                ))}
                <span className={styles.orderReceiptLabel}>Status</span>
                <span className={styles.orderReceiptValue}>
                    <Badge appearance="tint" color="success">{receipt.status}</Badge>
                </span>
            </div>
        </section>
    );
};

/**
 * What POS set when it set the sale to ship, shown under the reply that asked for it. The order stays
 * on the sale for the associate to take payment.
 * @param props The receipt POS built from the sale after it saved the shipping.
 * @returns The rendered shipping card.
 */
const ShippingReceipt: React.FC<{ receipt: IAgentShippingReceipt }> = ({ receipt }) => {
    const styles = useStyles();
    const hasValue = (row: { label: string; value?: string }): row is { label: string; value: string } =>
        typeof row.value === "string" && row.value.length > 0;

    const details: ReadonlyArray<{ label: string; value: string }> = [
        { label: "Customer", value: joinReceiptParts(receipt.customerName, receipt.customerAccount) },
        { label: "Ship to", value: joinReceiptParts(receipt.addressType, receipt.shippingAddress) },
        { label: "Method", value: receipt.deliveryMethod },
        { label: "Delivery", value: receipt.deliveryDate }
    ].filter(hasValue);
    const amounts: ReadonlyArray<{ label: string; value: string }> = [
        { label: "Shipping", value: receipt.shippingCharges },
        { label: "Total", value: receipt.total },
        { label: "Amount due", value: receipt.amountDue }
    ].filter(hasValue);

    return (
        <section className={styles.orderReceipt} aria-label={`Shipping for ${receipt.customerName}`} data-message-card="">
            <div className={styles.orderReceiptHeader}>
                <span>Shipping set</span>
                <Badge appearance="tint" color="success" icon={<CheckmarkCircleFilled />}>{receipt.status}</Badge>
            </div>
            <div className={styles.orderReceiptRows}>
                {details.map((row) => (
                    <React.Fragment key={row.label}>
                        <span className={styles.orderReceiptLabel}>{row.label}</span>
                        <span className={styles.orderReceiptValue}>{row.value}</span>
                    </React.Fragment>
                ))}
            </div>
            {receipt.lines.length > 0 && (
                <ul className={styles.shippingLines} aria-label="Products that ship">
                    {receipt.lines.map((line: IAgentShippingReceiptLine, index: number) => (
                        <li key={`${line.name}-${index}`} className={styles.shippingLine}>
                            <span className={styles.shippingLineName}>{line.name}</span>
                            <span className={styles.shippingLineQuantity}>{`\u00d7${line.quantity}`}</span>
                            <span className={styles.shippingLineSource}>
                                {`Ships from ${joinReceiptParts(line.shipFrom, line.shipFromDetail)}`}
                            </span>
                        </li>
                    ))}
                </ul>
            )}
            {amounts.length > 0 && (
                <div className={styles.orderReceiptRows}>
                    {amounts.map((row) => (
                        <React.Fragment key={row.label}>
                            <span className={styles.orderReceiptLabel}>{row.label}</span>
                            <span className={styles.orderReceiptValue}>{row.value}</span>
                        </React.Fragment>
                    ))}
                </div>
            )}
        </section>
    );
};

/**
 * The words sent when the associate asks for help with a failure POS reported. The failure itself goes
 * with the request.
 * @param error The failure.
 * @returns The message, for example "Help me with this customer order lookup error".
 */
function describePosErrorHelpRequest(error: IAgentPosErrorContext): string {
    const operation: string = (error.operation || "").trim();
    const subject: string = operation.length > 0
        ? operation.charAt(0).toLowerCase() + operation.slice(1)
        : "POS";
    return `Help me with this ${subject} error`;
}

/**
 * Formats an amount with the store's formatter, or with two decimals when there is none.
 * @param amount The amount.
 * @param formatCurrency The store's formatter, when POS supplied one.
 * @returns The formatted amount.
 */
function formatAmount(amount: number, formatCurrency?: (amount: number) => string): string {
    if (formatCurrency) {
        try {
            const text: string = formatCurrency(amount);
            if (typeof text === "string" && text.length > 0) {
                return text;
            }
        } catch {
            // The plain format below still shows the amount.
        }
    }

    return amount.toFixed(2);
}

/**
 * Adds up the prices POS read for the given products. Products without a price add nothing.
 * @param items The products.
 * @returns Their total.
 */
function sumCartPlanPrices(items: ReadonlyArray<IAgentCartPlanReceiptItem>): number {
    return items.reduce((total: number, item: IAgentCartPlanReceiptItem) => {
        const price: number | undefined = item.card.price;
        return typeof price === "number" && isFinite(price) ? total + price : total;
    }, 0);
}

/** What a cart plan card needs. */
interface ICartPlanCardProps {
    plan: IAgentCartPlanReceipt;
    /** Opens one product in the POS details view. */
    onProductActivated?: (recordId: number) => void;
    /** Adds products or variants to the current sale in one go. */
    onAddProducts?: (recordIds: ReadonlyArray<number>) => Promise<void>;
    formatCurrency?: (amount: number) => string;
}

/**
 * A cart the agent planned from what the customer is shopping for: how it chose, then one row per
 * need with a check box. Everything starts selected except products over a per-item budget. The
 * associate adds the selected products in one go, or any one of them on its own.
 * @param props The plan POS resolved from the channel.
 * @returns The rendered plan.
 */
const CartPlanCard: React.FC<ICartPlanCardProps> = (props) => {
    const styles = useStyles();
    const idPrefix: string = useId("side-chat-plan-");
    const plan: IAgentCartPlanReceipt = props.plan;
    const items: ReadonlyArray<IAgentCartPlanReceiptItem> = plan.items;
    const [selectedIds, setSelectedIds] = React.useState<ReadonlySet<number>>(() => new Set<number>(
        items
            .filter((item: IAgentCartPlanReceiptItem) => !item.overBudget)
            .map((item: IAgentCartPlanReceiptItem) => item.card.recordId)));
    const [adding, setAdding] = React.useState<{ ids: ReadonlySet<number>; isSelection: boolean } | null>(null);
    const [addedIds, setAddedIds] = React.useState<ReadonlySet<number>>(new Set<number>());
    const [error, setError] = React.useState<string | undefined>(undefined);

    const format = (amount: number): string => formatAmount(amount, props.formatCurrency);
    const budget = plan.budget;
    const isTotalBudget: boolean = !!budget && budget.appliesTo === "total";
    const isBusy: boolean = adding !== null;
    const isAddingSelection: boolean = adding !== null && adding.isSelection;
    const pending: ReadonlyArray<IAgentCartPlanReceiptItem> =
        items.filter((item: IAgentCartPlanReceiptItem) => !addedIds.has(item.card.recordId));
    const selected: ReadonlyArray<IAgentCartPlanReceiptItem> =
        pending.filter((item: IAgentCartPlanReceiptItem) => selectedIds.has(item.card.recordId));
    const selectedTotal: number = sumCartPlanPrices(selected);
    // A total budget covers what was already added from the plan as well as what is selected.
    const plannedTotal: number = selectedTotal
        + sumCartPlanPrices(items.filter((item: IAgentCartPlanReceiptItem) => addedIds.has(item.card.recordId)));
    const budgetLeft: number = budget ? budget.amount - plannedTotal : 0;

    const addProducts = (planItems: ReadonlyArray<IAgentCartPlanReceiptItem>, isSelection: boolean): void => {
        if (!props.onAddProducts || planItems.length === 0 || isBusy) {
            return;
        }

        const displayIds: number[] = planItems.map((item: IAgentCartPlanReceiptItem) => item.card.recordId);
        const saleIds: number[] = planItems.map(
            (item: IAgentCartPlanReceiptItem) => item.card.selectedVariantId ?? item.card.recordId);
        setError(undefined);
        setAdding({ ids: new Set<number>(displayIds), isSelection });
        props.onAddProducts(saleIds)
            .then(() => {
                setAddedIds((current: ReadonlySet<number>) => {
                    const next = new Set<number>(current);
                    displayIds.forEach((id: number) => next.add(id));
                    return next;
                });
            })
            .catch((reason: unknown) => {
                const detail: string = reason instanceof Error && reason.message ? ` ${reason.message}` : "";
                setError(`Couldn't add ${planItems.length === 1 ? "it" : "them"} to the sale.${detail}`);
            })
            .then(() => {
                setAdding(null);
            });
    };

    const setSelected = (recordId: number, isSelected: boolean): void => {
        setSelectedIds((current: ReadonlySet<number>) => {
            const next = new Set<number>(current);
            if (isSelected) {
                next.add(recordId);
            } else {
                next.delete(recordId);
            }

            return next;
        });
    };

    const budgetLabel: string | undefined = budget
        ? (isTotalBudget ? `Budget ${format(budget.amount)}` : `Under ${format(budget.amount)} each`)
        : undefined;
    const omittedCount: number = plan.omittedCount ?? 0;
    const title: string = plan.headline || plan.intent || "Suggested cart";

    return (
        <div role="group" className={styles.preview} aria-label={`Cart plan: ${title}`} data-message-card="">
            <div className={styles.previewHeader}>
                <span className={styles.previewHeaderIcon} aria-hidden="true">
                    <CartRegular />
                </span>
                <span className={styles.previewTitle}>{title}</span>
            </div>

            {plan.summary && (
                <div className={styles.cartPlanInsight}>
                    <LightbulbRegular className={styles.cartPlanInsightIcon} aria-hidden="true" />
                    <span>
                        <span className={styles.cartPlanInsightLabel}>Why these items: </span>
                        {plan.summary}
                    </span>
                </div>
            )}

            {(budgetLabel || omittedCount > 0) && (
                <div className={styles.cartPlanMeta}>
                    {budgetLabel && <Badge appearance="tint" color="informative">{budgetLabel}</Badge>}
                    <span>{`${items.length} ${items.length === 1 ? "item" : "items"}, one per need`}</span>
                    {omittedCount > 0 && (
                        <span>{`${omittedCount} similar or unavailable ${omittedCount === 1 ? "item" : "items"} left out`}</span>
                    )}
                </div>
            )}

            <ul className={styles.productList} aria-label="Products in the plan">
                {items.map((item: IAgentCartPlanReceiptItem) => {
                    const card: IAgentProductCard = item.card;
                    const isAdded: boolean = addedIds.has(card.recordId);
                    const isAdding: boolean = adding !== null && !adding.isSelection && adding.ids.has(card.recordId);
                    const variant: string = card.dimensionValues?.join(", ") ?? "";
                    const nameId: string = `${idPrefix}-${card.recordId}-name`;
                    const image: React.ReactElement = (
                        <ProductThumbnail className={styles.cartPlanImage} imageUrl={card.imageUrl} placeholderSize={24} />
                    );

                    return (
                        <li key={card.recordId} className={styles.productRow}>
                            <Checkbox
                                className={styles.cartPlanCheck}
                                checked={isAdded || selectedIds.has(card.recordId)}
                                disabled={isAdded || isBusy || !props.onAddProducts}
                                aria-labelledby={nameId}
                                onChange={(_event: React.ChangeEvent<HTMLInputElement>, data: { checked: boolean | "mixed" }) =>
                                    setSelected(card.recordId, data.checked === true)}
                            />

                            {props.onProductActivated ? (
                                <button
                                    type="button"
                                    className={styles.productImageButton}
                                    aria-label={`Details for ${card.name}`}
                                    title="Details"
                                    onClick={() => props.onProductActivated?.(card.recordId)}
                                >
                                    {image}
                                </button>
                            ) : image}

                            <div className={styles.productInfo}>
                                {item.need && (
                                    <Badge className={styles.cartPlanNeed} appearance="tint" color="brand" size="small">
                                        {item.need}
                                    </Badge>
                                )}
                                <span id={nameId} className={styles.productName} title={card.name}>{card.name}</span>
                                {card.priceText && <span className={styles.productPrice}>{card.priceText}</span>}
                                {variant.length > 0 && <span className={styles.productVariant}>{variant}</span>}
                                {item.overBudget && budget && (
                                    <span className={styles.cartPlanWarning}>
                                        <WarningRegular className={styles.cartPlanWarningIcon} aria-hidden="true" />
                                        <span>{`Over ${format(budget.amount)}, so not selected`}</span>
                                    </span>
                                )}
                                {item.reason && (
                                    <span className={styles.productReason}>
                                        <SparkleFilled className={styles.productReasonIcon} aria-hidden="true" />
                                        <span className={styles.productReasonText}>{item.reason}</span>
                                    </span>
                                )}

                                <div className={styles.cartPlanItemActions}>
                                    {isAdded ? (
                                        <span className={styles.cartPlanItemAdded} role="status">
                                            <CheckmarkCircleFilled aria-hidden="true" />
                                            Added
                                        </span>
                                    ) : (
                                        <Button
                                            appearance="secondary"
                                            size="small"
                                            icon={isAdding ? <Spinner size="tiny" /> : <CartRegular />}
                                            disabled={!props.onAddProducts || isBusy}
                                            aria-describedby={nameId}
                                            onClick={() => addProducts([item], false)}
                                        >
                                            {isAdding ? "Adding\u2026" : "Add to sale"}
                                        </Button>
                                    )}
                                </div>
                            </div>
                        </li>
                    );
                })}
            </ul>

            <div className={styles.cartPlanFooter}>
                {pending.length === 0 ? (
                    <span className={styles.productAdded} role="status">
                        <CheckmarkCircleFilled aria-hidden="true" />
                        All items added to the sale
                    </span>
                ) : (
                    <>
                        <div className={styles.cartPlanTotals} role="status">
                            <span>{`${selected.length} of ${pending.length} selected`}</span>
                            <span className={styles.cartPlanTotal}>{format(selectedTotal)}</span>
                        </div>
                        {isTotalBudget && budget && (budgetLeft < -0.005 ? (
                            <span className={styles.cartPlanWarning}>
                                <WarningRegular className={styles.cartPlanWarningIcon} aria-hidden="true" />
                                <span>{`Over the ${format(budget.amount)} budget by ${format(-budgetLeft)}`}</span>
                            </span>
                        ) : (
                            <span className={styles.cartPlanMeta}>{`${format(budgetLeft)} left of the ${format(budget.amount)} budget`}</span>
                        ))}
                        {error && <span className={styles.cartPlanError} role="alert">{error}</span>}
                        <Button
                            className={styles.cartPlanAddAll}
                            appearance="primary"
                            icon={isAddingSelection ? <Spinner size="tiny" /> : <CartRegular />}
                            disabled={!props.onAddProducts || isBusy || selected.length === 0}
                            onClick={() => addProducts(selected, true)}
                        >
                            {isAddingSelection
                                ? "Adding\u2026"
                                : `Add ${selected.length} ${selected.length === 1 ? "item" : "items"} to sale`}
                        </Button>
                    </>
                )}
            </div>
        </div>
    );
};

const ProductPreview: React.FC<{
    preview: IAgentProductPreview;
    messageStartId?: string;
    onProductActivated?: (recordId: number) => void;
    onAddToSale?: (recordId: number) => Promise<void>;
    /** Called with the filter tags selected in the preview, if any. */
    onViewAll?: (preview: IAgentProductPreview, selection?: IAgentProductFilterSelection) => void;
    /** Called with part of the preview that just expanded in place, so it can be scrolled into view. */
    onContentExpanded?: (element: HTMLElement) => void;
    /** Finds which of the products have the selected tags other than prices. */
    onFilterProducts?: (request: IAgentProductFilterRequest) => Promise<ReadonlyArray<number>>;
}> = (props) => {
    const styles = useStyles();
    // Names each row's name and variant, so its buttons can point screen readers at them.
    const idPrefix: string = useId("side-chat-product-");
    const [addingIds, setAddingIds] = React.useState<ReadonlySet<number>>(new Set<number>());
    const [addedIds, setAddedIds] = React.useState<ReadonlySet<number>>(new Set<number>());
    // The product compared with the best match, or undefined while the comparison is closed.
    const [comparisonProductId, setComparisonProductId] = React.useState<number | undefined>();
    // Closing the comparison returns focus to the control that last opened it: Compare options, or a
    // row's compare toggle. Compare options is the fallback.
    const compareButtonRef = React.useRef<HTMLButtonElement>(null);
    const comparisonOpenerRef = React.useRef<HTMLElement | null>(null);
    const filtersRef = React.useRef<HTMLDivElement>(null);
    const isCartSuggestion: boolean = props.preview.kind === "cartSuggestions";
    // Recommendations narrow to the tags selected here, in POS. Cart suggestions have no tags.
    const filters: IProductFilters = useProductFilters(
        props.preview.products,
        isCartSuggestion ? undefined : props.preview.filterFacets,
        props.onFilterProducts);
    const matchingProducts: ReadonlyArray<IAgentProductCard> = filters.products;
    // A recommendation always names one product as the best match: the agent's pick, or else the
    // first. A cart suggestion names one only when the agent picked it, because the products are
    // alternatives the operator may add together rather than candidates competing for one sale.
    const pickedProductId: number | undefined = isCartSuggestion
        ? props.preview.bestMatchProductId
        : props.preview.bestMatchProductId ?? props.preview.products[0]?.recordId;
    // The summary names it whatever the tags leave, so it never moves the tags as they are tapped.
    const pickedProduct: IAgentProductCard | undefined = props.preview.products.filter(
        (product: IAgentProductCard) => product.recordId === pickedProductId)[0];
    // It is badged while the tags leave it. Without a pick from the agent, the first product they
    // leave is the best match instead.
    const isPickShown: boolean = matchingProducts.some(
        (product: IAgentProductCard) => product.recordId === pickedProductId);
    const bestMatchProductId: number | undefined = isPickShown
        ? pickedProductId
        : !isCartSuggestion && props.preview.bestMatchProductId === undefined
            ? matchingProducts[0]?.recordId
            : undefined;
    // The agent's reason is only about its pick.
    const bestMatchReason: string | undefined = bestMatchProductId === pickedProductId
        ? props.preview.bestMatchReason
        : undefined;
    const orderedProducts: ReadonlyArray<IAgentProductCard> = bestMatchProductId === undefined
        ? matchingProducts
        : [
            ...matchingProducts.filter(
                (product: IAgentProductCard) => product.recordId === bestMatchProductId),
            ...matchingProducts.filter(
                (product: IAgentProductCard) => product.recordId !== bestMatchProductId)
        ];
    const visibleProducts: ReadonlyArray<IAgentProductCard> = orderedProducts.slice(0, MAX_PREVIEW_PRODUCTS);
    const hiddenCount: number = Math.max(0, matchingProducts.length - visibleProducts.length);
    const bestMatchProduct: IAgentProductCard | undefined = orderedProducts.filter(
        (product: IAgentProductCard) => product.recordId === bestMatchProductId)[0];
    // The best match is compared with the other products on screen.
    const alternatives: ReadonlyArray<IAgentProductCard> = visibleProducts.filter(
        (product: IAgentProductCard) => product.recordId !== bestMatchProductId);
    const comparisonProduct: IAgentProductCard | undefined = alternatives.filter(
        (product: IAgentProductCard) => product.recordId === comparisonProductId)[0];
    const isComparing: boolean = !!bestMatchProduct && !!comparisonProduct;
    const comparisonId: string = `${idPrefix}-comparison`;

    // A product the tags take off screen leaves the comparison, rather than coming back with it when
    // the tags are cleared.
    React.useEffect(() => {
        if (comparisonProductId !== undefined && !comparisonProduct) {
            setComparisonProductId(undefined);
        }
    }, [comparisonProductId, comparisonProduct]);

    const addToSale = React.useCallback((product: IAgentProductCard): void => {
        const displayRecordId: number = product.recordId;
        const saleRecordId: number = product.selectedVariantId ?? displayRecordId;
        if (!props.onAddToSale || addingIds.has(displayRecordId) || addedIds.has(displayRecordId)) {
            return;
        }

        setAddingIds((current: ReadonlySet<number>) => new Set(current).add(displayRecordId));
        props.onAddToSale(saleRecordId)
            .then(() => {
                setAddingIds((current: ReadonlySet<number>) => {
                    const next = new Set(current);
                    next.delete(displayRecordId);
                    return next;
                });
                setAddedIds((current: ReadonlySet<number>) => new Set(current).add(displayRecordId));
            })
            .catch(() => {
                setAddingIds((current: ReadonlySet<number>) => {
                    const next = new Set(current);
                    next.delete(displayRecordId);
                    return next;
                });
            });
    }, [addingIds, addedIds, props]);

    // A reason the agent gave for the product itself wins. A recommendation shows its best-match
    // reason in the summary and the comparison instead, so only a cart suggestion falls back to it
    // on the row.
    const reasonsByProductId: Map<number, string> = new Map<number, string>();
    if (isCartSuggestion && bestMatchProductId !== undefined && props.preview.bestMatchReason) {
        reasonsByProductId.set(bestMatchProductId, props.preview.bestMatchReason);
    }
    (props.preview.productReasons ?? []).forEach((entry: IAgentProductReason) => {
        reasonsByProductId.set(entry.productId, entry.reason);
    });

    const inventoryByProductId: Map<number, IAgentProductInventory> = new Map<number, IAgentProductInventory>();
    (props.preview.inventory ?? []).forEach((entry: IAgentProductInventory) => {
        if (!inventoryByProductId.has(entry.productId)) {
            inventoryByProductId.set(entry.productId, entry);
        }
    });

    const canCompare: boolean = !isCartSuggestion && !!bestMatchProduct && alternatives.length > 0;
    // Every cart suggestion is already on screen unless the agent returned more than fit.
    const canViewAll: boolean = !isCartSuggestion || hiddenCount > 0;
    const summary: string | undefined = isCartSuggestion
        ? "Based on the current cart"
        : pickedProduct && props.preview.bestMatchReason
            ? `Best match: ${pickedProduct.name}. ${props.preview.bestMatchReason}`
            : undefined;
    const hasNoMatch: boolean = matchingProducts.length === 0 && props.preview.products.length > 0;
    const isFilterStatusShown: boolean = filters.isFiltering || !!filters.note || filters.hasSelection;

    // Clear goes away with the tags it clears, so focus moves to the first tag before it does.
    const clearFilters = (): void => {
        focusFirstTag(filtersRef.current);
        filters.clear();
    };

    const toggleComparison = (): void => {
        comparisonOpenerRef.current = compareButtonRef.current;
        setComparisonProductId(comparisonProductId === undefined ? alternatives[0]?.recordId : undefined);
    };

    // A row's compare toggle puts its product in the comparison's second column, opening the comparison
    // if needed. Pressed again, it closes the comparison.
    const toggleComparedProduct = (recordId: number, toggle: HTMLElement): void => {
        if (comparisonProductId === recordId) {
            setComparisonProductId(undefined);
            return;
        }

        comparisonOpenerRef.current = toggle;
        setComparisonProductId(recordId);
    };

    const closeComparison = React.useCallback((): void => {
        setComparisonProductId(undefined);
        // The close button is about to go away with the comparison, so focus goes back to where it opened.
        const opener: HTMLElement | null = comparisonOpenerRef.current;
        (opener && opener.isConnected ? opener : compareButtonRef.current)?.focus();
    }, []);

    return (
        <div
            role="group"
            className={styles.preview}
            aria-label={isCartSuggestion ? "Products suggested for this cart" : "Recommended product preview"}
            data-message-start={props.messageStartId}
            data-message-card=""
        >
            <div className={styles.previewHeader}>
                <span className={styles.previewHeaderIcon} aria-hidden="true">
                    <SparkleRegular />
                </span>
                <span className={styles.previewTitle}>
                    {props.preview.headline || (isCartSuggestion ? "Goes well with this cart" : "Recommended products")}
                </span>
                {canViewAll && (
                    <Button
                        className={styles.previewViewAll}
                        appearance="transparent"
                        size="small"
                        icon={<ChevronRightRegular />}
                        iconPosition="after"
                        disabled={!props.onViewAll}
                        onClick={() => props.onViewAll?.(
                            props.preview,
                            filters.hasSelection ? filters.selection : undefined)}
                    >
                        View all
                    </Button>
                )}
            </div>

            {summary && <p className={styles.previewSummary}>{summary}</p>}

            {filters.facets.length > 0 && (
                <>
                    <ProductFacetFilters
                        ref={filtersRef}
                        className={mergeClasses(styles.previewFilters, !summary && styles.previewFiltersUnderHeading)}
                        facets={filters.facets}
                        selection={filters.selection}
                        onToggle={filters.toggle}
                        size="small"
                        scrollRows
                    />

                    <div className={mergeClasses(styles.previewFilterStatus, isFilterStatusShown && styles.previewFilterStatusShown)}>
                        <span className={styles.previewFilterStatusText} role="status">
                            {filters.isFiltering ? (
                                <>
                                    <Spinner size="extra-tiny" aria-hidden="true" />
                                    <span>Filtering{"\u2026"}</span>
                                </>
                            ) : filters.note ? (
                                <span>{filters.note}</span>
                            ) : filters.hasSelection ? (
                                <span>
                                    {`${matchingProducts.length} of ${props.preview.products.length} `}
                                    {matchingProducts.length === 1 ? "matches" : "match"}
                                </span>
                            ) : null}
                        </span>
                        {filters.hasSelection && (
                            <Button
                                className={styles.previewFilterClear}
                                appearance="transparent"
                                size="small"
                                onClick={clearFilters}
                            >
                                Clear
                            </Button>
                        )}
                    </div>
                </>
            )}

            {hasNoMatch ? (
                <p className={styles.previewNoMatch}>No products match these filters.</p>
            ) : (
                <ul className={styles.productList}>
                    {visibleProducts.map((product: IAgentProductCard) => {
                        const isBestMatch: boolean = product.recordId === bestMatchProductId;
                        const isCompared: boolean = isComparing && product.recordId === comparisonProductId;
                        const isAdding: boolean = addingIds.has(product.recordId);
                        const reason: string | undefined = reasonsByProductId.get(product.recordId);
                        const variant: string = product.dimensionValues?.join(", ") ?? "";
                        const nameId: string = `${idPrefix}-${product.recordId}-name`;
                        const variantId: string = `${idPrefix}-${product.recordId}-variant`;
                        const image: React.ReactElement = (
                            <ProductThumbnail className={styles.productImage} imageUrl={product.imageUrl} placeholderSize={28} />
                        );

                        return (
                            <li key={product.recordId} className={styles.productRow}>
                                {props.onProductActivated ? (
                                    <button
                                        type="button"
                                        className={styles.productImageButton}
                                        aria-label={`Details for ${product.name}`}
                                        title="Details"
                                        onClick={() => props.onProductActivated?.(product.recordId)}
                                    >
                                        {image}
                                    </button>
                                ) : image}

                                <div className={styles.productInfo}>
                                    {isBestMatch && (
                                        <Badge
                                            className={styles.productBestMatch}
                                            appearance="filled"
                                            color="brand"
                                            size="small"
                                            icon={<SparkleFilled />}
                                        >
                                            Best match
                                        </Badge>
                                    )}
                                    <div className={styles.productHeading}>
                                        <span id={nameId} className={styles.productName} title={product.name}>{product.name}</span>
                                        {canCompare && !isBestMatch && (
                                            <ToggleButton
                                                className={styles.productCompare}
                                                appearance="subtle"
                                                size="small"
                                                checked={isCompared}
                                                icon={isCompared ? <ItemCompareFilled /> : <ItemCompareRegular />}
                                                aria-label={`Compare ${product.name} with the best match`}
                                                aria-controls={isCompared ? comparisonId : undefined}
                                                title="Compare with best match"
                                                onClick={(event: React.MouseEvent<HTMLButtonElement>) =>
                                                    toggleComparedProduct(product.recordId, event.currentTarget)}
                                            />
                                        )}
                                    </div>
                                    {product.priceText && <span className={styles.productPrice}>{product.priceText}</span>}
                                    {variant.length > 0 && <span id={variantId} className={styles.productVariant}>{variant}</span>}
                                    <ProductStock
                                        className={styles.productStock}
                                        variant="badges"
                                        inventory={inventoryByProductId.get(product.recordId)}
                                        currentStoreName={props.preview.currentStoreName}
                                    />
                                    {reason && (
                                        <span className={styles.productReason}>
                                            <SparkleFilled className={styles.productReasonIcon} aria-hidden="true" />
                                            <span className={styles.productReasonText}>{reason}</span>
                                        </span>
                                    )}

                                    <div className={styles.productActions}>
                                        {addedIds.has(product.recordId) ? (
                                            <span className={styles.productAdded} role="status">
                                                <CheckmarkCircleFilled aria-hidden="true" />
                                                Added
                                            </span>
                                        ) : (
                                            <Button
                                                className={styles.productAdd}
                                                appearance="primary"
                                                icon={isAdding ? <Spinner size="tiny" /> : undefined}
                                                disabled={!props.onAddToSale || isAdding}
                                                aria-describedby={variant.length > 0 ? `${nameId} ${variantId}` : nameId}
                                                onClick={() => addToSale(product)}
                                            >
                                                {isAdding ? "Adding\u2026" : "Add to sale"}
                                            </Button>
                                        )}
                                    </div>
                                </div>
                            </li>
                        );
                    })}
                </ul>
            )}

            {(hiddenCount > 0 || canCompare) && (
                <div className={styles.previewFooter}>
                    {hiddenCount > 0 && (
                        <span className={styles.previewMore}>
                            {`Showing ${visibleProducts.length} of ${matchingProducts.length}`}
                        </span>
                    )}
                    {canCompare && (
                        <Button
                            ref={compareButtonRef}
                            className={styles.compareOptions}
                            appearance="secondary"
                            icon={isComparing ? <ChevronUpRegular /> : <ChevronDownRegular />}
                            iconPosition="after"
                            aria-expanded={isComparing}
                            aria-controls={isComparing ? comparisonId : undefined}
                            onClick={toggleComparison}
                        >
                            Compare options
                        </Button>
                    )}
                </div>
            )}

            {isComparing && bestMatchProduct && comparisonProduct && (
                <InlineProductComparison
                    id={comparisonId}
                    bestMatch={bestMatchProduct}
                    comparedProduct={comparisonProduct}
                    bestMatchReason={bestMatchReason}
                    onShown={props.onContentExpanded}
                    onClose={closeComparison}
                />
            )}
        </div>
    );
};

/**
 * The docked side panel. Owns its expanded/collapsed state and the conversation.
 * @param props The panel configuration.
 * @returns The rendered panel.
 */
export const SideChatPanel: React.FC<SideChatPanelProps> = (props) => {
    const styles = useStyles();

    const clientRef = React.useRef<ISideChatClient>(props.client);
    React.useEffect(() => {
        clientRef.current = props.client;
    }, [props.client]);

    // Kept in a ref so `send` does not need to be rebuilt when the accessor changes.
    const getViewContextRef = React.useRef<(() => string | null) | undefined>(props.getViewContext);
    React.useEffect(() => {
        getViewContextRef.current = props.getViewContext;
    }, [props.getViewContext]);

    const executeActionsRef = React.useRef<
        ((
            actions: ReadonlyArray<IAgentPosAction>,
            options?: IAgentActionExecutionOptions
        ) => Promise<ReadonlyArray<IActionReceipt>>) | undefined
    >(props.executeActions);
    React.useEffect(() => {
        executeActionsRef.current = props.executeActions;
    }, [props.executeActions]);

    const [isExpanded, setIsExpanded] = React.useState<boolean>(getIsOpen());
    const [messages, setMessages] = React.useState<SideChatMessage[]>([]);
    const [receiptsByMessageId, setReceiptsByMessageId] =
        React.useState<{ [messageId: string]: ReadonlyArray<IActionReceipt> }>({});
    const [draft, setDraft] = React.useState<string>("");
    const [isProcessing, setIsProcessing] = React.useState<boolean>(false);
    const [isSuggesting, setIsSuggesting] = React.useState<boolean>(false);
    // When the first message of the conversation was added, for the day it is headed with.
    const [conversationStartedAt, setConversationStartedAt] = React.useState<Date | null>(null);
    const [showAllSuggestions, setShowAllSuggestions] = React.useState<boolean>(false);
    // Before the first message the panel shows its name, a larger message box and starter prompts.
    const isEmpty: boolean = messages.length === 0;

    // The POS header icon owns opening and closing, so the open state lives outside React.
    React.useEffect(() => {
        return subscribe(setIsExpanded);
    }, []);

    const headerOffset: number = usePosHeaderOffset(isExpanded);

    const isMountedRef = React.useRef<boolean>(true);
    // The conversation as of the last change, updated as each message is added rather than after the
    // next render, because an automatic cart check can add a message while a reply is being added.
    const messagesRef = React.useRef<SideChatMessage[]>([]);
    const inputRef = React.useRef<HTMLTextAreaElement>(null);
    const scrollRef = React.useRef<HTMLDivElement>(null);
    const composerRef = React.useRef<HTMLDivElement>(null);
    const attachButtonRef = React.useRef<IAttachButtonHandle>(null);
    // Counts new chats, so an automatic cart check that answers after one is dropped.
    const conversationEpochRef = React.useRef<number>(0);
    const suggestionListId: string = useId("side-chat-suggestions-");

    // Read by callbacks that must not be rebuilt as they change.
    const isProcessingRef = React.useRef<boolean>(false);
    const isSuggestionRunningRef = React.useRef<boolean>(false);
    // Suggestions that arrived while the operator was waiting for a reply, shown after that reply.
    const heldSuggestionRef = React.useRef<IReadyCartSuggestion | null>(null);
    // Set when the panel opens itself to show suggestions, so it does not take focus from POS.
    const suppressFocusOnOpenRef = React.useRef<boolean>(false);
    // The failure POS reported last, while it is recent, and the newest one the associate already asked
    // about or dismissed, so its help offer shows once.
    const [posError, setPosError] = React.useState<IVersionedPosError | null>(() => getPosError());
    const [handledPosErrorVersion, setHandledPosErrorVersion] = React.useState<number>(0);
    // Lets a reply that finishes pick up a help request that waited for it.
    const pumpPosErrorHelpRef = React.useRef<() => void>(() => undefined);

    const appendMessage = React.useCallback((message: SideChatMessage): SideChatMessage[] => {
        if (messagesRef.current.length === 0) {
            setConversationStartedAt(new Date());
        }

        const next: SideChatMessage[] = [...messagesRef.current, message];
        messagesRef.current = next;
        setMessages(next);
        return next;
    }, []);

    React.useEffect(() => {
        return () => {
            isMountedRef.current = false;
        };
    }, []);

    // Keep the newest message in view, including when the panel opens on a conversation that grew
    // while it was closed. When a reply is too tall for that to show one of its cards whole, such as a
    // grid of products, it shows from its beginning instead, so the operator sees the headline and
    // first products rather than the end of the list.
    React.useEffect(() => {
        const scroller = scrollRef.current;
        if (!scroller) {
            return;
        }

        const bottom: number = scroller.scrollHeight - scroller.clientHeight;
        let scrollTop: number = bottom;
        const newest: SideChatMessage | undefined = messages[messages.length - 1];
        const starts: NodeListOf<HTMLElement> = scroller.querySelectorAll<HTMLElement>("[data-message-start]");
        const start: HTMLElement | undefined = starts[starts.length - 1];
        if (newest?.role === "assistant" && !isProcessing && !isSuggesting && start?.dataset.messageStart === newest.id) {
            // How far down the conversation an element starts.
            const offsetOf = (element: Element): number =>
                element.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop;
            const cutsACard: boolean = Array.from(scroller.children).some((child: Element) =>
                child.hasAttribute("data-message-card")
                && (child === start || (start.compareDocumentPosition(child) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0)
                && offsetOf(child) < bottom - 1);
            if (cutsACard) {
                scrollTop = offsetOf(start) - CONVERSATION_PADDING_PX;
            }
        }

        scroller.scrollTop = scrollTop;
    }, [messages, receiptsByMessageId, isProcessing, isSuggesting, isExpanded]);

    // Brings something that grew in place, such as an inline comparison, fully into view, or its top
    // when it is taller than the conversation. Only the conversation scrolls, never the POS page,
    // which scrollIntoView could also move.
    const revealInConversation = React.useCallback((element: HTMLElement): void => {
        const scroller: HTMLDivElement | null = scrollRef.current;
        if (!scroller) {
            return;
        }

        const visible: DOMRect = scroller.getBoundingClientRect();
        const target: DOMRect = element.getBoundingClientRect();
        const hiddenAbove: number = visible.top + CONVERSATION_PADDING_PX - target.top;
        const hiddenBelow: number = target.bottom - (visible.bottom - CONVERSATION_PADDING_PX);
        if (hiddenAbove > 0) {
            scroller.scrollTop -= hiddenAbove;
        } else if (hiddenBelow > 0) {
            scroller.scrollTop += Math.min(hiddenBelow, -hiddenAbove);
        }
    }, []);

    // Opening the panel is a deliberate act, so move focus to the composer. Closing it hands focus
    // back to POS rather than leaving it on a element that is about to be unmounted. When the panel
    // opens itself to show cart suggestions, the operator is busy in POS, so focus stays there.
    React.useEffect(() => {
        if (!isExpanded) {
            return;
        }

        if (suppressFocusOnOpenRef.current) {
            suppressFocusOnOpenRef.current = false;
            return;
        }

        if (inputRef.current) {
            inputRef.current.focus();
        }
    }, [isExpanded]);

    // The message box grows with what is typed or spoken until its maximum height, then scrolls.
    // Measured before paint, so the box never shows a scroll bar for text that is about to fit, and
    // again when the conversation starts or is cleared, since the box is taller in an empty panel.
    React.useLayoutEffect(() => {
        const input: HTMLTextAreaElement | null = inputRef.current;
        if (!input) {
            return;
        }

        input.style.height = "auto";
        input.style.height = `${input.scrollHeight}px`;
    }, [draft, isExpanded, isEmpty]);

    // After the associate speaks, focus goes back to the message box so Enter sends what they said, but
    // only from the composer itself: focus they have since moved into POS stays where they put it.
    const focusComposerAfterSpeech = React.useCallback((): void => {
        const input: HTMLTextAreaElement | null = inputRef.current;
        const composer: HTMLDivElement | null = composerRef.current;
        const focused: Element | null = document.activeElement;
        if (!input || !composer || (focused && focused !== document.body && !composer.contains(focused))) {
            return;
        }

        input.focus();
        input.setSelectionRange(input.value.length, input.value.length);
    }, []);

    // Tapping the mic to stop sends what the associate said. `send` stops the mic itself, so it is declared
    // after it, and the mic reaches it through this ref.
    const sendRef = React.useRef<(text: string) => void>(() => undefined);
    const voiceInput: IVoiceInput = useVoiceInput({
        onText: setDraft,
        onHeard: focusComposerAfterSpeech,
        onSend: (text: string) => sendRef.current(text)
    });
    const cancelVoiceInput: () => void = voiceInput.cancel;

    // Files go with the next message only when the backend can send them on.
    const acceptsAttachments: boolean = props.client.acceptsAttachments === true;
    const attachments: IComposerAttachments = useComposerAttachments();
    const { add: addAttachments, peek: peekAttachments, take: takeAttachments } = attachments;
    const [isFileDragOver, setIsFileDragOver] = React.useState<boolean>(false);
    // Drag events fire for every element the pointer crosses, so the overlay tracks how deep it is.
    const dragDepthRef = React.useRef<number>(0);

    // A closed panel does not listen, and a drag over it can't be finished.
    React.useEffect(() => {
        if (!isExpanded) {
            cancelVoiceInput();
            dragDepthRef.current = 0;
            setIsFileDragOver(false);
        }
    }, [isExpanded, cancelVoiceInput]);

    const onPanelDragEnter = React.useCallback((event: React.DragEvent<HTMLDivElement>): void => {
        if (!isDraggingFiles(event.dataTransfer)) {
            return;
        }

        event.preventDefault();
        dragDepthRef.current += 1;
        setIsFileDragOver(true);
    }, []);

    const onPanelDragOver = React.useCallback((event: React.DragEvent<HTMLDivElement>): void => {
        if (!isDraggingFiles(event.dataTransfer)) {
            return;
        }

        // Without this the drop isn't allowed.
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
    }, []);

    const onPanelDragLeave = React.useCallback((event: React.DragEvent<HTMLDivElement>): void => {
        if (!isDraggingFiles(event.dataTransfer)) {
            return;
        }

        dragDepthRef.current = Math.max(0, dragDepthRef.current - 1);
        if (dragDepthRef.current === 0) {
            setIsFileDragOver(false);
        }
    }, []);

    const onPanelDrop = React.useCallback((event: React.DragEvent<HTMLDivElement>): void => {
        if (!isDraggingFiles(event.dataTransfer)) {
            return;
        }

        // Otherwise the WebView opens the file in place of POS.
        event.preventDefault();
        dragDepthRef.current = 0;
        setIsFileDragOver(false);
        addAttachments(readDroppedFiles(event.dataTransfer));
    }, [addAttachments]);

    // Adds suggestions to the conversation and, when the panel is closed, opens it to show them.
    const showCartSuggestion = React.useCallback((suggestion: IReadyCartSuggestion): void => {
        const text: string = suggestion.reply.displayMessage && suggestion.reply.displayMessage.trim().length > 0
            ? suggestion.reply.displayMessage
            : "These go well with the items in the cart.";
        const message: SideChatMessage =
            createMessage("assistant", text, suggestion.reply.toolActivities, "cartSuggestion");
        appendMessage(message);
        setReceiptsByMessageId((current) => ({
            ...current,
            [message.id]: suggestion.receipts
        }));

        // Only a reply the operator can see becomes part of the agent conversation.
        if (suggestion.reply.acceptIntoConversation) {
            suggestion.reply.acceptIntoConversation();
        }

        if (!getIsOpen()) {
            suppressFocusOnOpenRef.current = true;
            setIsOpen(true);
        }
    }, [appendMessage]);

    // Says why a check came to nothing, so a spinner that disappears is not the only sign of it. The
    // operator did not ask for the check, so the note does not open the panel, and the same note is not
    // repeated for every item added while the problem lasts.
    const noteCartSuggestionFailure = React.useCallback((detail: string): void => {
        const text: string = `Couldn't get suggestions for this cart. ${detail}`;
        const latest: SideChatMessage | undefined = messagesRef.current[messagesRef.current.length - 1];
        if (latest && latest.role === "assistant" && latest.text === text) {
            return;
        }

        appendMessage(createMessage("assistant", text));
    }, [appendMessage]);

    // Asks about the newest cart POS published, one check at a time, and never while the operator is
    // waiting for a reply: both would continue the same agent conversation. A check that finds nothing
    // worth showing, or answers for a cart that has changed since, stays silent; one that fails says so.
    const pumpCartSuggestions = React.useCallback((): void => {
        if (!isMountedRef.current
            || isSuggestionRunningRef.current
            || isProcessingRef.current
            || heldSuggestionRef.current) {
            return;
        }

        const next: IVersionedCartSuggestionRequest | null = takeCartSuggestionRequest();
        const client: ISideChatClient = clientRef.current;
        if (!next || !client.suggestForCartAsync) {
            return;
        }

        // A newer cart replaces the check, and so does a new chat.
        const epoch: number = conversationEpochRef.current;
        const isCurrent = (): boolean =>
            isMountedRef.current
            && next.version === getLatestCartSuggestionVersion()
            && epoch === conversationEpochRef.current;
        const excludedProductIds: number[] = getProductIdsInCart(next.request);

        isSuggestionRunningRef.current = true;
        setIsSuggesting(true);
        const viewContext: string | null = getViewContextRef.current ? getViewContextRef.current() : null;

        client.suggestForCartAsync(next.request, viewContext)
            .then((reply: ICartSuggestionReply) => {
                const actions: IAgentPosAction[] = reply?.posActions ?? [];
                if (!isCurrent() || actions.length === 0 || !executeActionsRef.current) {
                    return undefined;
                }

                return executeActionsRef.current(actions, { automatic: true, excludedProductIds })
                    .then((receipts: ReadonlyArray<IActionReceipt>) => {
                        const shown: ReadonlyArray<IActionReceipt> = receipts.filter((receipt: IActionReceipt) =>
                            receipt.outcome === "ran"
                            && !!receipt.productPreview
                            && receipt.productPreview.products.length > 0);
                        if (!isCurrent() || shown.length === 0) {
                            return;
                        }

                        const suggestion: IReadyCartSuggestion = { version: next.version, reply, receipts: shown };
                        if (isProcessingRef.current) {
                            heldSuggestionRef.current = suggestion;
                        } else {
                            showCartSuggestion(suggestion);
                        }
                    });
            })
            .catch((error: unknown) => {
                // A newer cart replaces this check, and an operator waiting for their own reply is not
                // interrupted with it.
                if (!isCurrent() || isProcessingRef.current) {
                    return;
                }

                const detail: string = error instanceof Error && error.message
                    ? error.message
                    : "Unexpected error.";
                noteCartSuggestionFailure(detail);
            })
            .then(() => {
                isSuggestionRunningRef.current = false;
                if (isMountedRef.current) {
                    setIsSuggesting(false);
                    pumpCartSuggestions();
                }
            });
    }, [showCartSuggestion, noteCartSuggestionFailure]);

    React.useEffect(() => {
        const unsubscribe: () => void = subscribeToCartSuggestionRequests(pumpCartSuggestions);

        // POS may have asked before the panel finished mounting.
        pumpCartSuggestions();
        return unsubscribe;
    }, [pumpCartSuggestions]);

    const send = React.useCallback((text: string): void => {
        const trimmed = text.trim();
        if (isProcessingRef.current) {
            return;
        }

        // A file still being prepared would be left behind, and a message needs words or files.
        const pending: { count: number; isPreparing: boolean } = peekAttachments();
        if (pending.isPreparing || (trimmed.length === 0 && pending.count === 0)) {
            return;
        }

        // Read the view at send time so the message carries wherever the operator actually is.
        const viewContext: string | null = getViewContextRef.current ? getViewContextRef.current() : null;

        // Words the mic is still recognising would otherwise refill the box once it is cleared.
        cancelVoiceInput();
        const taken: ITakenAttachments = takeAttachments();
        const outgoing: SideChatMessage[] =
            appendMessage(createMessage("user", trimmed, undefined, undefined, taken.previews));
        setDraft("");
        isProcessingRef.current = true;
        setIsProcessing(true);

        (taken.attachments.length > 0
            ? clientRef.current.sendAsync(trimmed, outgoing, viewContext, taken.attachments)
            : clientRef.current.sendAsync(trimmed, outgoing, viewContext))
            .then((reply: ISideChatReply) => {
                if (!isMountedRef.current) {
                    return undefined;
                }

                const replyText = reply?.displayMessage && reply.displayMessage.trim().length > 0
                    ? reply.displayMessage
                    : "(No response was returned.)";
                const assistantMessage: SideChatMessage =
                    createMessage("assistant", replyText, reply.toolActivities);
                appendMessage(assistantMessage);

                const actions = reply?.posActions ?? [];
                if (actions.length === 0 || !executeActionsRef.current) {
                    return undefined;
                }

                // The agent only chooses; POS decides whether it can honour the choice. Receipts are
                // rendered either way so an unsupported or failed action is visible rather than silent.
                return executeActionsRef.current(actions).then((results: ReadonlyArray<IActionReceipt>) => {
                    if (isMountedRef.current && results.length > 0) {
                        setReceiptsByMessageId((current) => ({
                            ...current,
                            [assistantMessage.id]: results
                        }));
                    }

                    return undefined;
                });
            })
            .catch((error: unknown) => {
                if (isMountedRef.current) {
                    const detail = error instanceof Error ? error.message : "Unexpected error.";
                    appendMessage(
                        createMessage("assistant", `Sorry, something went wrong contacting the assistant: ${detail}`));
                }
            })
            .then(() => {
                isProcessingRef.current = false;
                if (!isMountedRef.current) {
                    return;
                }

                setIsProcessing(false);

                // Suggestions that arrived during the turn follow its reply, unless the cart has
                // changed since, in which case a newer check replaces them.
                const held: IReadyCartSuggestion | null = heldSuggestionRef.current;
                heldSuggestionRef.current = null;
                if (held && held.version === getLatestCartSuggestionVersion()) {
                    showCartSuggestion(held);
                }

                pumpCartSuggestions();
                pumpPosErrorHelpRef.current();
            });
    }, [appendMessage, cancelVoiceInput, peekAttachments, pumpCartSuggestions, showCartSuggestion, takeAttachments]);

    React.useEffect(() => {
        sendRef.current = send;
    }, [send]);

    // Asks the agent about a failure POS reported. The request carries the failure itself, so the words
    // only need to say what the associate wants.
    const askAboutPosError = React.useCallback((error: IVersionedPosError): void => {
        if (isProcessingRef.current) {
            return;
        }

        setHandledPosErrorVersion(error.version);
        send(describePosErrorHelpRequest(error.error));
    }, [send]);

    // Shows the newest failure, and asks about it when a POS view asked for help with it. A help request
    // waits for a reply the associate is already waiting for.
    const pumpPosErrorHelp = React.useCallback((): void => {
        if (!isMountedRef.current) {
            return;
        }

        setPosError(getPosError());
        if (isProcessingRef.current) {
            return;
        }

        const requested: IVersionedPosError | null = takePosErrorHelpRequest();
        if (requested) {
            askAboutPosError(requested);
        }
    }, [askAboutPosError]);

    React.useEffect(() => {
        pumpPosErrorHelpRef.current = pumpPosErrorHelp;
        const unsubscribe: () => void = subscribeToPosError(pumpPosErrorHelp);

        // POS may have reported the failure before the panel finished mounting.
        pumpPosErrorHelp();
        return unsubscribe;
    }, [pumpPosErrorHelp]);

    // The help offer goes away once the failure is too old to matter.
    React.useEffect(() => {
        if (!posError) {
            return undefined;
        }

        const remaining: number = posError.reportedAt + POS_ERROR_LIFETIME_MS - Date.now();
        const timer: number = window.setTimeout(() => {
            if (isMountedRef.current) {
                setPosError(getPosError());
            }
        }, Math.max(0, remaining) + 100);
        return () => window.clearTimeout(timer);
    }, [posError]);

    // A cart plan adds its products in one operation when POS supports that, and one at a time otherwise.
    const onAddProductsToSale = props.onAddProductsToSale;
    const onPreviewAddToSale = props.onPreviewAddToSale;
    const addPlanProducts = React.useMemo(() => {
        if (onAddProductsToSale) {
            return onAddProductsToSale;
        }

        if (!onPreviewAddToSale) {
            return undefined;
        }

        return (recordIds: ReadonlyArray<number>): Promise<void> => recordIds.reduce(
            (previous: Promise<void>, recordId: number) => previous.then(() => onPreviewAddToSale(recordId)),
            Promise.resolve());
    }, [onAddProductsToSale, onPreviewAddToSale]);

    const offeredPosError: IVersionedPosError | null =
        posError && posError.version !== handledPosErrorVersion ? posError : null;

    const onComposerKeyDown = React.useCallback(
        (event: React.KeyboardEvent<HTMLTextAreaElement>): void => {
            if (event.key === "Enter" && !event.shiftKey) {
                event.preventDefault();
                send(draft);
            }
        },
        [draft, send]
    );

    // A menu hands focus back to its button as it closes, so the message box takes it just after.
    const focusInputSoon = React.useCallback((): void => {
        window.setTimeout(() => {
            if (isMountedRef.current && inputRef.current) {
                inputRef.current.focus();
            }
        }, 0);
    }, []);

    // Clears the conversation and tells the client to start a new one. Not while a reply is on its way,
    // which would land in the new chat. Whatever is in the message box stays for the new chat.
    const startNewChat = React.useCallback((): void => {
        if (isProcessingRef.current) {
            return;
        }

        conversationEpochRef.current += 1;
        cancelVoiceInput();
        messagesRef.current = [];
        setMessages([]);
        setReceiptsByMessageId({});
        heldSuggestionRef.current = null;
        setConversationStartedAt(null);
        setIsSuggesting(false);
        setShowAllSuggestions(false);
        if (clientRef.current.startNewConversation) {
            clientRef.current.startNewConversation();
        }

        focusInputSoon();
    }, [cancelVoiceInput, focusInputSoon]);

    // A plain starter prompt is sent at once. One that needs a file waits in the message box while the
    // file picker opens, which has to happen in the same tap. Either way the prompt's button goes away,
    // so the message box takes focus.
    const runSuggestion = React.useCallback((suggestion: SideChatSuggestion): void => {
        focusInputSoon();
        if (getSuggestionFileWord(suggestion) === null) {
            send(getSuggestionText(suggestion));
            return;
        }

        cancelVoiceInput();
        setDraft(getSuggestionText(suggestion));
        if (attachButtonRef.current) {
            attachButtonRef.current.openPicker();
        }
    }, [cancelVoiceInput, focusInputSoon, send]);

    const title = props.title ?? "Copilot";
    // A prompt that needs a file is left out when the client can't send one.
    const suggestions: ReadonlyArray<SideChatSuggestion> = (props.suggestions ?? DEFAULT_SIDE_CHAT_SUGGESTIONS)
        .filter((suggestion: SideChatSuggestion) => acceptsAttachments || getSuggestionFileWord(suggestion) === null);
    const shownSuggestions: ReadonlyArray<SideChatSuggestion> = showAllSuggestions
        ? suggestions
        : suggestions.slice(0, SUGGESTIONS_SHOWN);
    // Send appears once there is something to send.
    const hasDraftContent: boolean = draft.trim().length > 0 || attachments.items.length > 0;
    // Stopping the mic sends what was said, except while Send could not, when the words stay in the box.
    const voiceSendsOnStop: boolean = !isProcessing && !attachments.isPreparing;
    let placeholder: string = isEmpty ? EMPTY_PLACEHOLDER : `Message ${title}`;
    if (attachments.items.length > 0) {
        placeholder = "Ask about the attached files, or just send";
    }

    // Nothing is rendered while closed, so the panel adds no tab stops and no screen reader output
    // to the views it sits over. The POS header icon is the only way in.
    if (!isExpanded) {
        return null;
    }

    return (
        <IdPrefixProvider value={FLUENT_ID_PREFIX}>
            <FluentProvider theme={webLightTheme} className={styles.root} style={{ top: `${headerOffset}px` }}>
                <div
                    className={styles.panel}
                    role="complementary"
                    aria-label={title}
                    onDragEnter={acceptsAttachments ? onPanelDragEnter : undefined}
                    onDragOver={acceptsAttachments ? onPanelDragOver : undefined}
                    onDragLeave={acceptsAttachments ? onPanelDragLeave : undefined}
                    onDrop={acceptsAttachments ? onPanelDrop : undefined}>
                    <div className={styles.toolbar}>
                        {suggestions.length > 0 && (
                            // Inline, because a menu portalled to the body would open under the panel.
                            <Menu inline positioning="below-start">
                                <MenuTrigger disableButtonEnhancement>
                                    <Button
                                        appearance="subtle"
                                        icon={<TextAlignLeftRegular />}
                                        aria-label="Suggested tasks"
                                        title="Suggested tasks"
                                        disabled={isProcessing}
                                    />
                                </MenuTrigger>
                                <MenuPopover className={styles.menuPopover}>
                                    <MenuList>
                                        {suggestions.map((suggestion: SideChatSuggestion) => (
                                            <MenuItem
                                                key={getSuggestionText(suggestion)}
                                                onClick={() => runSuggestion(suggestion)}>
                                                {getSuggestionText(suggestion)}
                                            </MenuItem>
                                        ))}
                                    </MenuList>
                                </MenuPopover>
                            </Menu>
                        )}
                        <span className={styles.signInBadge} role="img" aria-label={SIGN_IN_NOTE} title={SIGN_IN_NOTE}>
                            <ShieldTaskRegular />
                        </span>
                        <span className={styles.toolbarSpacer} />
                        <Button
                            appearance="primary"
                            icon={<ComposeRegular />}
                            aria-label="New chat"
                            title="New chat"
                            disabled={isProcessing}
                            onClick={startNewChat}
                        />
                        <Menu inline positioning="below-end">
                            <MenuTrigger disableButtonEnhancement>
                                <Button
                                    appearance="subtle"
                                    icon={<MoreHorizontalRegular />}
                                    aria-label="More options"
                                    title="More options"
                                />
                            </MenuTrigger>
                            <MenuPopover className={styles.menuPopover}>
                                <MenuList>
                                    <MenuItem icon={<ComposeRegular />} disabled={isProcessing} onClick={startNewChat}>
                                        New chat
                                    </MenuItem>
                                    <MenuItem icon={<DismissRegular />} onClick={() => setIsOpen(false)}>
                                        {`Close ${title}`}
                                    </MenuItem>
                                </MenuList>
                            </MenuPopover>
                        </Menu>
                    </div>

                    {isEmpty && (
                        <div className={styles.brand}>
                            <CommerceLogo size={48} />
                            <span className={styles.brandName}>{BRAND_NAME}</span>
                        </div>
                    )}

                    {/* Rendered in the same place before and after the first message, like the composer
                        below it, so neither is rebuilt and the message box keeps its focus and text. */}
                    <div
                        className={mergeClasses(styles.messages, isEmpty && styles.messagesEmpty)}
                        ref={scrollRef}
                        role="log"
                        aria-live="polite"
                        aria-label="Conversation">
                        {!isEmpty && conversationStartedAt && (
                            <div className={styles.dayDivider}>{formatConversationDay(conversationStartedAt)}</div>
                        )}

                        {messages.map((message) => {
                            const messageReceipts: ReadonlyArray<IActionReceipt> =
                                receiptsByMessageId[message.id] ?? [];
                            const firstCardReceiptIndex: number = messageReceipts.findIndex(hasRecommendationCards);
                            const hideAssistantText: boolean =
                                message.role === "assistant" && firstCardReceiptIndex >= 0;

                            return (
                                <React.Fragment key={message.id}>
                                    {message.origin === "cartSuggestion" && (
                                        <div className={styles.suggestionCaption} data-message-start={message.id}>
                                            <CartRegular aria-hidden="true" />
                                            <span>Suggested for the current cart</span>
                                        </div>
                                    )}

                                    {!hideAssistantText && (
                                        <div
                                            className={message.role === "user"
                                                ? styles.bubbleUser
                                                : styles.bubbleAssistant}
                                            data-message-start={message.origin === "cartSuggestion"
                                                ? undefined
                                                : message.id}>
                                            {message.attachments && message.attachments.length > 0 && (
                                                <MessageAttachments
                                                    attachments={message.attachments}
                                                    hasText={message.text.length > 0}
                                                />
                                            )}
                                            {message.role === "assistant"
                                                ? <KnowledgeReplyText text={message.text} />
                                                : message.text}
                                        </div>
                                    )}

                                    {message.role === "assistant" && !hideAssistantText && (
                                        <KnowledgeReplyFooter
                                            text={message.text}
                                            toolActivities={message.toolActivities}
                                        />
                                    )}

                                    {messageReceipts.map((receipt, index) => (
                                        <React.Fragment key={`${message.id}-${receipt.action}-${index}`}>
                                            {/* Suggested products and cart plans speak for themselves; a status line would only repeat them. */}
                                            {!hasRecommendationCards(receipt)
                                                && !(receipt.outcome === "ran" && receipt.cartPlan) && (
                                                <div
                                                    className={mergeClasses(
                                                        styles.receipt,
                                                        receipt.outcome === "failed"
                                                            ? styles.receiptFailed
                                                            : undefined,
                                                        receipt.outcome === "unsupported"
                                                            ? styles.receiptUnsupported
                                                            : undefined
                                                    )}>
                                                    {receipt.outcome === "ran"
                                                        ? <CheckmarkCircleRegular />
                                                        : <InfoRegular />}
                                                    <span>{receipt.summary}</span>
                                                </div>
                                            )}

                                            {receipt.outcome === "ran" && receipt.productPreview && (
                                                <ProductPreview
                                                    preview={receipt.productPreview}
                                                    messageStartId={hideAssistantText
                                                        && message.origin !== "cartSuggestion"
                                                        && index === firstCardReceiptIndex
                                                        ? message.id
                                                        : undefined}
                                                    onProductActivated={props.onPreviewProductActivated}
                                                    onAddToSale={props.onPreviewAddToSale}
                                                    onViewAll={props.onPreviewViewAll}
                                                    onContentExpanded={revealInConversation}
                                                    onFilterProducts={props.onFilterProducts}
                                                />
                                            )}

                                            {receipt.outcome === "ran" && receipt.customerOrderReceipt && (
                                                <CustomerOrderReceipt receipt={receipt.customerOrderReceipt} />
                                            )}

                                            {receipt.outcome === "ran" && receipt.shippingReceipt && (
                                                <ShippingReceipt receipt={receipt.shippingReceipt} />
                                            )}

                                            {receipt.outcome === "ran" && receipt.cartPlan && (
                                                <CartPlanCard
                                                    plan={receipt.cartPlan}
                                                    onProductActivated={props.onPreviewProductActivated}
                                                    onAddProducts={addPlanProducts}
                                                    formatCurrency={props.formatCurrency}
                                                />
                                            )}
                                        </React.Fragment>
                                    ))}
                                </React.Fragment>
                            );
                        })}

                        {(isProcessing || isSuggesting) && (
                            <div className={styles.progress}>
                                <span className={styles.progressGlyph} aria-hidden="true">
                                    {PROGRESS_CELLS.map((cell: IProgressCell, index: number) => (
                                        <span
                                            key={index}
                                            className={styles.progressCell}
                                            style={{ opacity: cell.opacity, animationDelay: cell.delay }}
                                        />
                                    ))}
                                </span>
                                <span className={styles.progressLabel}>
                                    {isProcessing ? "Putting things together" : "Looking for items that go with this cart\u2026"}
                                </span>
                            </div>
                        )}
                    </div>

                    <div className={mergeClasses(styles.composer, isEmpty && styles.composerHero)} ref={composerRef}>
                        {offeredPosError && (
                            <div className={styles.posErrorHelp} role="group" aria-label="Error on the POS screen">
                                <ErrorCircleRegular className={styles.posErrorHelpIcon} aria-hidden="true" />
                                <span className={styles.posErrorHelpText}>
                                    <span className={styles.posErrorHelpTitle}>
                                        {`${offeredPosError.error.operation || "POS operation"} failed`}
                                    </span>
                                    <span className={styles.posErrorHelpCode}>
                                        {offeredPosError.error.retryCount > 0
                                            ? `${offeredPosError.error.code} \u00b7 retried`
                                            : offeredPosError.error.code}
                                    </span>
                                </span>
                                <Button
                                    className={styles.posErrorHelpButton}
                                    appearance="primary"
                                    size="small"
                                    disabled={isProcessing}
                                    onClick={() => askAboutPosError(offeredPosError)}
                                >
                                    Get help
                                </Button>
                                <Button
                                    className={styles.posErrorHelpButton}
                                    appearance="transparent"
                                    size="small"
                                    icon={<DismissRegular />}
                                    aria-label="Dismiss"
                                    title="Dismiss"
                                    onClick={() => {
                                        setHandledPosErrorVersion(offeredPosError.version);
                                        inputRef.current?.focus();
                                    }}
                                />
                            </div>
                        )}
                        <div className={mergeClasses(styles.composerBox, isEmpty && styles.composerBoxHero)}>
                            {acceptsAttachments && (
                                <>
                                    <AttachmentChips
                                        items={attachments.items}
                                        onRemove={(id: string) => {
                                            attachments.remove(id);
                                            // The chip and its button are gone; the message box is next.
                                            inputRef.current?.focus();
                                        }}
                                    />
                                    <AttachmentStatus error={attachments.error} notice={attachments.notice} />
                                </>
                            )}
                            <textarea
                                ref={inputRef}
                                className={mergeClasses(styles.input, isEmpty && styles.inputHero)}
                                value={draft}
                                rows={1}
                                placeholder={placeholder}
                                aria-label="Message"
                                onChange={(event: React.ChangeEvent<HTMLTextAreaElement>) => {
                                    // Typing takes over from the mic, whose late words would overwrite the edit.
                                    cancelVoiceInput();
                                    setDraft(event.target.value);
                                }}
                                onPaste={acceptsAttachments
                                    ? (event: React.ClipboardEvent<HTMLTextAreaElement>) => {
                                        const files: File[] = readPastedFiles(event.clipboardData);
                                        if (files.length > 0) {
                                            event.preventDefault();
                                            addAttachments(files);
                                        }
                                    }
                                    : undefined}
                                onKeyDown={onComposerKeyDown}
                            />
                            <div className={mergeClasses(
                                styles.composerToolbar,
                                acceptsAttachments && styles.composerToolbarWithAttach,
                                isEmpty && styles.composerToolbarHero,
                                isEmpty && acceptsAttachments && styles.composerToolbarHeroWithAttach)}>
                                {acceptsAttachments && (
                                    <AttachButton
                                        ref={attachButtonRef}
                                        isFull={attachments.isFull}
                                        onFiles={addAttachments}
                                        onFull={attachments.reportFull}
                                    />
                                )}
                                <VoiceInputStatus
                                    className={styles.composerStatus}
                                    state={voiceInput.state}
                                    error={voiceInput.error}
                                    sendsOnStop={voiceSendsOnStop}
                                />
                                {voiceInput.isSupported && (
                                    <VoiceInputButton
                                        state={voiceInput.state}
                                        sendsOnStop={voiceSendsOnStop}
                                        onClick={() => voiceInput.toggle(draft)}
                                    />
                                )}
                                {hasDraftContent && (
                                    <Button
                                        appearance="primary"
                                        shape="circular"
                                        icon={<SendFilled />}
                                        aria-label="Send"
                                        title="Send"
                                        disabled={isProcessing || attachments.isPreparing}
                                        onClick={() => send(draft)}
                                    />
                                )}
                            </div>
                        </div>
                    </div>

                    {isEmpty ? (
                        <div key="suggestions" className={styles.suggestions}>
                            <div id={suggestionListId} className={styles.suggestionList}>
                                {shownSuggestions.map((suggestion: SideChatSuggestion) => (
                                    <Button
                                        key={getSuggestionText(suggestion)}
                                        className={styles.suggestionPill}
                                        onClick={() => runSuggestion(suggestion)}>
                                        {renderSuggestionText(suggestion, styles.suggestionFile)}
                                    </Button>
                                ))}
                            </div>
                            {suggestions.length > SUGGESTIONS_SHOWN && (
                                <Button
                                    appearance="transparent"
                                    size="small"
                                    className={styles.seeMore}
                                    icon={showAllSuggestions ? <ChevronUpRegular /> : <ChevronDownRegular />}
                                    iconPosition="after"
                                    aria-expanded={showAllSuggestions}
                                    aria-controls={suggestionListId}
                                    onClick={() => setShowAllSuggestions((current: boolean) => !current)}>
                                    {showAllSuggestions ? "See less" : "See more"}
                                </Button>
                            )}
                        </div>
                    ) : (
                        <div key="footer" className={styles.footer}>{AI_DISCLAIMER}</div>
                    )}

                    {isFileDragOver && <AttachmentDropOverlay />}
                </div>
            </FluentProvider>
        </IdPrefixProvider>
    );
};

export default SideChatPanel;
