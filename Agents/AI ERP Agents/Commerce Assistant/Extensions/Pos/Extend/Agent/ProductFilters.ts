/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Builds the filter tags shown with a set of recommended products.
 *
 * The agent decides which products to show; POS builds the tags for them, from the refiners Commerce
 * returns for exactly those products, as the POS search view's Filter command reads them. Color and
 * Size come first, then Price, built from the prices POS already read for the cards in place of
 * Commerce's price refiner, then every other refiner Commerce returns, such as Rating, Category, Brand
 * or Style, in Commerce's order. Selecting tags narrows the products already shown, in POS: the agent
 * is not asked again.
 *
 * A value every product already has, such as the size the associate asked for, is locked: its tag
 * shows as selected, cannot be cleared, and is the only tag in its row. The filters the agent reports
 * are hints for that and nothing else: they never add a tag.
 *
 * Refiners the search view shows as a slider or a text box have no tags to show, and are left out.
 *
 * Pure on purpose: no POS APIs, so the rules can be tested outside POS.
 */

import {
    IAgentProductCard,
    IAgentProductFacet,
    IAgentProductFacetValue,
    IAgentProductFilter
} from "ContosoSideChat";

/** The most applied filters read from the agent's hints. */
export const MAX_AGENT_FILTERS: number = 8;

/** The longest tag text shown, and the longest filter name accepted. */
export const MAX_FILTER_TEXT_LENGTH: number = 40;

/** The most tags in a row other than Price. */
export const MAX_FACET_VALUES: number = 12;

/** The most tags in the Price row. */
export const MAX_PRICE_RANGES: number = 4;

/** The most rows of tags, Color, Size and Price included. */
export const MAX_FACET_ROWS: number = 10;

/** The parts of a Commerce product refiner value the tags are built from. */
export interface IRefinerValueSource {
    LeftValueBoundString?: string;
    LeftValueBoundLocalizedString?: string;
    RightValueBoundString?: string;
    RightValueBoundLocalizedString?: string;
    UnitText?: string;
    SwatchColorHexCode?: string;
    Count?: number;
    /** Where the value comes from, as Commerce's ProductRefinerSource. */
    RefinerSourceValue?: number;
    /** The value's type, as Commerce's AttributeDataType. */
    DataTypeValue?: number;
}

/** The parts of a Commerce product refiner the tags are built from. */
export interface IRefinerSource {
    RecordId?: number;
    KeyName?: string;
    IsDimension?: boolean;
    /** Where the refiner comes from, as Commerce's ProductRefinerSource. */
    SourceValue?: number;
    /** Whether one or several values can be selected, as Commerce's RefinerType. */
    RefinerTypeValue?: number;
    /** How the search view shows the refiner, as Commerce's DisplayTemplate. */
    DisplayTemplateValue?: number;
    /** The values' type, as Commerce's AttributeDataType. */
    DataTypeValue?: number;
    Values?: ReadonlyArray<IRefinerValueSource>;
}

/** What the tags are built from. */
export interface IProductFacetSource {
    /** The refiners Commerce returned for the products shown. Empty when it returned none. */
    refiners: ReadonlyArray<IRefinerSource>;
    /** The products shown, in the agent's order. */
    cards: ReadonlyArray<IAgentProductCard>;
    /** The filters the agent reported. Anything other than an array is ignored. */
    agentFilters?: unknown;
    /** Formats a price in the channel's currency. */
    formatPrice: (price: number) => string;
}

/** The tags for a set of products, and the products as the tags see them. */
export interface IProductFacets {
    /**
     * The rows to show: Color, Size, Price, then Commerce's other refiners in its order, each only
     * when it has tags, and at most {@link MAX_FACET_ROWS}.
     */
    facets: IAgentProductFacet[];
    /**
     * The products, in the same order. A product's variant colour and size are given as the key of
     * the tag they match, and left out when no tag matches them.
     */
    cards: IAgentProductCard[];
}

type DimensionKind = "color" | "size";

/** What a row built from one of Commerce's other refiners filters on. */
type RefinerKind = "rating" | "category" | "attribute";

/** A tag read from a refiner, with the number of products Commerce counted for it. */
interface IFacetCandidate {
    value: IAgentProductFacetValue;
    count?: number;
}

/** A tag's key and text, read from a refiner value. */
interface IValueText {
    key: string;
    label: string;
}

/** Commerce's ProductRefinerSource values. */
const CATEGORY_SOURCE: number = 2;
const PRICE_SOURCE: number = 3;
const RATING_SOURCE: number = 4;

/** Commerce's DisplayTemplate values the search view lists values for. The others are sliders and text boxes. */
const LIST_TEMPLATE: number = 0;
const RANGE_TEMPLATE: number = 3;

/** Commerce's RefinerType values. */
const SINGLE_SELECT_REFINER: number = 0;
const FREE_TEXT_REFINER: number = 2;

/** Commerce's AttributeDataType values the tags read differently. */
const CURRENCY_DATA_TYPE: number = 1;
const DECIMAL_DATA_TYPE: number = 3;
const TRUE_FALSE_DATA_TYPE: number = 6;
const VIDEO_DATA_TYPE: number = 40;
const IMAGE_DATA_TYPE: number = 41;

/** Steps the price ranges are built on. Larger steps repeat the pattern a thousand times larger. */
const PRICE_STEPS: number[] = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500];

/** Ways a size is written, each mapped to one spelling, so "Medium" finds the tag "M". */
const SIZE_SPELLINGS: { [compact: string]: string } = {
    xxs: "xxs", "2xs": "xxs", xxsmall: "xxs", extraextrasmall: "xxs",
    xs: "xs", xsmall: "xs", extrasmall: "xs",
    s: "s", sm: "s", small: "s",
    m: "m", md: "m", med: "m", medium: "m",
    l: "l", lg: "l", large: "l",
    xl: "xl", xlarge: "xl", extralarge: "xl",
    xxl: "xxl", "2xl": "xxl", "2x": "xxl", xxlarge: "xxl", extraextralarge: "xxl",
    xxxl: "xxxl", "3xl": "xxxl", "3x": "xxxl", xxxlarge: "xxxl"
};

