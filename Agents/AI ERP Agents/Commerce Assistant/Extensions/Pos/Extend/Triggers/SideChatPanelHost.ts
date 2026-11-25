/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * SideChatPanelHost — owns the DOM container the docked chat side panel renders into.
 *
 * Why a container on document.body rather than a POS extension point:
 * POS has no supported extension point for a panel that persists across views. Custom controls are
 * declared per view in manifest.json, and app bar commands are per view too, so neither can produce
 * something that stays on screen while the operator navigates. Navigation replaces the children of
 * #contenthost (see the ContentHost control in the POS shell) and never touches document.body, so a
 * container appended to the body outlives every view change — out-of-box and custom alike.
 *
 * This is deliberately outside the supported extensibility surface. It is stable against normal
 * navigation, but it is not a contract the product guarantees, so re-verify it after POS upgrades.
 */

import * as SideChat from "ContosoSideChat";
import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities } from "PosApi/Entities";
import { CurrencyFormatter } from "PosApi/Consume/Formatters";
import CsuAgentSideChatClient from "../Agent/CsuAgentSideChatClient";
import { resetCartSuggestions, runWhileAgentActionsRun, scheduleCartSuggestions } from "../Agent/CartSuggestionScheduler";
import { executePosActionsAsync } from "../Agent/PosActionExecutor";
import { filterProductsAsync } from "../Agent/ProductFacetResolver";
import { addProductsToSaleAsync, addProductToSaleAsync } from "../Agent/ProductSaleHelper";
import { resetCustomerOrderLookup } from "../Agent/CustomerOrderLookup";

/** Id of the container appended to document.body. Also the idempotency key for install/remove. */
const HOST_ELEMENT_ID: string = "contosoSideChatHost";

/**
 * The backend for the signed-in operator. Kept for the whole session rather than created on every
 * mount, because it holds the agent conversation: reopening the panel from the header icon, and cart
 * suggestions shown while it was closed, continue the same conversation the panel shows.
 */
let sideChatClient: CsuAgentSideChatClient | null = null;

/**
 * POS sets `body { font-size: 4px }`, which every descendant inherits. The panel resets this on its
 * own React root as well, but setting it here too means nothing rendered into the container can pick
 * the 4px base up before Fluent's styles land.
 */
const HOST_BASE_FONT_SIZE: string = "14px";

/**
 * Finds the panel container, creating and appending it to document.body if it is not there yet.
 * @returns The container, or null when the document is not ready enough to host it.
 */
function ensureHostElement(): HTMLElement | null {
    if (typeof document === "undefined" || !document.body) {
        return null;
    }

    const existing: HTMLElement | null = document.getElementById(HOST_ELEMENT_ID);
    if (existing) {
        return existing;
    }

    const host: HTMLElement = document.createElement("div");
    host.id = HOST_ELEMENT_ID;

    // The container itself takes no space and swallows no input; the panel inside it is
    // position: fixed and lays itself out against the viewport.
    host.style.position = "fixed";
    host.style.width = "0";
    host.style.height = "0";
    host.style.fontSize = HOST_BASE_FONT_SIZE;

    document.body.appendChild(host);

    return host;
}

/**
 * Reads the POS view that is currently displayed.
 *
 * The public PosApi trigger context exposes only `navigate`/`navigateBack` (see
 * PosApi/Framework/Navigation.ts), so there is no supported accessor for the current view name.
 * The POS shell itself reads it through `Commerce.ViewModelAdapter.getCurrentViewName()`, which is
 * available on the global Commerce namespace at runtime, so that is what this uses.
 *
 * As with the body-level container, this is outside the supported surface: it is read defensively
 * and returns null rather than throwing if the shape ever changes.
 * @returns The current view name, or null when it cannot be determined.
 */
function getCurrentViewName(): string | null {
    try {
        const commerce: any = (typeof window !== "undefined") ? (window as any).Commerce : undefined;
        const viewName: unknown = commerce?.ViewModelAdapter?.getCurrentViewName?.();

        return (typeof viewName === "string" && viewName.length > 0) ? viewName : null;
    } catch {
        return null;
    }
}

/**
 * Renders the side panel, creating its container on first use. Safe to call repeatedly: the
 * container is reused and the bundle re-renders into the same React root.
 * @param {IExtensionContext} context The POS extension context, used to reach the backend and to run
 * the actions the agent chooses.
 */
