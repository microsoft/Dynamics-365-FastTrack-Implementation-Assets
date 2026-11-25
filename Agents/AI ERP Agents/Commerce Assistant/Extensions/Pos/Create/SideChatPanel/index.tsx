/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * index — the public surface of the bundled AMD module `Libraries/ContosoSideChat.js`.
 *
 * The POS trigger (SideChatPanelTrigger.ts, compiled to SystemJS by the POS build) imports this
 * module by its manifest alias `ContosoSideChat` and calls `mount` after logon and `unmount` on
 * logoff / lock. React, ReactDOM, Fluent UI and this app are all bundled into that single file, so
 * nothing extra needs to be available on the POS host.
 */

import * as React from "react";
import { createRoot, Root } from "react-dom/client";
import { SideChatPanel, SideChatPanelProps } from "./SideChatPanel";
import { ICartSuggestionRequest, ISideChatClient, SideChatSuggestion } from "./sideChatClient";
import {
    IActionReceipt,
    IAgentActionExecutionOptions,
    IAgentPosAction,
    IAgentPosErrorContext,
    IAgentProductCard,
    IAgentProductFilterRequest,
    IAgentProductFilterSelection,
    IAgentProductPreview
} from "./agentContracts";
import { getIsOpen, setIsOpen, subscribe, toggleIsOpen } from "./panelState";
import { clearCartSuggestionRequests, publishCartSuggestionRequest } from "./cartSuggestionState";
import {
    clearPosError as clearPosErrorState,
    getPosError as getPosErrorState,
    IVersionedPosError,
    publishPosError,
    requestPosErrorHelp as requestPosErrorHelpState
} from "./posErrorState";
import { IProductCompareProps, ProductCompareRoot } from "./productCompare/ProductCompareApp";
import { IProductResultsProps, ProductResultsRoot } from "./productResults/ProductResultsApp";
import { ensureTabsterCompatibility } from "./tabsterCompatibility";

export type {
    ICartSuggestionReply,
    ICartSuggestionRequest,
    ISideChatAttachment,
    ISideChatAttachmentPreview,
    ISideChatClient,
    ISideChatReply,
    ISideChatSuggestion,
    SideChatMessage,
    SideChatSuggestion
} from "./sideChatClient";
export { DEFAULT_SIDE_CHAT_SUGGESTIONS } from "./sideChatClient";
export type { IProductResultsProps } from "./productResults/ProductResultsApp";
export type { IProductCompareProps } from "./productCompare/ProductCompareApp";
export type {
    ActionOutcome,
    AgentCartBudgetScope,
    AgentPosConnectivity,
    AgentProductFacetKind,
    AgentProductPreviewKind,
    AgentShippingAddressType,
    IActionReceipt,
    IAgentActionDetails,
    IAgentActionExecutionOptions,
    IAgentAttachmentInfo,
    IAgentCartBudget,
    IAgentCartLine,
    IAgentCartPlan,
    IAgentCartPlanItem,
    IAgentCartPlanReceipt,
    IAgentCartPlanReceiptItem,
    IAgentCartSnapshot,
    IAgentCustomerOrderReceipt,
    IAgentCustomerOrderRequest,
    IAgentPosAction,
    IAgentPosErrorContext,
    IAgentProductCard,
    IAgentProductDimensionSelection,
    IAgentProductFacet,
    IAgentProductFacetValue,
    IAgentProductFilter,
    IAgentProductFilterRequest,
    IAgentProductFilterSelection,
    IAgentProductInventory,
    IAgentProductPreview,
    IAgentProductReason,
    IAgentProductSelection,
    IAgentRequestEnvelope,
    IAgentResponseEnvelope,
    IAgentSaleLine,
    IAgentSaleSnapshot,
    IAgentShippingItem,
    IAgentShippingReceipt,
    IAgentShippingReceiptLine,
    IAgentShippingRequest,
    IAgentStoreContext,
    IAgentStoreStock,
    IAgentToolActivity
} from "./agentContracts";