/**
 * Builds the filter tags for a set of recommended products.
 * @param source The refiners, products, agent hints and price formatting to build them from.
 * @returns The rows to show and the products as the tags see them. No rows for fewer than two products,
 * since there is nothing to narrow.
 */
export function buildProductFacets(source: IProductFacetSource): IProductFacets {
    const inputCards: ReadonlyArray<IAgentProductCard> = Array.isArray(source?.cards) ? source.cards : [];
    const refiners: ReadonlyArray<IRefinerSource> = Array.isArray(source?.refiners) ? source.refiners : [];
    const found: { color?: IRefinerSource; size?: IRefinerSource } = findRefiners(refiners, inputCards);
    const colors: IFacetCandidate[] = readCandidates(found.color);
    const sizes: IFacetCandidate[] = readCandidates(found.size);
    const cards: IAgentProductCard[] = inputCards.map((card: IAgentProductCard) => reconcileCard(card, colors, sizes));

    if (cards.length < 2) {
        return { facets: [], cards: cards };
    }

    const hints: IAgentProductFilter[] = getAppliedHints(source.agentFilters);
    const facets: IAgentProductFacet[] = [];
    const add = (facet: IAgentProductFacet | undefined): void => {
        if (facet && facets.length < MAX_FACET_ROWS) {
            facets.push(facet);
        }
    };

    add(buildDimensionFacet("color", "Color", colors, cards, hints));
    add(buildDimensionFacet("size", "Size", sizes, cards, hints));
    add(buildPriceFacet(cards, source.formatPrice));

    // The rows' keys are unique, so a selection names one row. Color, Size and Price keep their kind as theirs.
    const usedKeys: { [key: string]: boolean } = { color: true, size: true, price: true };
    refiners.forEach((refiner: IRefinerSource) => {
        if (refiner !== found.color && refiner !== found.size) {
            add(buildRefinerFacet(refiner, cards.length, hints, source.formatPrice, usedKeys));
        }
    });

    return { facets: facets, cards: cards };
}

/**
 * Gives products their variants' colours and sizes as the keys of tags already built for them, such
 * as the tags the results view receives from the chat with the products it reads again.
 * @param cards The products, as POS read them.
 * @param facets The tags.
 * @returns A copy of each product, in the same order, matched to the tags as {@link buildProductFacets}
 * matches them.
 */
export function matchCardsToFacets(
    cards: ReadonlyArray<IAgentProductCard>,
    facets: ReadonlyArray<IAgentProductFacet> | undefined
): IAgentProductCard[] {
    const getCandidates = (kind: DimensionKind): IFacetCandidate[] => {
        const facet: IAgentProductFacet | undefined = (Array.isArray(facets) ? facets : [])
            .filter((candidate: IAgentProductFacet) => !!candidate && candidate.kind === kind)[0];
        return (facet?.values ?? []).map((value: IAgentProductFacetValue) => ({ value: value }));
    };
    const colors: IFacetCandidate[] = getCandidates("color");
    const sizes: IFacetCandidate[] = getCandidates("size");

    return (Array.isArray(cards) ? cards : []).map((card: IAgentProductCard) => reconcileCard(card, colors, sizes));
}

/**
 * Makes a formatted price shorter when it has no cents, so "$50.00" reads "$50".
 * @param text The formatted price.
 * @returns The price without a final zero fraction.
 */
export function trimZeroDecimals(text: string): string {
    return text.replace(/[.,]00(?!.*\d)/, "");
}

/**
 * Tells what a refiner or a filter is on from its name.
 * @param name The name, such as "Color", "Colour" or "Sizes".
 * @returns The kind, or undefined when the name is neither a colour nor a size.
 */
export function getDimensionKind(name: unknown): DimensionKind | undefined {
    const letters: string = toLetters(name);
    if (/^colou?rs?$/.test(letters)) {
        return "color";
    }

    return /^sizes?$/.test(letters) ? "size" : undefined;
}

/**
 * Finds the refiners to build the Color and Size rows from.
 *
 * A refiner named Color or Size is used first, a product dimension before an attribute of the same
 * name. A dimension whose name is not recognised, a translated one say, is Color when Commerce has
 * swatches for it, and otherwise Color or Size when its values are the products' variants' values.
 * @param refiners The refiners Commerce returned.
 * @param cards The products shown.
 * @returns The refiner for each row, when there is one.
 */
function findRefiners(
    refiners: ReadonlyArray<IRefinerSource>,
    cards: ReadonlyArray<IAgentProductCard>
): { color?: IRefinerSource; size?: IRefinerSource } {
    const usable: IRefinerSource[] = refiners.filter((refiner: IRefinerSource) =>
        !!refiner && typeof refiner === "object" && Array.isArray(refiner.Values) && refiner.Values.length > 0);
    const pickNamed = (kind: DimensionKind): IRefinerSource | undefined => {
        const named: IRefinerSource[] = usable.filter((refiner: IRefinerSource) => getDimensionKind(refiner.KeyName) === kind);
        return named.filter((refiner: IRefinerSource) => refiner.IsDimension === true)[0] ?? named[0];
    };

    let color: IRefinerSource | undefined = pickNamed("color");
    let size: IRefinerSource | undefined = pickNamed("size");
    usable.forEach((refiner: IRefinerSource) => {
        if (refiner.IsDimension !== true || getDimensionKind(refiner.KeyName) !== undefined) {
            return;
        }

        if (!color && (hasSwatches(refiner) || matchesCards(refiner, cards, "color"))) {
            color = refiner;
        } else if (!size && matchesCards(refiner, cards, "size")) {
            size = refiner;
        }
    });

    return { color: color, size: size };
}

