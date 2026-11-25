/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Runs the actions the agent chose.
 *
 * The agent proposes; POS disposes. An action POS does not recognise is reported as unsupported
 * rather than treated as an error, which is what lets the agent start returning a new action before
 * POS supports it without anything breaking.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import {
    IActionReceipt,
    IAgentActionDetails,
    IAgentActionExecutionOptions,
    IAgentPosAction,
    IAgentProductCard,
    IAgentProductInventory,
    IAgentProductPreview,
    IAgentProductReason,
    IAgentProductSelection,
    IAgentStoreContext
} from "ContosoSideChat";
import {
    CART_SUGGESTIONS_ACTION,
    describeProductCount,
    findActionDefinition,
    getCartSuggestionActionNames,
    IPosActionDefinition,
    IPosActionRunResult,
    PRODUCT_RECOMMENDATIONS_ACTION
} from "./posActionCatalogue";
import { IResolvedProductCards, resolveProductCardsAsync } from "./ProductCardResolver";
import { getShownInventory } from "./ProductInventory";
import { getProductFacetsAsync } from "./ProductFacetResolver";
import { IProductFacets } from "./ProductFilters";
import { getCurrentStoreAsync } from "./CurrentStoreHelper";

/** The longest reason shown on a suggested product's card. */
const MAX_REASON_LENGTH: number = 200;

/**
 * Runs a batch of actions in order, stopping at the first failure.
 *
 * Sequential rather than parallel because actions are ordered by intent — a later action generally
 * assumes the earlier ones already happened.
 * @param actions The actions the agent returned.
 * @param context The POS extension context.
 * @param options How to run them. For a turn POS started on its own, only suggestions are shown.
 * @returns A receipt for every action attempted.
 */
export async function executePosActionsAsync(
    actions: ReadonlyArray<IAgentPosAction>,
    context: IExtensionContext,
    options?: IAgentActionExecutionOptions
): Promise<IActionReceipt[]> {
    const receipts: IActionReceipt[] = [];

    if (!actions || actions.length === 0) {
        return receipts;
    }

    if (options && options.automatic) {
        return showSuggestionsAsync(actions, context, options.excludedProductIds ?? []);
    }

    for (const action of actions) {
        const definition: IPosActionDefinition | undefined = findActionDefinition(action);

        if (!definition) {
            const name: string = describe(action);
            context.logger.logInformational(`Side chat: ignoring unsupported action "${name}".`);
            receipts.push({
                action: action?.action ?? "(unnamed)",
                summary: `POS does not support the action "${name}", so it was skipped.`,
                outcome: "unsupported"
            });

            continue;
        }

        try {
            const runResult: string | IPosActionRunResult = await definition.run(action, context);
            const summary: string = typeof runResult === "string" ? runResult : runResult.summary;
            const productPreview: IAgentProductPreview | undefined =
                await resolveProductPreviewAsync(action, definition, context, false, []);

            // Recommendations are shown only as cards, so without any the action did nothing.
            if (definition.name === PRODUCT_RECOMMENDATIONS_ACTION && !productPreview) {
                throw new Error("None of the recommended products could be read from the channel.");
            }

            receipts.push({
                action: action.action,
                summary: summary,
                outcome: "ran",
                productPreview: productPreview,
                customerOrderReceipt: typeof runResult === "string"
                    ? undefined
                    : runResult.customerOrderReceipt,
                shippingReceipt: typeof runResult === "string"
                    ? undefined
                    : runResult.shippingReceipt,
                cartPlan: typeof runResult === "string"
                    ? undefined
                    : runResult.cartPlan
            });
        } catch (error) {
            const detail: string = error instanceof Error ? error.message : "Unexpected error.";
            context.logger.logError(`Side chat: action "${describe(action)}" failed. ${detail}`);
            receipts.push({
                action: action.action,
                summary: `Could not complete "${describe(action)}": ${detail}`,
                outcome: "failed"
            });

            // Later actions generally assume this one succeeded, so stop rather than compound the failure.
            break;
        }
    }

    return receipts;
}