/** Options accepted when mounting the side panel. */
export interface SideChatMountOptions {
    /** The backend that answers prompts. */
    client: ISideChatClient;
    /** Optional header text override. */
    title?: string;
    /** Optional starter prompts override. */
    suggestions?: ReadonlyArray<SideChatSuggestion>;
    /**
     * Optional accessor for the POS view that is open right now. Called at send time so the
     * context follows the operator as they navigate with the panel open.
     */
    getViewContext?: () => string | null;
    /**
     * Optional executor for the actions the agent chose. Supplied by the POS extension, because only
     * POS code can reach the navigator and the runtime. The panel passes `{ automatic: true }` for the
     * actions of an automatic cart check.
     */
    executeActions?: (
        actions: ReadonlyArray<IAgentPosAction>,
        options?: IAgentActionExecutionOptions
    ) => Promise<ReadonlyArray<IActionReceipt>>;
    /** Opens one Commerce-resolved preview product in the POS details view. */
    onPreviewProductActivated?: (recordId: number) => void;
    /** Adds one Commerce-resolved product or variant to the current sale. */
    onPreviewAddToSale?: (recordId: number) => Promise<void>;
    /** Reopens the full curated-results view for an inline preview, with the tags selected in it. */
    onPreviewViewAll?: (preview: IAgentProductPreview, selection?: IAgentProductFilterSelection) => void;
    /**
     * Finds which of the products shown have the selected tags other than prices, as record
     * identifiers from the request. Supplied by the POS extension, because only POS code can reach
     * Commerce. Without it, only price tags filter.
     */
    onFilterProducts?: (request: IAgentProductFilterRequest) => Promise<ReadonlyArray<number>>;
    /**
     * Adds several Commerce-resolved products or variants to the current sale at once, from a cart
     * plan. Supplied by the POS extension, which adds them in one operation.
     */
    onAddProductsToSale?: (recordIds: ReadonlyArray<number>) => Promise<void>;
    /** Formats an amount in the store's currency, for the totals the panel works out itself. */
    formatCurrency?: (amount: number) => string;
}

// One React root per host element so mount/unmount are idempotent and leak-free.
const roots = new Map<Element, Root>();

/** Roots for the curated product results, kept separate so the two apps never evict each other. */
const productResultRoots = new Map<Element, Root>();

/** Roots for product comparisons. */
const productCompareRoots = new Map<Element, Root>();

/**
 * Render the side panel into the given host element. Calling this again for the same element
 * re-renders in place rather than creating a second root, so the trigger can be defensive.
 * @param element The host element appended to document.body by the POS trigger.
 * @param options The backend, and optional presentation overrides.
 */
export function mount(element: HTMLElement, options: SideChatMountOptions): void {
    if (!element) {
        return;
    }

    ensureTabsterCompatibility(element.ownerDocument.defaultView);

    let root = roots.get(element);
    if (!root) {
        root = createRoot(element);
        roots.set(element, root);
    }

    const props: SideChatPanelProps = {
        client: options.client,
        title: options.title,
        suggestions: options.suggestions,
        getViewContext: options.getViewContext,
        executeActions: options.executeActions,
        onPreviewProductActivated: options.onPreviewProductActivated,
        onPreviewAddToSale: options.onPreviewAddToSale,
        onPreviewViewAll: options.onPreviewViewAll,
        onFilterProducts: options.onFilterProducts,
        onAddProductsToSale: options.onAddProductsToSale,
        formatCurrency: options.formatCurrency
    };

    root.render(React.createElement(SideChatPanel, props));
}

/**
 * Opens or closes the panel. The POS header icon calls this.
 * @returns True when the panel is now open.
 */
export function toggle(): boolean {
    return toggleIsOpen();
}

/**
 * Sets the panel open or closed explicitly.
 * @param isOpen True to open the panel.
 */
export function setOpen(isOpen: boolean): void {
    setIsOpen(isOpen);
}

/**
 * Reads whether the panel is currently open.
 * @returns True when the panel is open.
 */
export function isOpen(): boolean {
    return getIsOpen();
}

/**
 * Tells the caller whenever the panel opens or closes, however that happened. The POS header icon
 * uses it to show when the panel is open.
 * @param listener Called with true when the panel opens and false when it closes.
 * @returns A function that stops the notifications.
 */
export function subscribeToOpenState(listener: (isOpen: boolean) => void): () => void {
    return subscribe(listener);
}