/**
 * Tells whether Commerce has a swatch colour for any of a refiner's values.
 * @param refiner The refiner.
 * @returns True when it does.
 */
function hasSwatches(refiner: IRefinerSource): boolean {
    return (refiner.Values ?? []).some((value: IRefinerValueSource) =>
        !!value && readSwatchColor(value.SwatchColorHexCode) !== undefined);
}

/**
 * Tells whether a refiner's values include a product's variant colour or size.
 * @param refiner The refiner.
 * @param cards The products shown.
 * @param kind Which of the variant's values to look for.
 * @returns True when a product shows a variant whose value is one of the refiner's.
 */
function matchesCards(refiner: IRefinerSource, cards: ReadonlyArray<IAgentProductCard>, kind: DimensionKind): boolean {
    const candidates: IFacetCandidate[] = readCandidates(refiner);
    return cards.some((card: IAgentProductCard) =>
        findCandidate(kind, readText(kind === "color" ? card?.variantColor : card?.variantSize), candidates) !== undefined);
}

/**
 * Reads the tags in a refiner.
 * @param refiner The refiner, if there is one.
 * @returns One tag per distinct value, in the order Commerce lists them.
 */
function readCandidates(refiner: IRefinerSource | undefined): IFacetCandidate[] {
    const candidates: IFacetCandidate[] = [];

    (refiner?.Values ?? []).forEach((raw: IRefinerValueSource) => {
        if (!raw || typeof raw !== "object") {
            return;
        }

        const bound: string = readText(raw.LeftValueBoundString);
        const localized: string = readText(raw.LeftValueBoundLocalizedString);
        const key: string = normalize(bound.length > 0 ? bound : localized);
        if (key.length === 0 || candidates.some((candidate: IFacetCandidate) => candidate.value.key === key)) {
            return;
        }

        const value: IAgentProductFacetValue = {
            key: key,
            label: limitText(localized.length > 0 ? localized : bound),
            refinerValue: raw
        };
        const swatchColor: string | undefined = readSwatchColor(raw.SwatchColorHexCode);
        if (swatchColor) {
            value.swatchColor = swatchColor;
        }

        candidates.push({
            value: value,
            count: typeof raw.Count === "number" && isFinite(raw.Count) ? raw.Count : undefined
        });
    });

    return candidates;
}

/**
 * Gives a product its variant's colour and size as the keys of the tags they match.
 * @param card The product, as POS read it.
 * @param colors The Color tags.
 * @param sizes The Size tags.
 * @returns A copy of the product. A value no tag matches is left out, so the product is filtered by
 * Commerce rather than by POS.
 */
function reconcileCard(card: IAgentProductCard, colors: IFacetCandidate[], sizes: IFacetCandidate[]): IAgentProductCard {
    const reconciled: IAgentProductCard = { ...card };
    delete reconciled.variantColor;
    delete reconciled.variantSize;

    const color: IFacetCandidate | undefined = findCandidate("color", readText(card.variantColor), colors);
    if (color) {
        reconciled.variantColor = color.value.key;
    }

    const size: IFacetCandidate | undefined = findCandidate("size", readText(card.variantSize), sizes);
    if (size) {
        reconciled.variantSize = size.value.key;
    }

    return reconciled;
}

/**
 * Builds the Color or the Size row.
 * @param kind Which row.
 * @param label The row's label.
 * @param candidates The row's tags, as Commerce lists them.
 * @param cards The products shown, already reconciled with the tags.
 * @param hints The filters the agent reported as applied.
 * @returns The row, or undefined when Commerce has no values for it.
 */
function buildDimensionFacet(
    kind: DimensionKind,
    label: string,
    candidates: IFacetCandidate[],
    cards: IAgentProductCard[],
    hints: IAgentProductFilter[]
): IAgentProductFacet | undefined {
    if (candidates.length === 0) {
        return undefined;
    }

    const lockedKey: string | undefined = findLockedKey(kind, candidates, cards, hints);
    if (lockedKey !== undefined) {
        const locked: IAgentProductFacetValue = candidates.filter((candidate: IFacetCandidate) =>
            candidate.value.key === lockedKey)[0].value;

        return { key: kind, kind: kind, label: label, values: [locked], lockedKey: lockedKey };
    }

    return { key: kind, kind: kind, label: label, values: limitCandidates(candidates, getPinnedKeys(cards, kind)) };
}

/**
 * Finds the value every product shown already has, which locks the row.
 *
 * That is the one value Commerce lists for the products, unless its count shows some lack it; the one
 * value every product's variant has; or the one value the agent reported as applied, when no product's
 * variant has another.
 * @param kind Which row.
 * @param candidates The row's tags.
 * @param cards The products shown, already reconciled with the tags.
 * @param hints The filters the agent reported as applied.
 * @returns The key of the locked tag, or undefined when the row is not locked.
 */
function findLockedKey(
    kind: DimensionKind,
    candidates: IFacetCandidate[],
    cards: IAgentProductCard[],
    hints: IAgentProductFilter[]
): string | undefined {
    const pinned: string[] = getPinnedKeys(cards, kind);
    const isPinnedTo = (key: string): boolean => pinned.every((pinnedKey: string) => pinnedKey === key);

    if (candidates.length === 1) {
        const only: IFacetCandidate = candidates[0];
        const someLackIt: boolean = only.count !== undefined && only.count > 0 && only.count < cards.length;
        if (!someLackIt && isPinnedTo(only.value.key)) {
            return only.value.key;
        }
    }

    if (pinned.length > 0 && pinned.length === cards.length && isPinnedTo(pinned[0])) {
        return pinned[0];
    }

    const hinted: string[] = [];
    hints.forEach((hint: IAgentProductFilter) => {
        if (getDimensionKind(hint.name) !== kind) {
            return;
        }

        const match: IFacetCandidate | undefined = findCandidate(kind, hint.value, candidates)
            ?? findCandidate(kind, stripFilterName(kind, hint.value), candidates)
            ?? findCandidate(kind, stripFilterName(kind, hint.label ?? ""), candidates);
        if (match && hinted.indexOf(match.value.key) < 0) {
            hinted.push(match.value.key);
        }
    });

    return hinted.length === 1 && isPinnedTo(hinted[0]) ? hinted[0] : undefined;
}