export function showSideChatPanel(context: IExtensionContext): void {
    const host: HTMLElement | null = ensureHostElement();
    if (!host) {
        return;
    }

    if (!sideChatClient) {
        sideChatClient = new CsuAgentSideChatClient(context);
    }

    SideChat.mount(host, {
        client: sideChatClient,
        title: "Copilot",
        getViewContext: getCurrentViewName,

        // Only POS code can reach the navigator and the runtime, so the bundle hands the actions
        // back here rather than trying to carry them out itself.
        executeActions: (
            actions: ReadonlyArray<SideChat.IAgentPosAction>,
            options?: SideChat.IAgentActionExecutionOptions
        ): Promise<ReadonlyArray<SideChat.IActionReceipt>> => {
            // An automatic cart check only shows products, so the operator's own scans while it runs
            // still start the next check.
            if (options && options.automatic) {
                return executePosActionsAsync(actions, context, options);
            }

            // Items the agent's actions add, such as the lines of a customer order, are not the
            // operator adding to the cart, so they do not start a cart check.
            return runWhileAgentActionsRun(() => executePosActionsAsync(actions, context, options));
        },
        onPreviewProductActivated: (recordId: number): void => {
            context.navigator.navigateToPOSView(
                "SimpleProductDetailsView",
                new ClientEntities.SimpleProductDetailsNavigationParameters(recordId));
        },
        onPreviewAddToSale: (recordId: number): Promise<void> => {
            return addProductToSaleAsync(recordId, context);
        },
        onPreviewViewAll: (preview: SideChat.IAgentProductPreview, selection?: SideChat.IAgentProductFilterSelection): void => {
            context.navigator.navigate("AgentProductResultsView", {
                productIds: preview.productIds,
                productSelections: preview.productSelections,
                bestMatchProductId: preview.bestMatchProductId,
                bestMatchReason: preview.bestMatchReason,
                headline: preview.headline,
                inventory: preview.inventory,
                filterFacets: preview.filterFacets,
                filterSelection: selection
            });
        },
        onFilterProducts: (request: SideChat.IAgentProductFilterRequest): Promise<ReadonlyArray<number>> => {
            return filterProductsAsync(request, context);
        },
        // A cart plan is already the whole cart, so the products added from it do not start a cart check.
        onAddProductsToSale: (recordIds: ReadonlyArray<number>): Promise<void> => {
            return runWhileAgentActionsRun(() => addProductsToSaleAsync(recordIds, context));
        },
        formatCurrency: (amount: number): string => {
            return CurrencyFormatter.toCurrency(amount);
        }
    });
}

/**
 * Opens or closes the panel, mounting it first if it is not up yet.
 *
 * Mounting here as well as in the PostLogOn trigger means the header icon still works if the panel
 * was never shown — for example after a page reload, where the trigger does not run again.
 * @param {IExtensionContext} context The POS extension context.
 * @returns {boolean} True when the panel is now open.
 */
export function toggleSideChatPanel(context: IExtensionContext): boolean {
    showSideChatPanel(context);

    return SideChat.toggle();
}

/**
 * Tells the caller whenever the panel opens or closes, from the header icon, from the panel itself,
 * or when a cart suggestion opens it.
 * @param {(isOpen: boolean) => void} listener Called with true when the panel opens and false when it closes.
 * @returns {() => void} A function that stops the notifications.
 */
export function subscribeToSideChatOpenState(listener: (isOpen: boolean) => void): () => void {
    return SideChat.subscribeToOpenState(listener);
}

/**
 * Reads whether the panel is open.
 * @returns {boolean} True when the panel is open.
 */
export function isSideChatPanelOpen(): boolean {
    return SideChat.isOpen();
}

/**
 * Asks the agent, once the cart settles, which products would go well with it. Called after products
 * are added to the cart. Returns straight away; suggestions appear in the panel when the agent answers,
 * and the panel opens itself to show them without taking focus from POS.
 * @param {ReadonlyArray<number>} addedProductIds The products just added.
 * @param {IExtensionContext} context The POS extension context.
 */
export function suggestProductsForCart(addedProductIds: ReadonlyArray<number>, context: IExtensionContext): void {
    scheduleCartSuggestions(addedProductIds, context, (request: SideChat.ICartSuggestionRequest): void => {
        // After a page reload the sign-in trigger does not run again, so the panel may not be up yet.
        // It is mounted closed; an existing panel is left as it is.
        if (typeof document !== "undefined" && !document.getElementById(HOST_ELEMENT_ID)) {
            showSideChatPanel(context);
        }

        SideChat.requestCartSuggestions(request);
    });
}

/**
 * Tears the panel down and removes its container, discarding the conversation with it.
 *
 * Called when the operator signs out or locks the terminal so that one operator's conversation is
 * never left on screen for the next one. Safe to call when the panel was never shown.
 */
export function hideSideChatPanel(): void {
    // Forgotten even when the panel was never shown: a pending cart check, a failed lookup or a
    // conversation must not carry over to the next operator.
    resetCartSuggestions();
    resetCustomerOrderLookup();
    SideChat.clearPosError();
    sideChatClient = null;

    if (typeof document === "undefined") {
        return;
    }

    const host: HTMLElement | null = document.getElementById(HOST_ELEMENT_ID);
    if (!host) {
        return;
    }

    SideChat.unmount(host);

    if (host.parentElement) {
        host.parentElement.removeChild(host);
    }
}
