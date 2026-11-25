/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Narrows the products the agent recommended to the filter tags the associate selected.
 *
 * Pure, so it can be tested without React. Prices, and the colour and size of the variant a card
 * shows, are matched here. Which products have any other tag, such as a rating or a category, and
 * whether a master product comes in a colour or size, is for Commerce to say, so this builds the
 * request that asks it and then uses the answer. The agent is never asked.
 */

import {
    AgentProductFacetKind,
    IAgentProductCard,
    IAgentProductFacet,
    IAgentProductFacetValue,
    IAgentProductFilterRequest,
    IAgentProductFilterSelection
} from "../agentContracts";

/** The kinds of rows the tags can show. */
const FACET_KINDS: ReadonlyArray<AgentProductFacetKind> = ["color", "size", "price", "rating", "category", "attribute"];

/** No tags selected. */
export const EMPTY_FILTER_SELECTION: IAgentProductFilterSelection = {};

/**
 * Reads the key of the Color or Size tag that matches the variant a card shows.
 * @param card The product.
 * @param kind The row's kind.
 * @returns The key, or undefined for a master product, a row other than Color and Size, or a value
 * that matches no tag.
 */
export function getCardFacetKey(card: IAgentProductCard, kind: AgentProductFacetKind): string | undefined {
    const key: unknown = kind === "color" ? card.variantColor : kind === "size" ? card.variantSize : undefined;
    return typeof key === "string" && key.length > 0 ? key : undefined;
}

/**
 * Reads the tag a locked row shows.
 * @param facet The row.
 * @returns The locked tag, or undefined when the row is not locked.
 */
export function getLockedValue(facet: IAgentProductFacet): IAgentProductFacetValue | undefined {
    if (facet.lockedKey === undefined) {
        return undefined;
    }

    return facet.values.filter((value: IAgentProductFacetValue) => value.key === facet.lockedKey)[0];
}

/**
 * Reads the tags selected in a row.
 * @param selection The selection.
 * @param facetKey The row's key.
 * @returns The selected tags' keys, or none.
 */
export function getSelectedKeys(selection: IAgentProductFilterSelection, facetKey: string): ReadonlyArray<string> {
    const keys: unknown = Object.prototype.hasOwnProperty.call(selection, facetKey) ? selection[facetKey] : undefined;
    return Array.isArray(keys) ? keys : [];
}

/**
 * Reads whether a row can be shown: a known kind with tags, whose key can name it in a selection, and
 * whose locked tag, if any, is one of its tags.
 * @param facet The row, as it crossed from POS.
 * @returns True when the row can be shown.
 */
function isUsableFacet(facet: IAgentProductFacet): boolean {
    if (!facet
        || typeof facet.key !== "string"
        || facet.key.length === 0
        || Object.prototype.hasOwnProperty.call(Object.prototype, facet.key)
        || FACET_KINDS.indexOf(facet.kind) < 0
        || !Array.isArray(facet.values)
        || facet.values.length === 0) {
        return false;
    }

    return facet.lockedKey === undefined || getLockedValue(facet) !== undefined;
}

/**
 * Reads whether a row's values belong to a product's variants, such as its colours, sizes or styles.
 * @param facet The row.
 * @returns True for Color, Size and any other dimension.
 */
function isVariantRow(facet: IAgentProductFacet): boolean {
    return facet.kind === "color" || facet.kind === "size" || facet.isDimension === true;
}

/**
 * Picks the rows of tags to show.
 *
 * Price matches from the cards, and a locked row has nothing to narrow, so both always show. Any
 * other row needs Commerce to say which products have its values, so without a way to ask it shows
 * only when it is Color or Size and every card shows a variant whose value is known.
 * @param facets The rows POS built.
 * @param cards The products shown.
 * @param canAskCommerce True when Commerce can be asked which products match.
 * @returns The rows to show, in order. A row whose key an earlier row has is left out.
 */
export function getVisibleFacets(
    facets: ReadonlyArray<IAgentProductFacet> | undefined,
    cards: ReadonlyArray<IAgentProductCard>,
    canAskCommerce: boolean
): ReadonlyArray<IAgentProductFacet> {
    if (!Array.isArray(facets)) {
        return [];
    }

    const seenKeys: string[] = [];
    return facets.filter((facet: IAgentProductFacet) => {
        if (!isUsableFacet(facet) || seenKeys.indexOf(facet.key) >= 0) {
            return false;
        }

        seenKeys.push(facet.key);
        return facet.kind === "price"
            || facet.lockedKey !== undefined
            || canAskCommerce
            || ((facet.kind === "color" || facet.kind === "size")
                && cards.every((card: IAgentProductCard) => getCardFacetKey(card, facet.kind) !== undefined));
    });
}