/**
 * Lists the tag keys the products' variants have for a row.
 * @param cards The products shown, already reconciled with the tags.
 * @param kind Which row.
 * @returns One key per product whose variant has one, in the products' order.
 */
function getPinnedKeys(cards: ReadonlyArray<IAgentProductCard>, kind: DimensionKind): string[] {
    const keys: string[] = [];
    cards.forEach((card: IAgentProductCard) => {
        const key: string | undefined = kind === "color" ? card.variantColor : card.variantSize;
        if (typeof key === "string" && key.length > 0) {
            keys.push(key);
        }
    });

    return keys;
}

/**
 * Keeps a row short enough to read, without dropping a value a product's variant has.
 * @param candidates The row's tags, as Commerce lists them.
 * @param pinnedKeys The keys the products' variants have.
 * @returns At most {@link MAX_FACET_VALUES} tags, in Commerce's order.
 */
function limitCandidates(candidates: IFacetCandidate[], pinnedKeys: string[]): IAgentProductFacetValue[] {
    const kept: { [key: string]: boolean } = {};
    let count: number = 0;
    const keep = (candidate: IFacetCandidate, onlyPinned: boolean): void => {
        const key: string = candidate.value.key;
        if (!kept[key] && count < MAX_FACET_VALUES && (!onlyPinned || pinnedKeys.indexOf(key) >= 0)) {
            kept[key] = true;
            count++;
        }
    };

    candidates.forEach((candidate: IFacetCandidate) => keep(candidate, true));
    candidates.forEach((candidate: IFacetCandidate) => keep(candidate, false));

    return candidates
        .filter((candidate: IFacetCandidate) => kept[candidate.value.key])
        .map((candidate: IFacetCandidate) => candidate.value);
}

/**
 * Builds the Price row from the products' prices.
 *
 * Ranges are on round steps, such as 20 or 50, the smallest that gives at most
 * {@link MAX_PRICE_RANGES} ranges with products in them. Ranges with no products are left out. The
 * lowest range reads "Under", the highest "and up".
 * @param cards The products shown.
 * @param formatPrice Formats a price in the channel's currency.
 * @returns The row, or undefined when the prices do not fall into at least two ranges.
 */
function buildPriceFacet(
    cards: ReadonlyArray<IAgentProductCard>,
    formatPrice: (price: number) => string
): IAgentProductFacet | undefined {
    const prices: number[] = [];
    cards.forEach((card: IAgentProductCard) => {
        const price: number | undefined = card.price;
        if (typeof price === "number" && isFinite(price) && price >= 0 && prices.indexOf(price) < 0) {
            prices.push(price);
        }
    });

    if (prices.length < 2) {
        return undefined;
    }

    const spread: number = Math.max.apply(Math, prices) - Math.min.apply(Math, prices);
    let stepIndex: number = 0;
    while (getPriceStep(stepIndex) < spread / MAX_PRICE_RANGES) {
        stepIndex++;
    }

    let buckets: number[] = getPriceBuckets(prices, getPriceStep(stepIndex));
    while (buckets.length > MAX_PRICE_RANGES) {
        stepIndex++;
        buckets = getPriceBuckets(prices, getPriceStep(stepIndex));
    }

    if (buckets.length < 2) {
        return undefined;
    }

    const step: number = getPriceStep(stepIndex);
    const format = (price: number): string => {
        try {
            return trimZeroDecimals(formatPrice(price));
        } catch {
            return String(price);
        }
    };

    const values: IAgentProductFacetValue[] = buckets.map((bucket: number, position: number) => {
        const lower: number = bucket * step;
        const upper: number = (bucket + 1) * step;
        const key: string = `p${position}`;
        if (position === 0) {
            return { key: key, label: `Under ${format(upper)}`, maxPrice: upper };
        }

        if (position === buckets.length - 1) {
            return { key: key, label: `${format(lower)} and up`, minPrice: lower };
        }

        return { key: key, label: `${format(lower)}\u2013${format(upper)}`, minPrice: lower, maxPrice: upper };
    });

    return { key: "price", kind: "price", label: "Price", values: values };
}

/**
 * Builds a row from one of Commerce's refiners other than Color, Size and Price, such as Rating,
 * Category, an attribute like Brand, or a dimension like Style.
 *
 * Its tags read as the POS search view's Filter command reads them: a rating as "4 stars and up", a
 * yes-or-no attribute as Yes or No, an amount in the channel's currency, a number with its unit, and a
 * range as "Under", "Over" or from-to. Its one value, or the one value the agent reported as applied,
 * locks it unless Commerce counted fewer products with it than are shown.
 * @param refiner The refiner.
 * @param cardCount How many products are shown.
 * @param hints The filters the agent reported as applied.
 * @param formatPrice Formats a price in the channel's currency.
 * @param usedKeys The keys of the rows built so far. The row's key is added to them.
 * @returns The row, or undefined when the refiner is the price, is named Color or Size, is not shown
 * as a list of values in the search view, or has no values to show.
 */
