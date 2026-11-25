/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The filter tags on a set of recommended products, and the products they leave.
 *
 * Shared by the chat's product preview and the full results view. Everything happens in POS: price
 * tags and the variants the cards show filter at once, and for any other tag, or when a master
 * product's colours or sizes matter, POS asks Commerce once per combination and remembers the answer.
 * The agent is never asked.
 */

import * as React from "react";
import {
    IAgentProductCard,
    IAgentProductFacet,
    IAgentProductFilterRequest,
    IAgentProductFilterSelection
} from "../agentContracts";
import {
    EMPTY_FILTER_SELECTION,
    createFilterRequest,
    filterProducts,
    getCommerceSignature,
    getVisibleFacets,
    hasSelection,
    keepPriceSelection,
    needsCommerce,
    sanitizeSelection,
    toggleSelection
} from "./productFilterMatching";

/** Shown when POS could not ask Commerce which products match. The tags go back as they were. */
export const FILTER_FAILED_NOTE: string = "POS couldn't filter these products. Try again.";

/** Asks POS which of the products have the selected tags other than prices. */
export type FilterProductsHandler = (request: IAgentProductFilterRequest) => Promise<ReadonlyArray<number>>;

/** The tags, what is selected and the products that match. */
export interface IProductFilters {
    /** The rows of tags to show. Empty when there are none. */
    facets: ReadonlyArray<IAgentProductFacet>;
    /** The tags selected, including any POS is still finding the products for. */
    selection: IAgentProductFilterSelection;
    /** The products that match the tags, in the agent's order. All of them when no tag is selected. */
    products: ReadonlyArray<IAgentProductCard>;
    /** True while POS finds the products that match the tags just selected. */
    isFiltering: boolean;
    /** Why the last tags selected were undone, when POS could not find their products. */
    note?: string;
    /** True when any tag is selected. */
    hasSelection: boolean;
    /** Selects a tag, or clears it when it is selected. In a row that takes one tag at a time, replaces the one selected. */
    toggle: (facetKey: string, key: string) => void;
    /** Clears every tag. */
    clear: () => void;
}

/** What the tags are doing, for one set of products. */
interface IFilterState {
    products: ReadonlyArray<IAgentProductCard>;
    facets: ReadonlyArray<IAgentProductFacet>;
    /** What Commerce said, by the question asked, so selecting the same tags again does not ask again. */
    answers: ReadonlyMap<string, ReadonlySet<number>>;
    /** The tags selected. */
    selection: IAgentProductFilterSelection;
    /** The tags the products shown match. Behind `selection` while Commerce is asked. */
    applied: IAgentProductFilterSelection;
    /** The products Commerce said have the tags other than prices in `applied`. */
    matchedIds?: ReadonlySet<number>;
    /** The selection Commerce is being asked about, and the question. */
    pending?: { signature: string; selection: IAgentProductFilterSelection };
    note?: string;
}

/**
 * Moves to a new selection: at once when POS can match it itself or already has Commerce's answer,
 * otherwise once Commerce answers.
 * @param state The current state.
 * @param requested The tags to select.
 * @returns The new state.
 */
function select(state: IFilterState, requested: IAgentProductFilterSelection): IFilterState {
    const selection: IAgentProductFilterSelection = sanitizeSelection(requested, state.facets);
    if (!needsCommerce(selection, state.facets, state.products)) {
        return { ...state, selection: selection, applied: selection, matchedIds: undefined, pending: undefined, note: undefined };
    }

    const signature: string = getCommerceSignature(selection, state.facets);
    const answer: ReadonlySet<number> | undefined = state.answers.get(signature);
    if (answer) {
        return { ...state, selection: selection, applied: selection, matchedIds: answer, pending: undefined, note: undefined };
    }

    return { ...state, selection: selection, pending: { signature: signature, selection: selection }, note: undefined };
}

/**
 * Starts the tags for a set of products. While Commerce is asked about the other tags first
 * selected, their price tags already filter.
 * @param products The products.
 * @param facets The rows shown.
 * @param initialSelection The tags to start with.
 * @returns The state.
 */
function createState(
    products: ReadonlyArray<IAgentProductCard>,
    facets: ReadonlyArray<IAgentProductFacet>,
    initialSelection: IAgentProductFilterSelection | undefined
): IFilterState {
    const state: IFilterState = select({
        products: products,
        facets: facets,
        answers: new Map<string, ReadonlySet<number>>(),
        selection: EMPTY_FILTER_SELECTION,
        applied: EMPTY_FILTER_SELECTION
    }, initialSelection ?? EMPTY_FILTER_SELECTION);

    return state.pending
        ? { ...state, applied: keepPriceSelection(state.selection, facets) }
        : state;
}

/**
 * Keeps the record identifiers Commerce returned.
 * @param productIds What came back.
 * @returns The identifiers.
 * @throws When the answer is not a list.
 */