/**
 * Keeps only the selected tags the associate can select: those in the rows shown, other than locked
 * rows, and one per row that takes one at a time. They come back in the order the rows list them, so
 * the same tags always read the same.
 * @param selection The tags selected, possibly for an older set of products.
 * @param facets The rows shown.
 * @returns The usable selection.
 */
export function sanitizeSelection(
    selection: IAgentProductFilterSelection | undefined,
    facets: ReadonlyArray<IAgentProductFacet>
): IAgentProductFilterSelection {
    if (!selection || typeof selection !== "object") {
        return EMPTY_FILTER_SELECTION;
    }

    const result: { [facetKey: string]: ReadonlyArray<string> } = {};
    facets.forEach((facet: IAgentProductFacet) => {
        const wanted: ReadonlyArray<string> = getSelectedKeys(selection, facet.key);
        if (facet.lockedKey !== undefined || wanted.length === 0) {
            return;
        }

        const keys: string[] = facet.values
            .map((value: IAgentProductFacetValue) => value.key)
            .filter((key: string) => wanted.indexOf(key) >= 0);
        if (keys.length > 0) {
            result[facet.key] = facet.singleSelect === true ? keys.slice(0, 1) : keys;
        }
    });

    return result;
}

/**
 * Keeps only the selected price tags.
 * @param selection The selection.
 * @param facets The rows shown.
 * @returns The price tags selected, which POS matches itself.
 */
export function keepPriceSelection(
    selection: IAgentProductFilterSelection,
    facets: ReadonlyArray<IAgentProductFacet>
): IAgentProductFilterSelection {
    const result: { [facetKey: string]: ReadonlyArray<string> } = {};
    facets.forEach((facet: IAgentProductFacet) => {
        const keys: ReadonlyArray<string> = getSelectedKeys(selection, facet.key);
        if (facet.kind === "price" && keys.length > 0) {
            result[facet.key] = keys;
        }
    });

    return result;
}

/**
 * Reads whether any tag is selected.
 * @param selection The selection.
 * @returns True when at least one tag is selected.
 */
export function hasSelection(selection: IAgentProductFilterSelection): boolean {
    return Object.keys(selection).some((facetKey: string) => getSelectedKeys(selection, facetKey).length > 0);
}

/**
 * Selects a tag, or clears it when it is selected. Tags in a row are alternatives, so a row can have
 * several selected, unless it takes one at a time, when selecting a tag replaces the one selected.
 * @param selection The selection.
 * @param facetKey The key of the tag's row.
 * @param key The tag.
 * @param singleSelect True when the row takes one tag at a time.
 * @returns The new selection.
 */
export function toggleSelection(
    selection: IAgentProductFilterSelection,
    facetKey: string,
    key: string,
    singleSelect?: boolean
): IAgentProductFilterSelection {
    const current: ReadonlyArray<string> = getSelectedKeys(selection, facetKey);
    let next: ReadonlyArray<string>;
    if (current.indexOf(key) >= 0) {
        next = current.filter((selected: string) => selected !== key);
    } else {
        next = singleSelect === true ? [key] : [...current, key];
    }

    return { ...selection, [facetKey]: next };
}

/**
 * Lists the rows other than Price a selection narrows. Locked rows narrow nothing: every product
 * shown already has their value.
 * @param selection The selection.
 * @param facets The rows shown.
 * @returns The rows, in order.
 */
function getSelectedRows(
    selection: IAgentProductFilterSelection,
    facets: ReadonlyArray<IAgentProductFacet>
): IAgentProductFacet[] {
    return facets.filter((facet: IAgentProductFacet) =>
        facet.kind !== "price"
        && facet.lockedKey === undefined
        && getSelectedKeys(selection, facet.key).length > 0);
}

/**
 * Lists the products only Commerce can match: those whose card shows no known value for a row the
 * selection narrows, such as a master product for Color, or any product for Category.
 * @param cards The products shown.
 * @param rows The rows the selection narrows.
 * @returns Their record identifiers, without repeats.
 */
function getProductsToAsk(cards: ReadonlyArray<IAgentProductCard>, rows: ReadonlyArray<IAgentProductFacet>): number[] {
    const productIds: number[] = [];
    cards.forEach((card: IAgentProductCard) => {
        if (rows.some((row: IAgentProductFacet) => getCardFacetKey(card, row.kind) === undefined)
            && productIds.indexOf(card.recordId) < 0) {
            productIds.push(card.recordId);
        }
    });

    return productIds;
}

/**
 * Reads whether Commerce has to be asked which products match a selection.
 * @param selection The selection.
 * @param facets The rows shown.
 * @param cards The products shown.
 * @returns True when a tag other than a price is selected and some product's value for it is unknown.
 */