function buildRefinerFacet(
    refiner: IRefinerSource,
    cardCount: number,
    hints: IAgentProductFilter[],
    formatPrice: (price: number) => string,
    usedKeys: { [key: string]: boolean }
): IAgentProductFacet | undefined {
    if (!refiner || typeof refiner !== "object" || !Array.isArray(refiner.Values)) {
        return undefined;
    }

    // Color and Size are rows of their own, so a second refiner named so would only repeat them.
    const label: string = limitText(readText(refiner.KeyName));
    if (label.length === 0 || getDimensionKind(refiner.KeyName) !== undefined || isPriceRefiner(refiner) || !isListedRefiner(refiner)) {
        return undefined;
    }

    const kind: RefinerKind = getRefinerKind(refiner);
    const isRange: boolean = refiner.DisplayTemplateValue === RANGE_TEMPLATE;
    const candidates: IFacetCandidate[] = readRefinerCandidates(refiner, kind, isRange, formatPrice);
    if (candidates.length === 0) {
        return undefined;
    }

    const lockedKey: string | undefined = findRefinerLockedKey(kind, label, candidates, cardCount, hints);
    const facet: IAgentProductFacet = {
        key: claimRefinerKey(refiner, kind, usedKeys),
        kind: kind,
        label: label,
        values: lockedKey !== undefined
            ? candidates.filter((candidate: IFacetCandidate) => candidate.value.key === lockedKey).map((candidate: IFacetCandidate) => candidate.value)
            : candidates.slice(0, MAX_FACET_VALUES).map((candidate: IFacetCandidate) => candidate.value)
    };

    if (lockedKey !== undefined) {
        facet.lockedKey = lockedKey;
    }

    // As in the search view, a range or a single-select refiner takes one value at a time.
    if (isRange || refiner.RefinerTypeValue === SINGLE_SELECT_REFINER) {
        facet.singleSelect = true;
    }

    if (refiner.IsDimension === true) {
        facet.isDimension = true;
    }

    return facet;
}

/**
 * Tells whether a refiner is the price, which the Price row built from the cards' prices replaces.
 * @param refiner The refiner.
 * @returns True when Commerce says it is the price, or it is named Price.
 */
function isPriceRefiner(refiner: IRefinerSource): boolean {
    return readRefinerSource(refiner) === PRICE_SOURCE || /^prices?$/.test(toLetters(refiner.KeyName));
}

/**
 * Tells whether the POS search view lists a refiner's values to choose from, as tags can show them.
 * @param refiner The refiner.
 * @returns False for a slider, a text box, free text, and images or videos.
 */
function isListedRefiner(refiner: IRefinerSource): boolean {
    const template: number | undefined = refiner.DisplayTemplateValue;
    const listed: boolean = typeof template !== "number" || template === LIST_TEMPLATE || template === RANGE_TEMPLATE;
    return listed
        && refiner.RefinerTypeValue !== FREE_TEXT_REFINER
        && refiner.DataTypeValue !== VIDEO_DATA_TYPE
        && refiner.DataTypeValue !== IMAGE_DATA_TYPE;
}

/**
 * Reads where a refiner comes from.
 * @param refiner The refiner.
 * @returns Commerce's ProductRefinerSource for the refiner, else for its first value that has one, or
 * undefined when neither says.
 */
function readRefinerSource(refiner: IRefinerSource): number | undefined {
    if (typeof refiner.SourceValue === "number" && refiner.SourceValue > 0) {
        return refiner.SourceValue;
    }

    let source: number | undefined;
    (refiner.Values ?? []).forEach((value: IRefinerValueSource) => {
        if (source === undefined && !!value && typeof value.RefinerSourceValue === "number" && value.RefinerSourceValue > 0) {
            source = value.RefinerSourceValue;
        }
    });

    return source;
}

/**
 * Tells what a refiner other than Color, Size and Price filters on.
 * @param refiner The refiner.
 * @returns Rating or category when Commerce says so, or, when it does not say, when the refiner is
 * named so. Otherwise an attribute, which includes dimensions such as Style.
 */
function getRefinerKind(refiner: IRefinerSource): RefinerKind {
    const source: number | undefined = readRefinerSource(refiner);
    if (source === RATING_SOURCE) {
        return "rating";
    }

    if (source === CATEGORY_SOURCE) {
        return "category";
    }

    if (source === undefined) {
        const letters: string = toLetters(refiner.KeyName);
        if (/^ratings?$/.test(letters)) {
            return "rating";
        }

        if (/^categor(y|ies)$/.test(letters)) {
            return "category";
        }
    }

    return "attribute";
}

/**
 * Reads the tags in a refiner other than Color, Size and Price.
 * @param refiner The refiner.
 * @param kind What it filters on.
 * @param isRange True when its values are ranges.
 * @param formatPrice Formats a price in the channel's currency.
 * @returns One tag per distinct value, in the order Commerce lists them, each carrying the value as
 * Commerce returned it.
 */
function readRefinerCandidates(
    refiner: IRefinerSource,
    kind: RefinerKind,
    isRange: boolean,
    formatPrice: (price: number) => string
): IFacetCandidate[] {
    const candidates: IFacetCandidate[] = [];

    (refiner.Values ?? []).forEach((raw: IRefinerValueSource) => {
        if (!raw || typeof raw !== "object") {
            return;
        }

        const text: IValueText | undefined = isRange
            ? readRangeText(refiner, raw, kind, formatPrice)
            : readListText(refiner, raw, kind, formatPrice);
        if (!text || text.key.length === 0 || text.label.length === 0
            || candidates.some((candidate: IFacetCandidate) => candidate.value.key === text.key)) {
            return;
        }

        const value: IAgentProductFacetValue = { key: text.key, label: limitText(text.label), refinerValue: raw };
        const swatchColor: string | undefined = readSwatchColor(raw.SwatchColorHexCode);
        if (swatchColor) {
            value.swatchColor = swatchColor;
        }

        candidates.push({
            value: value,
            count: typeof raw.Count === "number" && isFinite(raw.Count) ? raw.Count : undefined
        });
    });

    return candidates;
}

/**
 * Reads one value of a refiner listed as values, as the POS search view's Filter command shows it.
 * @param refiner The refiner.
 * @param raw The value.
 * @param kind What the refiner filters on.
 * @param formatPrice Formats a price in the channel's currency.
 * @returns The tag's key and text, or undefined when the value has neither.
 */