/**
 * Handles the actions of a turn POS started on its own, such as an automatic cart check.
 *
 * The operator did not ask for anything, so POS only shows suggested products in the panel, labelled
 * as going with the cart. It does not run the actions. Products are read from the channel exactly as
 * for a recommendation, and every other action is logged and dropped, so nothing the agent returns
 * can navigate or change the transaction.
 * @param actions The actions the agent returned.
 * @param context The POS extension context.
 * @param excludedProductIds Products already in the cart, which are never suggested.
 * @returns One receipt carrying the first set of suggestions that resolved, or none.
 */
async function showSuggestionsAsync(
    actions: ReadonlyArray<IAgentPosAction>,
    context: IExtensionContext,
    excludedProductIds: ReadonlyArray<number>
): Promise<IActionReceipt[]> {
    const suggestionActionNames: string[] = getCartSuggestionActionNames();

    for (const action of actions) {
        const definition: IPosActionDefinition | undefined = findActionDefinition(action);
        if (!definition || suggestionActionNames.indexOf(definition.name) < 0) {
            context.logger.logInformational(
                `Side chat: ignoring "${describe(action)}" returned for an automatic cart check.`);
            continue;
        }

        const productPreview: IAgentProductPreview | undefined =
            await resolveProductPreviewAsync(action, definition, context, true, excludedProductIds);
        if (productPreview) {
            return [{
                action: action.action,
                summary: `Suggested ${describeProductCount(productPreview.products.length)} to go with the cart.`,
                outcome: "ran",
                productPreview: productPreview
            }];
        }
    }

    return [];
}

async function resolveProductPreviewAsync(
    action: IAgentPosAction,
    definition: IPosActionDefinition,
    context: IExtensionContext,
    automatic: boolean,
    excludedProductIds: ReadonlyArray<number>
): Promise<IAgentProductPreview | undefined> {
    if (definition.name !== PRODUCT_RECOMMENDATIONS_ACTION && definition.name !== CART_SUGGESTIONS_ACTION) {
        return undefined;
    }

    const isCartSuggestion: boolean = automatic || definition.name === CART_SUGGESTIONS_ACTION;
    const requestedSelections: IAgentProductSelection[] = action.details?.productSelections ?? [];

    // A product is in the cart when it, or the variant the agent selected for it, is already sold.
    const isInCart = (productId: number): boolean =>
        excludedProductIds.indexOf(productId) >= 0
        || requestedSelections.some((selection: IAgentProductSelection) =>
            selection.productId === productId && excludedProductIds.indexOf(selection.variantProductId) >= 0);

    const productIds: number[] = (action.details?.productIds ?? []).filter(
        (id: number) => typeof id === "number" && isFinite(id) && id > 0);
    const shownProductIds: number[] = isCartSuggestion
        ? productIds.filter((id: number, index: number) => productIds.indexOf(id) === index && !isInCart(id))
        : productIds;
    if (shownProductIds.length < productIds.length) {
        context.logger.logInformational(
            `Side chat: left ${productIds.length - shownProductIds.length} suggested product(s) out because `
            + "they are already in the cart or were repeated.");
    }

    if (shownProductIds.length === 0) {
        return undefined;
    }

    try {
        const resolved: IResolvedProductCards = await resolveProductCardsAsync(
            shownProductIds,
            context,
            requestedSelections);
        if (resolved.cards.length === 0) {
            return undefined;
        }

        const resolvedIds: number[] = resolved.cards.map((product: IAgentProductCard) => product.recordId);
        const requestedBestMatchProductId: number | undefined = action.details?.bestMatchProductId;
        const shownBestMatchProductId: number | undefined = requestedBestMatchProductId !== undefined
            && resolvedIds.indexOf(requestedBestMatchProductId) >= 0
            ? requestedBestMatchProductId
            : undefined;

        if (isCartSuggestion) {
            // Suggestions badge a product only when the agent picked one.
            return {
                products: resolved.cards,
                productIds: resolvedIds,
                productSelections: resolved.productSelections,
                bestMatchProductId: shownBestMatchProductId,
                bestMatchReason: shownBestMatchProductId !== undefined
                    ? limitReason(action.details?.bestMatchReason)
                    : undefined,
                headline: action.details?.headline,
                kind: "cartSuggestions",
                productReasons: getProductReasons(action.details, resolvedIds, requestedSelections)
            };
        }

        const preview: IAgentProductPreview = {
            products: resolved.cards,
            productIds: productIds,
            productSelections: resolved.productSelections,
            bestMatchProductId: shownBestMatchProductId ?? resolvedIds[0],
            bestMatchReason: action.details?.bestMatchReason,
            headline: action.details?.headline
        };

        // Filter tags, like stock, come only with an answer to the associate, never with a cart
        // suggestion. POS builds them for the products shown; the agent's filters only tell which
        // are already applied.
        const productFacets: IProductFacets =
            await getProductFacetsAsync(resolved.cards, action.details?.filters, context);
        preview.products = productFacets.cards;
        if (productFacets.facets.length > 0) {
            preview.filterFacets = productFacets.facets;
        }

        // Stock is looked up only when the associate asked, so a recommendation carries it and an
        // automatic cart suggestion never does. The store is read only when there is stock to label.
        const inventory: IAgentProductInventory[] | undefined = action.details?.inventory;
        if (Array.isArray(inventory) && inventory.length > 0) {
            const currentStore: IAgentStoreContext | undefined = await getCurrentStoreAsync(context);
            const shownInventory: IAgentProductInventory[] =
                getShownInventory(inventory, resolvedIds, resolved.productSelections, currentStore);
            if (shownInventory.length > 0) {
                preview.inventory = shownInventory;
                preview.currentStoreName = currentStore?.name;
            }
        }

        return preview;
    } catch (error) {
        context.logger.logInformational(
            `Side chat: product preview could not be loaded. ${JSON.stringify(error)}`);
        return undefined;
    }
}