export function needsCommerce(
    selection: IAgentProductFilterSelection,
    facets: ReadonlyArray<IAgentProductFacet>,
    cards: ReadonlyArray<IAgentProductCard>
): boolean {
    const rows: IAgentProductFacet[] = getSelectedRows(selection, facets);
    return rows.length > 0 && getProductsToAsk(cards, rows).length > 0;
}

/**
 * Identifies the question Commerce answers for a selection, which is about its tags other than prices.
 * @param selection The selection.
 * @param facets The rows shown.
 * @returns The same text for selections that ask the same question.
 */
export function getCommerceSignature(
    selection: IAgentProductFilterSelection,
    facets: ReadonlyArray<IAgentProductFacet>
): string {
    return JSON.stringify(getSelectedRows(selection, facets).map((row: IAgentProductFacet) =>
        [row.key, getSelectedKeys(selection, row.key)]));
}

/**
 * Builds the request that asks Commerce which products have the selected tags other than prices.
 *
 * The locked tag of a Color, Size or other variant row goes along too, because the products that
 * match must also come in the value every product shown has. Each tag carries the refiner value
 * Commerce returned for it.
 * @param cards The products shown.
 * @param facets The rows shown.
 * @param selection The selection.
 * @returns The request.
 */
export function createFilterRequest(
    cards: ReadonlyArray<IAgentProductCard>,
    facets: ReadonlyArray<IAgentProductFacet>,
    selection: IAgentProductFilterSelection
): IAgentProductFilterRequest {
    const values: IAgentProductFacetValue[] = [];
    facets.forEach((facet: IAgentProductFacet) => {
        if (facet.kind === "price") {
            return;
        }

        const locked: IAgentProductFacetValue | undefined = getLockedValue(facet);
        if (locked) {
            if (isVariantRow(facet)) {
                values.push(locked);
            }

            return;
        }

        const keys: ReadonlyArray<string> = getSelectedKeys(selection, facet.key);
        facet.values.forEach((value: IAgentProductFacetValue) => {
            if (keys.indexOf(value.key) >= 0) {
                values.push(value);
            }
        });
    });

    return {
        productIds: getProductsToAsk(cards, getSelectedRows(selection, facets)),
        values: values
    };
}

/**
 * Reads whether a price falls in a price tag's range.
 * @param price The price.
 * @param range The tag.
 * @returns True when the price is known and in the range.
 */
function isInRange(price: number | undefined, range: IAgentProductFacetValue): boolean {
    if (typeof price !== "number" || !isFinite(price)) {
        return false;
    }

    return (typeof range.minPrice !== "number" || price >= range.minPrice)
        && (typeof range.maxPrice !== "number" || price < range.maxPrice);
}

/**
 * Narrows the products to a selection, keeping the agent's order.
 *
 * Tags in a row are alternatives and rows narrow together: a product matches when it is in one of
 * the selected price ranges, and has one of the selected tags in every other row with a selection. A
 * product without a price matches no price range. A card's colour or size is matched against the
 * variant it shows; for a master product, and for every other row, Commerce's answer decides.
 * @param cards The products shown.
 * @param facets The rows shown.
 * @param selection The selection.
 * @param matchedIds The products Commerce said have the selected tags other than prices.
 * @returns The products that match, or the same list when nothing is selected.
 */
export function filterProducts(
    cards: ReadonlyArray<IAgentProductCard>,
    facets: ReadonlyArray<IAgentProductFacet>,
    selection: IAgentProductFilterSelection,
    matchedIds?: ReadonlySet<number>
): ReadonlyArray<IAgentProductCard> {
    const ranges: IAgentProductFacetValue[] = [];
    facets.forEach((facet: IAgentProductFacet) => {
        if (facet.kind === "price") {
            const priceKeys: ReadonlyArray<string> = getSelectedKeys(selection, facet.key);
            facet.values.forEach((value: IAgentProductFacetValue) => {
                if (priceKeys.indexOf(value.key) >= 0) {
                    ranges.push(value);
                }
            });
        }
    });

    const rows: IAgentProductFacet[] = getSelectedRows(selection, facets);
    if (ranges.length === 0 && rows.length === 0) {
        return cards;
    }

    return cards.filter((card: IAgentProductCard) => {
        if (ranges.length > 0 && !ranges.some((range: IAgentProductFacetValue) => isInRange(card.price, range))) {
            return false;
        }

        return rows.every((row: IAgentProductFacet) => {
            const key: string | undefined = getCardFacetKey(card, row.kind);
            return key !== undefined
                ? getSelectedKeys(selection, row.key).indexOf(key) >= 0
                : !!matchedIds && matchedIds.has(card.recordId);
        });
    });
}