function readListText(
    refiner: IRefinerSource,
    raw: IRefinerValueSource,
    kind: RefinerKind,
    formatPrice: (price: number) => string
): IValueText | undefined {
    const bound: string = readText(raw.LeftValueBoundString);
    const localized: string = readText(raw.LeftValueBoundLocalizedString);
    const text: string = bound.length > 0 ? bound : localized;
    const dataType: number | undefined = readDataType(refiner, raw);

    if (kind === "rating") {
        // No stars and up would be every product, so it is not a tag.
        const stars: number | undefined = readNumber(text);
        if (stars !== undefined) {
            return stars > 0
                ? { key: normalize(text), label: stars === 1 ? "1 star and up" : `${formatNumber(stars)} stars and up` }
                : undefined;
        }
    }

    if (dataType === TRUE_FALSE_DATA_TYPE) {
        const flag: string = readText(raw.RightValueBoundString) || text;
        const isTrue: boolean = flag === "1" || flag.toLowerCase() === "true";
        return { key: isTrue ? "yes" : "no", label: isTrue ? "Yes" : "No" };
    }

    if (text.length === 0) {
        return undefined;
    }

    const amount: number | undefined = readNumber(bound);
    if (amount !== undefined && dataType === CURRENCY_DATA_TYPE) {
        return { key: normalize(text), label: formatAmount(amount, formatPrice) };
    }

    if (amount !== undefined && dataType === DECIMAL_DATA_TYPE) {
        return { key: normalize(text), label: withUnit(formatNumber(amount), raw.UnitText) };
    }

    return { key: normalize(text), label: localized.length > 0 ? localized : bound };
}

/**
 * Reads one value of a refiner listed as ranges, as the POS search view's Filter command shows it.
 * @param refiner The refiner.
 * @param raw The value.
 * @param kind What the refiner filters on.
 * @param formatPrice Formats a price in the channel's currency.
 * @returns The tag's key and text, such as "Under 10 kg", "Over 20 kg" or "10 kg–20 kg", or undefined
 * for the search view's custom range, which has no bounds.
 */
function readRangeText(
    refiner: IRefinerSource,
    raw: IRefinerValueSource,
    kind: RefinerKind,
    formatPrice: (price: number) => string
): IValueText | undefined {
    const left: string = readText(raw.LeftValueBoundString);
    const right: string = readText(raw.RightValueBoundString);
    if (left.length === 0 && right.length === 0) {
        return undefined;
    }

    const dataType: number | undefined = readDataType(refiner, raw);
    const formatBound = (bound: string, localized: unknown): string => {
        const amount: number | undefined = readNumber(bound);
        if (amount !== undefined && dataType === CURRENCY_DATA_TYPE) {
            return formatAmount(amount, formatPrice);
        }

        if (amount !== undefined && (dataType === DECIMAL_DATA_TYPE || kind === "rating")) {
            return withUnit(formatNumber(amount), raw.UnitText);
        }

        const localizedText: string = readText(localized);
        return localizedText.length > 0 ? localizedText : bound;
    };

    let label: string = left.length === 0
        ? `Under ${formatBound(right, raw.RightValueBoundLocalizedString)}`
        : right.length === 0
            ? `Over ${formatBound(left, raw.LeftValueBoundLocalizedString)}`
            : `${formatBound(left, raw.LeftValueBoundLocalizedString)}\u2013${formatBound(right, raw.RightValueBoundLocalizedString)}`;
    if (kind === "rating") {
        label = `${label} stars`;
    }

    return { key: `${normalize(left)}|${normalize(right)}`, label: label };
}

/**
 * Finds the value every product shown has in a row built from one of Commerce's other refiners,
 * which locks the row.
 *
 * That is the row's one value, or the one value the agent reported as applied, unless Commerce counted
 * fewer products with it than are shown.
 * @param kind What the row filters on.
 * @param label The row's label.
 * @param candidates The row's tags.
 * @param cardCount How many products are shown.
 * @param hints The filters the agent reported as applied.
 * @returns The key of the locked tag, or undefined when the row is not locked.
 */
function findRefinerLockedKey(
    kind: RefinerKind,
    label: string,
    candidates: IFacetCandidate[],
    cardCount: number,
    hints: IAgentProductFilter[]
): string | undefined {
    const someLackIt = (candidate: IFacetCandidate): boolean =>
        candidate.count !== undefined && candidate.count > 0 && candidate.count < cardCount;

    if (candidates.length === 1) {
        return someLackIt(candidates[0]) ? undefined : candidates[0].value.key;
    }

    const names: string[] = getRowNames(label, kind);
    const hinted: IFacetCandidate[] = [];
    hints.forEach((hint: IAgentProductFilter) => {
        if (!isHintForRow(hint.name, names)) {
            return;
        }

        const match: IFacetCandidate | undefined = findRefinerCandidate(kind, hint.value, candidates)
            ?? findRefinerCandidate(kind, stripRowName(names, hint.value), candidates)
            ?? findRefinerCandidate(kind, stripRowName(names, hint.label ?? ""), candidates);
        if (match && hinted.indexOf(match) < 0) {
            hinted.push(match);
        }
    });

    return hinted.length === 1 && !someLackIt(hinted[0]) ? hinted[0].value.key : undefined;
}

/**
 * Lists the names a filter on a row may have.
 * @param label The row's label.
 * @param kind What the row filters on.
 * @returns The label, and for a rating or a category the usual words for it.
 */
function getRowNames(label: string, kind: RefinerKind): string[] {
    const names: string[] = [label];
    if (kind === "rating") {
        names.push("ratings", "rating", "stars", "star");
    } else if (kind === "category") {
        names.push("categories", "category");
    }

    return names;
}

/**
 * Tells whether a filter the agent reported is on a row.
 * @param name The filter's name.
 * @param names The names the row may have.
 * @returns True when the name is one of them, ignoring case and spacing.
 */