function toMatchedIds(productIds: unknown): ReadonlySet<number> {
    if (!Array.isArray(productIds)) {
        throw new Error("POS did not return a list of products.");
    }

    return new Set<number>(productIds.filter((productId: unknown): productId is number =>
        typeof productId === "number" && isFinite(productId)));
}

/**
 * Tracks the filter tags on a set of products and the products they leave.
 *
 * Starts again when the products or their tags change.
 * @param products The products the agent recommended, in its order.
 * @param facets The rows of tags POS built for them.
 * @param onFilterProducts Asks POS which products have the selected tags other than prices. Without
 * it, only the tags POS can match from the cards show.
 * @param initialSelection The tags to start with, such as those selected in the chat.
 * @returns The tags and the products that match.
 */
export function useProductFilters(
    products: ReadonlyArray<IAgentProductCard>,
    facets: ReadonlyArray<IAgentProductFacet> | undefined,
    onFilterProducts?: FilterProductsHandler,
    initialSelection?: IAgentProductFilterSelection
): IProductFilters {
    const canAskCommerce: boolean = !!onFilterProducts;
    const visibleFacets: ReadonlyArray<IAgentProductFacet> = React.useMemo(
        () => getVisibleFacets(facets, products, canAskCommerce),
        [facets, products, canAskCommerce]);

    // Hosts may pass a new function on every render, so the request reads the latest one.
    const onFilterProductsRef = React.useRef<FilterProductsHandler | undefined>(onFilterProducts);
    React.useEffect(() => {
        onFilterProductsRef.current = onFilterProducts;
    }, [onFilterProducts]);

    const [storedState, setState] = React.useState<IFilterState>(
        () => createState(products, visibleFacets, initialSelection));

    // New products start again, during render, so they never show with the old products' tags.
    let state: IFilterState = storedState;
    if (storedState.products !== products || storedState.facets !== visibleFacets) {
        state = createState(products, visibleFacets, initialSelection);
        setState(state);
    }

    // The question depends only on the products, the rows and the tags other than prices selected, so
    // a price tag selected while Commerce answers neither asks again nor cancels the question.
    const pendingSignature: string | undefined = state.pending?.signature;
    const pendingSelection: IAgentProductFilterSelection | undefined = state.pending?.selection;
    const { answers } = state;
    React.useEffect(() => {
        if (pendingSignature === undefined || !pendingSelection) {
            return undefined;
        }

        let isCurrent: boolean = true;
        const request: IAgentProductFilterRequest = createFilterRequest(state.products, state.facets, pendingSelection);
        Promise.resolve()
            .then(() => {
                const filter: FilterProductsHandler | undefined = onFilterProductsRef.current;
                if (!filter) {
                    throw new Error("POS cannot filter these products.");
                }

                return filter(request);
            })
            .then((productIds: ReadonlyArray<number>) => {
                const matchedIds: ReadonlySet<number> = toMatchedIds(productIds);
                if (!isCurrent) {
                    return;
                }

                setState((latest: IFilterState) => {
                    if (latest.answers !== answers || !latest.pending || latest.pending.signature !== pendingSignature) {
                        return latest;
                    }

                    const nextAnswers: Map<string, ReadonlySet<number>> = new Map<string, ReadonlySet<number>>(latest.answers);
                    nextAnswers.set(pendingSignature, matchedIds);
                    return {
                        ...latest,
                        answers: nextAnswers,
                        applied: latest.pending.selection,
                        matchedIds: matchedIds,
                        pending: undefined,
                        note: undefined
                    };
                });
            })
            .catch(() => {
                if (!isCurrent) {
                    return;
                }

                setState((latest: IFilterState) => {
                    if (latest.answers !== answers || !latest.pending || latest.pending.signature !== pendingSignature) {
                        return latest;
                    }

                    return { ...latest, selection: latest.applied, pending: undefined, note: FILTER_FAILED_NOTE };
                });
            });

        return () => {
            isCurrent = false;
        };
        // A new answer, or new products, comes with a new `answers`; the rest follows from the question.
    }, [pendingSignature, answers]);

    const matchingProducts: ReadonlyArray<IAgentProductCard> = React.useMemo(
        () => filterProducts(state.products, state.facets, state.applied, state.matchedIds),
        [state.products, state.facets, state.applied, state.matchedIds]);

    const toggle = React.useCallback((facetKey: string, key: string): void => {
        setState((latest: IFilterState) => {
            const facet: IAgentProductFacet | undefined = latest.facets.filter((row: IAgentProductFacet) => row.key === facetKey)[0];
            return facet
                ? select(latest, toggleSelection(latest.selection, facetKey, key, facet.singleSelect === true))
                : latest;
        });
    }, []);

    const clear = React.useCallback((): void => {
        setState((latest: IFilterState) => select(latest, EMPTY_FILTER_SELECTION));
    }, []);

    return {
        facets: state.facets,
        selection: state.selection,
        products: matchingProducts,
        isFiltering: state.pending !== undefined,
        note: state.note,
        hasSelection: hasSelection(state.selection),
        toggle: toggle,
        clear: clear
    };
}