/**
 * Asks the panel to suggest products that go with the current cart, without the operator typing
 * anything. POS calls this after an item is added to the cart.
 *
 * Returns straight away. The panel asks the agent when it is free, shows any suggestions as product
 * cards in the conversation, and opens itself to show them without taking focus from POS. A newer
 * request replaces one that has not started yet, and a reply for a cart that has changed since is
 * dropped, so only suggestions for the latest cart are shown.
 * @param request The cart to ask about.
 */
export function requestCartSuggestions(request: ICartSuggestionRequest): void {
    if (!request || !request.cart) {
        return;
    }

    publishCartSuggestionRequest(request);
}

/**
 * Tells the panel about a POS operation that just failed on the associate's screen. Until it is
 * cleared, or for ten minutes, the panel offers help with it and sends it with the requests the
 * associate types, so the agent can look it up in the IT support guide.
 * @param error The failure, with diagnostic fields only: never payment data, tokens or contact details.
 */
export function reportPosError(error: IAgentPosErrorContext): void {
    if (!error || !error.code) {
        return;
    }

    publishPosError(error);
}

/** Forgets the failure reported last, for example when the operation succeeds on a retry. */
export function clearPosError(): void {
    clearPosErrorState();
}

/**
 * Reads the failure reported last, while it is recent.
 * @returns The failure, or null when there is none or it is too old to matter.
 */
export function getPosError(): IAgentPosErrorContext | null {
    const current: IVersionedPosError | null = getPosErrorState();
    return current === null ? null : { ...current.error };
}

/**
 * Opens the panel and asks the agent for help with the failure reported last, as if the associate
 * had chosen its help chip. The panel must already be mounted.
 * @returns True when there was a recent failure to ask about.
 */
export function requestPosErrorHelp(): boolean {
    if (!requestPosErrorHelpState()) {
        return false;
    }

    setIsOpen(true);
    return true;
}

/**
 * Tear down the panel rendered into the given element, discarding the conversation with it.
 * Safe to call more than once, and safe to call for an element that was never mounted.
 * @param element The host element previously passed to {@link mount}.
 */
export function unmount(element: HTMLElement): void {
    const root = roots.get(element);
    if (root) {
        root.unmount();
        roots.delete(element);
    }

    // Closed rather than left open, so a later mount (next sign-in) starts from the header icon.
    setIsOpen(false);

    // A cart check started for this operator must never reach the next one.
    clearCartSuggestionRequests();

    // Nor must a failure the last operator saw.
    clearPosErrorState();
}

/**
 * Renders the agent's curated product results into the given element.
 *
 * A separate root map from the side panel's: both can be on screen at once, and each host element
 * owns its own React root so mounting one never disturbs the other.
 * @param element The element the POS view controller renders into.
 * @param props The products POS resolved, plus the agent's recommendation.
 */
export function mountProductResults(element: HTMLElement, props: IProductResultsProps): void {
    if (!element) {
        return;
    }

    ensureTabsterCompatibility(element.ownerDocument.defaultView);

    let root = productResultRoots.get(element);
    if (!root) {
        root = createRoot(element);
        productResultRoots.set(element, root);
    }

    root.render(React.createElement(ProductResultsRoot, props));
}

/**
 * Tears down product results previously rendered into the given element.
 *
 * The POS view controller must call this from its `dispose`, or the React root outlives the view.
 * @param element The element previously passed to {@link mountProductResults}.
 */
export function unmountProductResults(element: HTMLElement): void {
    const root = productResultRoots.get(element);
    if (root) {
        root.unmount();
        productResultRoots.delete(element);
    }
}

/**
 * Renders a product comparison into the given element.
 * @param element The element the POS view controller renders into.
 * @param props The products and recommendation to compare.
 */
export function mountProductCompare(element: HTMLElement, props: IProductCompareProps): void {
    if (!element) {
        return;
    }

    ensureTabsterCompatibility(element.ownerDocument.defaultView);

    let root = productCompareRoots.get(element);
    if (!root) {
        root = createRoot(element);
        productCompareRoots.set(element, root);
    }

    root.render(React.createElement(ProductCompareRoot, props));
}

/**
 * Tears down a product comparison previously rendered into the given element.
 * @param element The element previously passed to mountProductCompare.
 */
export function unmountProductCompare(element: HTMLElement): void {
    const root = productCompareRoots.get(element);
    if (root) {
        root.unmount();
        productCompareRoots.delete(element);
    }
}