function isHintForRow(name: string, names: string[]): boolean {
    const wanted: string = normalize(name);
    return wanted.length > 0 && names.some((rowName: string) => normalize(rowName) === wanted);
}

/**
 * Removes a row's name from the front of a filter's text, so "Brand: Contoso" reads "Contoso".
 * @param names The names the row may have.
 * @param text The text.
 * @returns The text without the first name it starts with, or the text unchanged.
 */
function stripRowName(names: string[], text: string): string {
    const tidied: string = readText(text);
    let stripped: string = tidied;
    names.forEach((name: string) => {
        if (stripped === tidied) {
            stripped = tidied.replace(new RegExp(`^${escapeRegExp(readText(name))}(\\s*[:\\-\\u2013]\\s*|\\s+)`, "i"), "");
        }
    });

    return stripped;
}

/**
 * Finds the tag a piece of text names in a row built from one of Commerce's other refiners.
 * @param kind What the row filters on.
 * @param text The text, such as a value the agent reported.
 * @param candidates The row's tags.
 * @returns The tag whose value or label the text is, ignoring case and spacing. For a rating, also the
 * tag for the text's number of stars, so "4 stars & up" finds "4 stars and up". Undefined when none is.
 */
function findRefinerCandidate(kind: RefinerKind, text: string, candidates: IFacetCandidate[]): IFacetCandidate | undefined {
    const wanted: string = normalize(text);
    if (wanted.length === 0) {
        return undefined;
    }

    const exact: IFacetCandidate | undefined = candidates.filter((candidate: IFacetCandidate) =>
        candidate.value.key === wanted || normalize(candidate.value.label) === wanted)[0];
    if (exact || kind !== "rating") {
        return exact;
    }

    const stars: number | undefined = readFirstNumber(wanted);
    return stars === undefined
        ? undefined
        : candidates.filter((candidate: IFacetCandidate) => readFirstNumber(candidate.value.key) === stars)[0];
}

/**
 * Gives a row built from one of Commerce's other refiners a key no other row has.
 * @param refiner The refiner.
 * @param kind What the row filters on.
 * @param usedKeys The keys of the rows built so far. The key is added to them.
 * @returns The refiner's record identifier with its source, such as "r1-5637144576", or, when it has
 * none, its kind and name. Numbered when another row has it already.
 */
function claimRefinerKey(refiner: IRefinerSource, kind: RefinerKind, usedKeys: { [key: string]: boolean }): string {
    const recordId: number | undefined = refiner.RecordId;
    const base: string = typeof recordId === "number" && isFinite(recordId) && recordId !== 0
        ? `r${readRefinerSource(refiner) ?? 0}-${recordId}`
        : `${kind}-${normalize(readText(refiner.KeyName)).replace(/ /g, "-")}`;

    let key: string = base;
    for (let suffix: number = 2; usedKeys[key] === true; suffix++) {
        key = `${base}-${suffix}`;
    }

    usedKeys[key] = true;
    return key;
}

/**
 * Reads the type of a refiner's values.
 * @param refiner The refiner.
 * @param raw One of its values.
 * @returns The refiner's AttributeDataType, else the value's, or undefined when neither has one.
 */
function readDataType(refiner: IRefinerSource, raw: IRefinerValueSource): number | undefined {
    if (typeof refiner.DataTypeValue === "number" && refiner.DataTypeValue > 0) {
        return refiner.DataTypeValue;
    }

    return typeof raw.DataTypeValue === "number" && raw.DataTypeValue > 0 ? raw.DataTypeValue : undefined;
}

/**
 * Formats an amount in the channel's currency.
 * @param amount The amount.
 * @param formatPrice Formats a price in the channel's currency.
 * @returns The amount without a zero fraction, such as "$50", or the bare number when it cannot be formatted.
 */
function formatAmount(amount: number, formatPrice: (price: number) => string): string {
    try {
        return trimZeroDecimals(formatPrice(amount));
    } catch {
        return formatNumber(amount);
    }
}

/**
 * Writes a number without needless digits.
 * @param value The number.
 * @returns The number rounded to at most four decimals, such as "4" or "10.5".
 */
function formatNumber(value: number): string {
    return String(Math.round(value * 10000) / 10000);
}

/**
 * Adds a unit to a number.
 * @param text The number.
 * @param unit The unit, such as "kg". Ignored unless it is text.
 * @returns The number and its unit, such as "10 kg", or the number alone.
 */
function withUnit(text: string, unit: unknown): string {
    const unitText: string = readText(unit);
    return unitText.length > 0 ? `${text} ${unitText}` : text;
}

/**
 * Reads a number Commerce wrote as text.
 * @param text The text, such as "4" or "10.5".
 * @returns The number, or undefined when the text is not a number.
 */
function readNumber(text: string): number | undefined {
    const value: number = Number(text);
    return text.length > 0 && isFinite(value) ? value : undefined;
}

/**
 * Reads the first number in a piece of text.
 * @param text The text, such as "4 stars and up".
 * @returns The number, or undefined when the text has none.
 */
function readFirstNumber(text: string): number | undefined {
    const match: RegExpExecArray | null = /\d+(\.\d+)?/.exec(text);
    return match ? Number(match[0]) : undefined;
}

/**
 * Makes text safe to match literally in a regular expression.
 * @param text The text.
 * @returns The text with the characters regular expressions treat specially escaped.
 */