/**
 * Pairs each shown product with the reason the agent gave for it.
 * @param details The details the agent returned.
 * @param shownProductIds The products that resolved and will be shown.
 * @param selections The variants the agent selected, whose identifiers it may have used instead.
 * @returns At most one reason per shown product, in the agent's order.
 */
function getProductReasons(
    details: IAgentActionDetails | undefined,
    shownProductIds: number[],
    selections: IAgentProductSelection[]
): IAgentProductReason[] {
    const reasons: IAgentProductReason[] = [];

    (details?.reasons ?? []).forEach((entry: IAgentProductReason) => {
        const reason: string | undefined = limitReason(entry?.reason);
        if (!reason || typeof entry.productId !== "number") {
            return;
        }

        const selection: IAgentProductSelection | undefined = selections.filter(
            (candidate: IAgentProductSelection) => candidate.variantProductId === entry.productId)[0];
        const productId: number = selection ? selection.productId : entry.productId;
        const isShown: boolean = shownProductIds.indexOf(productId) >= 0;
        const isDuplicate: boolean = reasons.some((existing: IAgentProductReason) => existing.productId === productId);
        if (isShown && !isDuplicate) {
            reasons.push({ productId: productId, reason: reason });
        }
    });

    return reasons;
}

/**
 * Trims a reason and keeps it short enough for a product card.
 * @param reason The reason the agent gave.
 * @returns The reason, or undefined when it is missing or blank.
 */
function limitReason(reason: string | undefined): string | undefined {
    if (typeof reason !== "string") {
        return undefined;
    }

    const trimmed: string = reason.trim();
    if (trimmed.length === 0) {
        return undefined;
    }

    return trimmed.length > MAX_REASON_LENGTH ? `${trimmed.substring(0, MAX_REASON_LENGTH - 1)}\u2026` : trimmed;
}

/**
 * Builds a readable name for an action, for logs and receipts.
 * @param action The action.
 * @returns The name.
 */
function describe(action: IAgentPosAction): string {
    if (!action || !action.action) {
        return "(unnamed)";
    }

    return action.action;
}