function escapeRegExp(text: string): string {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Reduces a name to its lowercase letters, so names can be compared however they are written.
 * @param name The name.
 * @returns Its letters a to z, in lowercase, or an empty string when the name is not text.
 */
function toLetters(name: unknown): string {
    return typeof name === "string" ? name.toLowerCase().replace(/[^a-z]/g, "") : "";
}

/**
 * Gets a price step.
 * @param index Which step, from the smallest.
 * @returns The step.
 */
function getPriceStep(index: number): number {
    const cycle: number = Math.floor(index / PRICE_STEPS.length);
    return PRICE_STEPS[index % PRICE_STEPS.length] * Math.pow(1000, cycle);
}

/**
 * Lists the price ranges that have products in them.
 * @param prices The distinct prices.
 * @param step The width of each range.
 * @returns Each range's index, counted in steps from zero, lowest first.
 */
function getPriceBuckets(prices: number[], step: number): number[] {
    const buckets: number[] = [];
    prices.forEach((price: number) => {
        const bucket: number = Math.floor(price / step);
        if (buckets.indexOf(bucket) < 0) {
            buckets.push(bucket);
        }
    });

    return buckets.sort((first: number, second: number) => first - second);
}

/**
 * Finds the tag a piece of text names.
 * @param kind Which row the tag is in.
 * @param text The text, such as a variant's size or a value the agent reported.
 * @param candidates The row's tags.
 * @returns The tag whose value or label the text is, ignoring case and spacing. For a size, also
 * written another way, so "Medium" finds "M". Undefined when none is.
 */
function findCandidate(kind: DimensionKind, text: string, candidates: IFacetCandidate[]): IFacetCandidate | undefined {
    const wanted: string = normalize(text);
    if (wanted.length === 0) {
        return undefined;
    }

    const exact: IFacetCandidate | undefined = candidates.filter((candidate: IFacetCandidate) =>
        candidate.value.key === wanted || normalize(candidate.value.label) === wanted)[0];
    if (exact || kind !== "size") {
        return exact;
    }

    const size: string = getSizeSpelling(wanted);
    return candidates.filter((candidate: IFacetCandidate) =>
        getSizeSpelling(candidate.value.key) === size || getSizeSpelling(candidate.value.label) === size)[0];
}

/**
 * Removes a filter's name from the front of its text, so "Size: M" reads "M".
 * @param kind What the filter is on.
 * @param text The text.
 * @returns The text without the name, or the text unchanged when it does not start with the name.
 */
function stripFilterName(kind: DimensionKind, text: string): string {
    const pattern: RegExp = kind === "color" ? /^colou?rs?(\s*[:\-\u2013]\s*|\s+)/i : /^sizes?(\s*[:\-\u2013]\s*|\s+)/i;
    return readText(text).replace(pattern, "");
}

/**
 * Writes a size one way, so the ways it is written can be compared.
 * @param text The size.
 * @returns The size's one spelling, such as "m" for "Medium", or the size in lowercase without
 * spaces or hyphens when it is not one of the common sizes.
 */
function getSizeSpelling(text: string): string {
    const compact: string = text.toLowerCase().replace(/[^a-z0-9.]/g, "");
    return Object.prototype.hasOwnProperty.call(SIZE_SPELLINGS, compact) ? SIZE_SPELLINGS[compact] : compact;
}

/**
 * Reads the filters the agent reported as applied to every product it shows.
 * @param filters The filters the agent sent. Anything other than an array is ignored.
 * @returns At most {@link MAX_AGENT_FILTERS} usable filters, in the agent's order.
 */
function getAppliedHints(filters: unknown): IAgentProductFilter[] {
    const hints: IAgentProductFilter[] = [];
    if (!Array.isArray(filters)) {
        return hints;
    }

    filters.forEach((entry: unknown) => {
        const filter: IAgentProductFilter | undefined = readFilter(entry);
        if (filter && filter.applied && hints.length < MAX_AGENT_FILTERS) {
            hints.push(filter);
        }
    });

    return hints;
}

/**
 * Reads one filter the agent reported.
 * @param entry One entry the agent sent.
 * @returns The filter with its text tidied, or undefined when it has no usable name or value.
 */
function readFilter(entry: unknown): IAgentProductFilter | undefined {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
        return undefined;
    }

    const candidate = entry as { name?: unknown; value?: unknown; label?: unknown; applied?: unknown };
    const name: string = readText(candidate.name);
    const value: string = typeof candidate.value === "number" && isFinite(candidate.value)
        ? String(candidate.value)
        : readText(candidate.value);
    if (name.length === 0 || name.length > MAX_FILTER_TEXT_LENGTH
        || value.length === 0 || value.length > MAX_FILTER_TEXT_LENGTH) {
        return undefined;
    }

    const filter: IAgentProductFilter = { name: name, value: value };
    const label: string = readText(candidate.label);
    if (label.length > 0 && label.length <= MAX_FILTER_TEXT_LENGTH && label !== value) {
        filter.label = label;
    }

    if (candidate.applied === true) {
        filter.applied = true;
    }

    return filter;
}

/**
 * Reads a swatch colour as a CSS colour.
 * @param code The hex code Commerce has for the colour, with or without "#".
 * @returns The colour, such as "#1A2B3C", or undefined when the code is not three or six hex digits.
 */
function readSwatchColor(code: unknown): string | undefined {
    if (typeof code !== "string") {
        return undefined;
    }

    const digits: string = code.trim().replace(/^(#|0x)/i, "");
    return /^([0-9a-f]{3}|[0-9a-f]{6})$/i.test(digits) ? `#${digits.toUpperCase()}` : undefined;
}

/**
 * Reads a piece of text, with runs of whitespace, including line breaks, made single spaces.
 * @param value The value.
 * @returns The text, or an empty string when the value is not text.
 */
function readText(value: unknown): string {
    return typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
}

/**
 * Writes text the way two values are compared: tidied and in lowercase.
 * @param text The text.
 * @returns The compared form.
 */
function normalize(text: string): string {
    return readText(text).toLowerCase();
}

/**
 * Keeps tag text short enough for a tag.
 * @param text The text.
 * @returns The text, cut with an ellipsis when longer than {@link MAX_FILTER_TEXT_LENGTH}.
 */
function limitText(text: string): string {
    return text.length > MAX_FILTER_TEXT_LENGTH ? `${text.substring(0, MAX_FILTER_TEXT_LENGTH - 1)}\u2026` : text;
}
