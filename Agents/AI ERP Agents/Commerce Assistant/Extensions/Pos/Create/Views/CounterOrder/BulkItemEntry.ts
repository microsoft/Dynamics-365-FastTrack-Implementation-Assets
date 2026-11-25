/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Finds the products in a pasted item list and adds them to the cart the way the POS bulk item entry dialog
 * does, with the same messages.
 *
 * Finding looks up each item ID in the store's catalog, eight at a time, and accepts a product only when its
 * item ID is exactly the one entered. Adding asks the associate to choose the options of each product master,
 * one at a time, then adds every line in one add-to-cart operation. When that operation fails, each line is
 * tried on its own so one bad line doesn't stop the rest. When the associate cancels it, nothing is retried.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { AddItemToCartOperationRequest, AddItemToCartOperationResponse } from "PosApi/Consume/Cart";
import { GetChannelConfigurationClientRequest, GetChannelConfigurationClientResponse } from "PosApi/Consume/Device";
import {
    GetCurrentProductCatalogStoreClientRequest,
    GetCurrentProductCatalogStoreClientResponse,
    GetProductsByIdsClientRequest,
    GetProductsByIdsClientResponse,
    SelectProductVariantClientRequest,
    SelectProductVariantClientResponse
} from "PosApi/Consume/Products";
import { SearchByTextRequest, SearchByTextResponse } from "../../../Extend/Agent/OobRetailServerRequests";
import { IBulkLineParseError, IBulkLineParseResult, IBulkParseResult, parseBulkItemInput } from "./BulkItemParser";

/** The most item lines one bulk add takes, as in POS. */
export const MAX_BULK_ITEM_LINES: number = 100;

/** The most characters the item list takes, as in POS. */
export const MAX_BULK_ITEM_TEXT_LENGTH: number = 8000;

/** How many item IDs are looked up at once. */
const MAX_CONCURRENT_LOOKUPS: number = 8;

/**
 * How many products a lookup returns. A short item ID such as "100" also matches "1001", "1002" and so on, so
 * the page is large enough to hold the exact match among them.
 */
const SEARCH_PAGE_SIZE: number = 25;

/** Shown when Commerce gives no reason a line failed. */
const GENERIC_ADD_FAILURE: string = "Unable to add this item to the cart";

/**
 * Why a line can't be added, as the POS dialog shows it.
 */
export interface IBulkLineError {
    /** The item ID the error is about, or an empty string when the line couldn't be read. */
    readonly sku: string;
    /** The message to show. */
    readonly message: string;
    /** The line in the list (1-based, not counting blank lines or a header), or 0 for the whole list. */
    readonly lineNumber: number;
    /** The whole line as entered. */
    readonly rawLine: string;
    /** Just the failing item ID and quantity, so the list can be rebuilt with only what still needs attention. */
    readonly pairText?: string;
    /** Set when the associate chose not to add the item, rather than it failing: in the variant picker, or by declining the add. */
    readonly cancellation?: "variant" | "add";
}

/**
 * A line of the list and the one product it matched.
 */
export interface IIdentifiedLine {
    readonly parseLine: IBulkLineParseResult;
    readonly product: ProxyEntities.SimpleProduct;
    /** The line as written on a photo, when it doesn't show the item ID, so the associate can check the match. */
    readonly readAs?: string;
}

/** Why a line read from a photo can't be added as written. */
export type PhotoLineProblem = "unreadable" | "noQuantity" | "notFound" | "ambiguous";

/**
 * A line of an item list read from a photo: the line as written, and the item ID and quantity on it, or why it
 * can't be added as written.
 */
export interface IPhotoItemLine {
    /** The line as written, on one line. */
    readonly text: string;
    /** The item ID written on the line, or the one found for a line without one. */
    readonly itemId?: string;
    /** The exact product or variant found for the line. Used only when its item ID is itemId. */
    readonly productId?: number;
    /** The quantity written on the line: a whole number from 1 to MAX_BULK_QUANTITY. */
    readonly quantity?: number;
    /** Why the line can't be added as written. */
    readonly problem?: PhotoLineProblem;
}

/**
 * What finding the products in a list came to.
 */
export interface IFindItemsResult {
    /** The item ID and quantity pairs plus the lines that couldn't be read. */
    readonly totalLines: number;
    /** The pairs that matched exactly one product, in list order. */
    readonly identified: IIdentifiedLine[];
    /** Why the other lines can't be added: lines that couldn't be read first, then item IDs that didn't match. */
    readonly errors: IBulkLineError[];
    /** True when the list has more than MAX_BULK_ITEM_LINES pairs, so nothing was looked up. */
    readonly tooManyLines: boolean;
}

/**
 * What adding the found products to the cart came to.
 */
export interface IAddItemsResult {
    /** How many lines were added. */
    readonly addedCount: number;
    /** The lines that weren't added and why, including the ones the associate cancelled. */
    readonly errors: IBulkLineError[];
}

/** Why an item ID didn't resolve to one product. */
type ResolveFailure = "notFound" | "ambiguous" | "error";

/** An item ID's product, or why it has none. */
interface IResolution {
    readonly product?: ProxyEntities.SimpleProduct;
    readonly failure?: ResolveFailure;
    readonly underlyingError?: unknown;
}

/** The record ID a lookup found for an item ID, or why it found none. */
interface ISearchOutcome {
    readonly recordId?: number;
    readonly failure?: ResolveFailure;
    readonly underlyingError?: unknown;
}

/** The products fetched by record ID, and whether fetching them was cancelled. */
interface IInflateOutcome {
    readonly canceled: boolean;
    readonly productsById: { [recordId: number]: ProxyEntities.SimpleProduct };
}

/** The variant the associate chose for a product master, or why there is none. */
interface IVariantOutcome {
    readonly kind: "selected" | "cancelled" | "failed";
    readonly variant?: ProxyEntities.SimpleProduct;
}

/** How an add-to-cart operation ended. */
interface IAddOutcome {
    readonly outcome: "added" | "cancelled" | "error";
    readonly error?: unknown;
}

/**
 * Finds the product for each item ID in a list.
 * @param context The extension context.
 * @param rawText The list as entered or pasted.
 * @param correlationId The correlation identifier for logging.
 * @returns The lines that matched a product, and why the others didn't.
 */
export async function findItemsAsync(context: IExtensionContext, rawText: string, correlationId: string): Promise<IFindItemsResult> {
    const parseResult: IBulkParseResult = parseBulkItemInput(rawText);
    const totalLines: number = parseResult.lines.length + parseResult.errors.length;
    const parseErrors: IBulkLineError[] = parseResult.errors.map(createParseError);

    // Bounds the lookups and the add before anything is sent, as POS does; the associate trims the list and retries.
    if (parseResult.lines.length > MAX_BULK_ITEM_LINES) {
        return { totalLines: totalLines, identified: [], errors: [createTooManyLinesError()], tooManyLines: true };
    }

    if (parseResult.lines.length === 0) {
        return { totalLines: totalLines, identified: [], errors: parseErrors, tooManyLines: false };
    }

    const resolutions: IResolution[] = await resolveLinesAsync(context, parseResult.lines, correlationId);
    const identified: IIdentifiedLine[] = [];
    const resolveErrors: IBulkLineError[] = [];
    parseResult.lines.forEach((parseLine: IBulkLineParseResult, index: number): void => {
        const resolution: IResolution = resolutions[index];
        if (resolution && resolution.product) {
            identified.push({ parseLine: parseLine, product: resolution.product });
        } else {
            resolveErrors.push(createResolveError(parseLine, resolution));
        }
    });

    return { totalLines: totalLines, identified: identified, errors: parseErrors.concat(resolveErrors), tooManyLines: false };
}

/**
 * Finds the product for each line of an item list read from a photo. Each item ID is looked up exactly, as for a
 * pasted list. A product found for the line by record ID is used instead when its item ID is the line's.
 * @param context The extension context.
 * @param lines The lines read from the photo, in the order written.
 * @param correlationId The correlation identifier for logging.
 * @returns The lines that matched a product, and why the others didn't, in the order written.
 */
export async function findPhotoItemsAsync(
    context: IExtensionContext,
    lines: ReadonlyArray<IPhotoItemLine>,
    correlationId: string
): Promise<IFindItemsResult> {
    const totalLines: number = lines.length;
    if (lines.length > MAX_BULK_ITEM_LINES) {
        return { totalLines: totalLines, identified: [], errors: [createTooManyLinesError()], tooManyLines: true };
    }

    const pairs: IBulkLineParseResult[] = [];
    const pairLines: IPhotoItemLine[] = [];
    const lineErrors: IBulkLineError[] = [];
    lines.forEach((line: IPhotoItemLine, index: number): void => {
        const lineNumber: number = index + 1;
        if (canLookUpPhotoLine(line)) {
            pairs.push({ lineNumber: lineNumber, rawText: line.text, sku: line.itemId, quantity: line.quantity });
            pairLines.push(line);
        } else {
            lineErrors.push(createPhotoLineError(line, lineNumber));
        }
    });

    if (pairs.length === 0) {
        return { totalLines: totalLines, identified: [], errors: lineErrors, tooManyLines: false };
    }

    const productIds: Array<number | undefined> = pairLines.map((line: IPhotoItemLine): number | undefined => line.productId);
    const resolutions: IResolution[] = await resolvePhotoPairsAsync(context, pairs, productIds, correlationId);
    const identified: IIdentifiedLine[] = [];
    const errors: IBulkLineError[] = lineErrors.slice();
    pairs.forEach((parseLine: IBulkLineParseResult, index: number): void => {
        const resolution: IResolution = resolutions[index];
        if (resolution && resolution.product) {
            identified.push({ parseLine: parseLine, product: resolution.product, readAs: describeReadAs(pairLines[index]) });
        } else {
            errors.push(createResolveError(parseLine, resolution));
        }
    });

    errors.sort((first: IBulkLineError, second: IBulkLineError): number => first.lineNumber - second.lineNumber);
    return { totalLines: totalLines, identified: identified, errors: errors, tooManyLines: false };
}

/**
 * Adds found lines to the cart. The associate chooses the options of each product master first, one at a time.
 * @param context The extension context.
 * @param lines The lines to add.
 * @param correlationId The correlation identifier for logging.
 * @returns How many lines were added, and why the others weren't.
 */
export async function addIdentifiedLinesAsync(
    context: IExtensionContext,
    lines: ReadonlyArray<IIdentifiedLine>,
    correlationId: string
): Promise<IAddItemsResult> {
    const directLines: IIdentifiedLine[] = [];
    const masterLines: IIdentifiedLine[] = [];
    lines.forEach((line: IIdentifiedLine): void => {
        if (requiresVariantSelection(line.product)) {
            masterLines.push(line);
        } else {
            directLines.push(line);
        }
    });

    const errors: IBulkLineError[] = [];
    const selectedLines: IIdentifiedLine[] = [];
    for (const line of masterLines) {
        const selection: IVariantOutcome = await selectVariantAsync(context, line.product, correlationId);
        if (selection.kind === "selected") {
            selectedLines.push({ parseLine: line.parseLine, product: selection.variant });
        } else if (selection.kind === "failed") {
            errors.push(createPairError(line.parseLine, `${line.parseLine.sku} was not added because variant selection failed`));
        } else {
            errors.push(createPairError(line.parseLine, `${line.parseLine.sku} was not added as the variant was not selected`, "variant"));
        }
    }

    const addLines: IIdentifiedLine[] = directLines.concat(selectedLines);
    if (addLines.length === 0) {
        return { addedCount: 0, errors: errors };
    }

    const catalogId: number = await getCatalogIdAsync(context, correlationId);
    const batch: IAddOutcome = await tryAddLinesAsync(context, addLines, catalogId, correlationId);
    if (batch.outcome === "added") {
        return { addedCount: addLines.length, errors: errors };
    }

    // The associate declined the add, for example an age confirmation, so nothing is added behind their back.
    if (batch.outcome === "cancelled") {
        addLines.forEach((line: IIdentifiedLine): void => {
            errors.push(createAddCancelledError(line.parseLine));
        });
        return { addedCount: 0, errors: errors };
    }

    // The operation failed before it added anything, so each line is tried on its own and only the bad ones stay.
    const failedErrors: IBulkLineError[] = [];
    const cancelledErrors: IBulkLineError[] = [];
    for (const line of addLines) {
        const single: IAddOutcome = await tryAddLinesAsync(context, [line], catalogId, correlationId);
        if (single.outcome === "cancelled") {
            cancelledErrors.push(createAddCancelledError(line.parseLine));
        } else if (single.outcome === "error") {
            failedErrors.push(createPairError(line.parseLine, `${line.parseLine.sku}: ${describeError(single.error) || GENERIC_ADD_FAILURE}`));
        }
    }

    return {
        addedCount: addLines.length - failedErrors.length - cancelledErrors.length,
        errors: errors.concat(failedErrors, cancelledErrors)
    };
}

/**
 * Rebuilds the list with only the lines that still have errors, so lines already added can't be added twice.
 * A line with several pairs keeps only its failing pairs, one per line; a line that couldn't be read stays as it was.
 * @param errors The errors from the last run.
 * @returns The list to show.
 */
export function buildRemainingText(errors: ReadonlyArray<IBulkLineError>): string {
    const lineNumbers: number[] = [];
    const errorsByLine: { [lineNumber: number]: IBulkLineError[] } = {};
    errors.forEach((error: IBulkLineError): void => {
        if (!errorsByLine[error.lineNumber]) {
            errorsByLine[error.lineNumber] = [];
            lineNumbers.push(error.lineNumber);
        }

        errorsByLine[error.lineNumber].push(error);
    });

    const output: string[] = [];
    lineNumbers
        .sort((first: number, second: number): number => first - second)
        .forEach((lineNumber: number): void => {
            const lineErrors: IBulkLineError[] = errorsByLine[lineNumber];
            const failedPairs: string[] = lineErrors
                .map((error: IBulkLineError): string | undefined => error.pairText)
                .filter((pairText: string | undefined): boolean => pairText !== undefined);

            if (failedPairs.length > 0) {
                output.push(...failedPairs);
            } else {
                output.push(lineErrors[0].rawLine);
            }
        });

    return output.join("\n");
}

/**
 * Writes an item list read from a photo as a list the associate can edit: each item ID and quantity, one per line,
 * in the order written. A line without both is written as it was read.
 * @param lines The lines read from the photo.
 * @returns The list.
 */
export function buildPhotoListText(lines: ReadonlyArray<IPhotoItemLine>): string {
    return lines.map(describePhotoLinePair).join("\n");
}

/**
 * Counts the item ID and quantity pairs in a list.
 * @param rawText The list.
 * @returns The number of pairs that can be added.
 */
export function countValidLines(rawText: string): number {
    return parseBulkItemInput(rawText).lines.length;
}

/**
 * Says how many lines a list will add, as the POS dialog does above its list.
 * @param count The number of pairs.
 * @returns The text.
 */
export function formatLineCount(count: number): string {
    if (count === 0) {
        return "No lines to add yet";
    }

    return count === 1 ? "1 line to add" : `${count} lines to add`;
}

/**
 * Says how many lines were added, as the POS dialog does once they're in the cart.
 * @param count The number of lines.
 * @returns The text.
 */
export function formatAddedCount(count: number): string {
    return count === 1 ? "1 line added to transaction" : `${count} lines added to transaction`;
}

/**
 * What the POS bulk item entry dialog says in a toast once it closes.
 */
export interface IBulkAddToast {
    readonly title: string;
    readonly body?: string;
    /** "success" when every line was added, "error" when lines failed and none were added, otherwise "info". */
    readonly kind: "success" | "info" | "error";
}

/**
 * Says how adding the items went, as the POS bulk item entry dialog does in a toast once it closes.
 * @param addedCount The lines added since the dialog opened.
 * @param errors The lines the last add left out: ones that couldn't be read, found or added, and ones the associate cancelled.
 * @returns The toast, or undefined when there is nothing to report.
 */
export function describeAddToast(addedCount: number, errors: ReadonlyArray<IBulkLineError>): IBulkAddToast | undefined {
    if (addedCount + errors.length === 0) {
        return undefined;
    }

    const variantCancelledSkus: string[] = [];
    let addCancelledCount: number = 0;
    errors.forEach((error: IBulkLineError): void => {
        if (error.cancellation === "variant") {
            variantCancelledSkus.push(error.sku);
        } else if (error.cancellation === "add") {
            addCancelledCount++;
        }
    });

    // A cancellation is the associate's choice, so only the rest count as failures.
    const failedCount: number = errors.length - variantCancelledSkus.length - addCancelledCount;
    if (failedCount === 0) {
        if (variantCancelledSkus.length === 0 && addCancelledCount === 0) {
            return { title: addedCount === 1 ? "1 line added to cart" : `${addedCount} lines added to cart`, kind: "success" };
        }

        if (addCancelledCount === 0) {
            const skus: string = variantCancelledSkus.join(", ");
            return {
                title: variantCancelledSkus.length === 1
                    ? `${skus} was not added as the variant was not selected`
                    : `${skus} were not added as variants were not selected`,
                kind: "info"
            };
        }

        return { title: addedCount === 0 ? "Lines not added to transaction" : formatAddedCount(addedCount), kind: "info" };
    }

    const body: string = failedCount === 1
        ? "1 line could not be added to the transaction"
        : `${failedCount} lines could not be added to the transaction due to errors`;
    if (addedCount === 0) {
        return { title: "Lines not added to transaction", body: body, kind: "error" };
    }

    return { title: formatAddedCount(addedCount), body: body, kind: "info" };
}

/**
 * Reads the reason out of whatever POS or Commerce rejected with.
 * @param error The rejection.
 * @returns The reason, or an empty string when there is none.
 */
export function describeError(error: unknown): string {
    const first: unknown = Array.isArray(error) ? error[0] : error;
    if (typeof first === "string") {
        return first.trim();
    }

    if (first && typeof first === "object") {
        const fields: { [name: string]: unknown } = first as { [name: string]: unknown };
        const names: string[] = [
            "localizedMessage",
            "LocalizedMessage",
            "ErrorLocalizedMessage",
            "ExternalLocalizedErrorMessage",
            "formattedMessage",
            "ErrorMessage",
            "message",
            "ErrorCode"
        ];
        for (const name of names) {
            const value: unknown = fields[name];
            if (typeof value === "string" && value.trim().length > 0) {
                return value.trim();
            }
        }
    }

    return "";
}

/**
 * Looks up the product for each line, keeping the lines' order. When the lookups can't run at all, every line
 * fails with the general message, as in POS.
 */
async function resolveLinesAsync(
    context: IExtensionContext,
    lines: ReadonlyArray<IBulkLineParseResult>,
    correlationId: string
): Promise<IResolution[]> {
    const skus: string[] = lines.map((line: IBulkLineParseResult): string => line.sku);
    try {
        return await resolveSkusAsync(context, skus, correlationId);
    } catch (error) {
        context.logger.logWarning(`Counter order: looking up ${skus.length} item IDs failed. ${describeError(error)}`, correlationId);
        return skus.map((): IResolution => ({ failure: "error" }));
    }
}

/**
 * Looks up the product for each pair read from a photo, keeping their order. A pair whose line names a product by
 * record ID gets that product when its item ID is the pair's; the rest are looked up by item ID, as typed ones are.
 */
async function resolvePhotoPairsAsync(
    context: IExtensionContext,
    pairs: ReadonlyArray<IBulkLineParseResult>,
    productIds: ReadonlyArray<number | undefined>,
    correlationId: string
): Promise<IResolution[]> {
    const recordIds: number[] = [];
    productIds.forEach((productId: number | undefined): void => {
        if (isRecordId(productId) && recordIds.indexOf(productId) < 0) {
            recordIds.push(productId);
        }
    });

    let named: { [recordId: number]: ProxyEntities.SimpleProduct } = {};
    if (recordIds.length > 0) {
        try {
            named = (await getProductsByIdsAsync(context, recordIds, correlationId)).productsById;
        } catch (error) {
            // Their item IDs are looked up instead.
            context.logger.logWarning(
                `Counter order: fetching ${recordIds.length} products read from a photo failed. ${describeError(error)}`, correlationId);
        }
    }

    const resolutions: IResolution[] = [];
    const searchPairs: IBulkLineParseResult[] = [];
    const searchIndexes: number[] = [];
    pairs.forEach((pair: IBulkLineParseResult, index: number): void => {
        const productId: number | undefined = productIds[index];
        const product: ProxyEntities.SimpleProduct | undefined = isRecordId(productId) ? named[productId] : undefined;

        // As for a typed item ID, only a product with the item ID on the line is accepted.
        if (product && itemIdMatchesSku(product.ItemId, pair.sku)) {
            resolutions[index] = { product: product };
        } else {
            searchIndexes.push(index);
            searchPairs.push(pair);
        }
    });

    if (searchPairs.length > 0) {
        const searched: IResolution[] = await resolveLinesAsync(context, searchPairs, correlationId);
        searchIndexes.forEach((pairIndex: number, position: number): void => {
            resolutions[pairIndex] = searched[position];
        });
    }

    return resolutions;
}

async function resolveSkusAsync(context: IExtensionContext, skus: ReadonlyArray<string>, correlationId: string): Promise<IResolution[]> {
    const channelId: number = await getChannelIdAsync(context, correlationId);
    const catalogId: number = await getCatalogIdAsync(context, correlationId);

    // Lookups run eight at a time; each one writes to its own slot so the results keep the list's order.
    const searches: ISearchOutcome[] = [];
    let nextIndex: number = 0;
    const runWorkerAsync = async (): Promise<void> => {
        while (nextIndex < skus.length) {
            const index: number = nextIndex++;
            searches[index] = await searchSkuAsync(context, skus[index], channelId, catalogId, correlationId);
        }
    };

    const workers: Promise<void>[] = [];
    const workerCount: number = Math.min(MAX_CONCURRENT_LOOKUPS, skus.length);
    for (let worker: number = 0; worker < workerCount; worker++) {
        workers.push(runWorkerAsync());
    }

    await Promise.all(workers);

    // Fetches the full products, which say whether options must be chosen and are what the cart takes.
    const recordIds: number[] = [];
    searches.forEach((search: ISearchOutcome): void => {
        if (search && typeof search.recordId === "number") {
            recordIds.push(search.recordId);
        }
    });

    const inflated: IInflateOutcome = recordIds.length === 0
        ? { canceled: false, productsById: {} }
        : await getProductsByIdsAsync(context, recordIds, correlationId);

    return skus.map((sku: string, index: number): IResolution => {
        const search: ISearchOutcome | undefined = searches[index];
        if (!search) {
            return { failure: "error" };
        }

        if (search.failure) {
            return { failure: search.failure, underlyingError: search.underlyingError };
        }

        const product: ProxyEntities.SimpleProduct | undefined = inflated.productsById[search.recordId];
        if (!product) {
            // A cancelled fetch lost the product for reasons that have nothing to do with the item ID.
            return { failure: inflated.canceled ? "error" : "notFound" };
        }

        // Only the item ID the associate entered is accepted, so a bulk add never adds the wrong item.
        return itemIdMatchesSku(product.ItemId, sku) ? { product: product } : { failure: "notFound" };
    });
}

/**
 * Looks up one item ID in the store's catalog.
 */
async function searchSkuAsync(
    context: IExtensionContext,
    sku: string,
    channelId: number,
    catalogId: number,
    correlationId: string
): Promise<ISearchOutcome> {
    try {
        const result: ClientEntities.ICancelableDataResult<SearchByTextResponse> = await context.runtime.executeAsync(
            new SearchByTextRequest<SearchByTextResponse>(correlationId, channelId, catalogId, sku, SEARCH_PAGE_SIZE));

        if (result.canceled) {
            return { failure: "error" };
        }

        const matches: ProxyEntities.ProductSearchResult[] = (result.data && result.data.result) || [];
        if (matches.length === 0) {
            return { failure: "notFound" };
        }

        if (matches.length > 1) {
            // "100" also matches "1001"; when exactly one product has the item ID entered, it's the one.
            const exact: ProxyEntities.ProductSearchResult[] = matches.filter(
                (match: ProxyEntities.ProductSearchResult): boolean => itemIdMatchesSku(match.ItemId, sku));
            return exact.length === 1 ? { recordId: exact[0].RecordId } : { failure: "ambiguous" };
        }

        return itemIdMatchesSku(matches[0].ItemId, sku) ? { recordId: matches[0].RecordId } : { failure: "notFound" };
    } catch (error) {
        return { failure: "error", underlyingError: error };
    }
}

async function getProductsByIdsAsync(context: IExtensionContext, recordIds: number[], correlationId: string): Promise<IInflateOutcome> {
    const result: ClientEntities.ICancelableDataResult<GetProductsByIdsClientResponse> = await context.runtime.executeAsync(
        new GetProductsByIdsClientRequest<GetProductsByIdsClientResponse>(recordIds, correlationId));

    const productsById: { [recordId: number]: ProxyEntities.SimpleProduct } = {};
    if (result.canceled || !result.data) {
        return { canceled: true, productsById: productsById };
    }

    const products: ProxyEntities.SimpleProduct[] = result.data.result || result.data.products || [];
    products.forEach((product: ProxyEntities.SimpleProduct): void => {
        if (product && typeof product.RecordId === "number") {
            productsById[product.RecordId] = product;
        }
    });

    return { canceled: false, productsById: productsById };
}

/** The store the products are looked up in. */
async function getChannelIdAsync(context: IExtensionContext, correlationId: string): Promise<number> {
    const result: ClientEntities.ICancelableDataResult<GetChannelConfigurationClientResponse> = await context.runtime.executeAsync(
        new GetChannelConfigurationClientRequest<GetChannelConfigurationClientResponse>(correlationId));

    const channelId: number | undefined = !result.canceled && result.data && result.data.result ? result.data.result.RecordId : undefined;
    if (typeof channelId !== "number") {
        throw new Error("POS didn't say which store this is.");
    }

    return channelId;
}

/** The catalog the store sells from, or 0 for its whole assortment, as POS falls back to. */
async function getCatalogIdAsync(context: IExtensionContext, correlationId: string): Promise<number> {
    try {
        const result: ClientEntities.ICancelableDataResult<GetCurrentProductCatalogStoreClientResponse> = await context.runtime.executeAsync(
            new GetCurrentProductCatalogStoreClientRequest<GetCurrentProductCatalogStoreClientResponse>(correlationId));

        const catalogId: number | undefined = !result.canceled && result.data && result.data.context ? result.data.context.CatalogId : undefined;
        return typeof catalogId === "number" ? catalogId : 0;
    } catch (error) {
        context.logger.logWarning(`Counter order: POS didn't say which catalog the store uses. ${describeError(error)}`, correlationId);
        return 0;
    }
}

/** Asks the associate to choose the options of a product master in the POS variant picker. */
async function selectVariantAsync(context: IExtensionContext, master: ProxyEntities.SimpleProduct, correlationId: string): Promise<IVariantOutcome> {
    try {
        const result: ClientEntities.ICancelableDataResult<SelectProductVariantClientResponse> = await context.runtime.executeAsync(
            new SelectProductVariantClientRequest<SelectProductVariantClientResponse>(master, undefined, correlationId));

        if (result.canceled) {
            return { kind: "cancelled" };
        }

        const variant: ProxyEntities.SimpleProduct | undefined = result.data ? result.data.result : undefined;
        return variant ? { kind: "selected", variant: variant } : { kind: "failed" };
    } catch (error) {
        context.logger.logWarning(`Counter order: choosing the options of ${master.ItemId} failed. ${describeError(error)}`, correlationId);
        return { kind: "failed" };
    }
}

/** Adds lines to the cart in one add-to-cart operation, as POS does. */
async function tryAddLinesAsync(
    context: IExtensionContext,
    lines: ReadonlyArray<IIdentifiedLine>,
    catalogId: number,
    correlationId: string
): Promise<IAddOutcome> {
    const details: ClientEntities.IProductSaleReturnDetails[] = lines.map(
        (line: IIdentifiedLine): ClientEntities.IProductSaleReturnDetails => ({
            product: line.product,
            quantity: line.parseLine.quantity,
            catalogId: catalogId
        }));

    try {
        const result: ClientEntities.ICancelableDataResult<AddItemToCartOperationResponse> = await context.runtime.executeAsync(
            new AddItemToCartOperationRequest<AddItemToCartOperationResponse>(details, correlationId));
        return { outcome: result.canceled ? "cancelled" : "added" };
    } catch (error) {
        context.logger.logWarning(`Counter order: adding ${lines.length} lines to the cart failed. ${describeError(error)}`, correlationId);
        return { outcome: "error", error: error };
    }
}

/**
 * Says whether the associate chooses a product's options, such as size and colour, as it's added.
 * @param product The product.
 * @returns True for a product master or kit master.
 */
export function requiresVariantSelection(product: ProxyEntities.SimpleProduct): boolean {
    return product.ProductTypeValue === ProxyEntities.ProductType.Master
        || product.ProductTypeValue === ProxyEntities.ProductType.KitMaster;
}

function itemIdMatchesSku(itemId: string | undefined, sku: string): boolean {
    return (itemId || "").trim().toLowerCase() === sku.trim().toLowerCase();
}

function createParseError(error: IBulkLineParseError): IBulkLineError {
    const sku: string = error.sku || "";
    const token: string = sku || error.rawText;
    let message: string;
    switch (error.kind) {
        case "quantityLessThanOne":
            message = `${token}: Enter quantity greater than or equal to 1`;
            break;
        case "multiPairDelimiter":
            message = "Please enter one SKU/Qty pair on every line";
            break;
        case "integerSkuRequiresXQty":
            message = `${token}: Please enter in SKU xQty format only for integer SKU IDs`;
            break;
        case "noQuantityFound":
            message = `${token}: Enter a SKU and a quantity, for example ABC 5`;
            break;
        case "pairDelimiterMisuse":
            message = `${token}: Put a space between the SKU and quantity; use ${error.delimiter || ""} only between items`;
            break;
        default:
            message = `${token}: Unable to parse this line`;
            break;
    }

    return {
        sku: sku,
        message: message,
        lineNumber: error.lineNumber,
        rawLine: error.rawText,
        pairText: error.pairText !== undefined ? error.pairText : error.rawText
    };
}

function createResolveError(parseLine: IBulkLineParseResult, resolution: IResolution | undefined): IBulkLineError {
    const failure: ResolveFailure = resolution && resolution.failure ? resolution.failure : "error";
    let message: string;
    if (failure === "notFound") {
        message = `${parseLine.sku}: SKU not found`;
    } else if (failure === "ambiguous") {
        message = `${parseLine.sku}: Multiple products match this SKU. Please enter a more specific SKU.`;
    } else {
        message = `${parseLine.sku}: ${describeError(resolution ? resolution.underlyingError : undefined) || GENERIC_ADD_FAILURE}`;
    }

    return createPairError(parseLine, message);
}

function createAddCancelledError(parseLine: IBulkLineParseResult): IBulkLineError {
    return createPairError(parseLine, `${parseLine.sku} was not added because the add was cancelled`, "add");
}

function createPairError(parseLine: IBulkLineParseResult, message: string, cancellation?: "variant" | "add"): IBulkLineError {
    return {
        sku: parseLine.sku,
        message: message,
        lineNumber: parseLine.lineNumber,
        rawLine: parseLine.rawText,
        pairText: `${parseLine.sku} ${parseLine.quantity}`,
        cancellation: cancellation
    };
}

function createTooManyLinesError(): IBulkLineError {
    return {
        sku: "",
        message: `You can add up to ${MAX_BULK_ITEM_LINES} lines at a time. Remove some lines and try again.`,
        lineNumber: 0,
        rawLine: ""
    };
}

/** The most characters of a line read from a photo that its error shows. */
const MAX_LINE_LABEL_LENGTH: number = 40;

/** Says whether a line read from a photo has an item ID and a quantity that can be looked up. */
function canLookUpPhotoLine(line: IPhotoItemLine): boolean {
    // A line that couldn't be read, or has no quantity written, is never added on a guess.
    return line.problem !== "unreadable"
        && line.problem !== "noQuantity"
        && !!line.itemId
        && typeof line.quantity === "number";
}

function createPhotoLineError(line: IPhotoItemLine, lineNumber: number): IBulkLineError {
    const label: string = shortenLineText(line.text);
    const itemId: string = line.itemId || "";
    let message: string;
    if (line.problem === "unreadable") {
        message = `${label}: Unable to read this line from the photo`;
    } else if (itemId.length === 0) {
        message = line.problem === "ambiguous"
            ? `${label}: More than one product matches this line. Enter its item ID.`
            : `${label}: No item ID found for this line`;
    } else {
        // The same message as a typed item ID without a quantity.
        message = `${itemId}: Enter a SKU and a quantity, for example ABC 5`;
    }

    return {
        sku: itemId,
        message: message,
        lineNumber: lineNumber,
        rawLine: line.text,
        pairText: describePhotoLinePair(line)
    };
}

/** Writes a line read from a photo as its item ID and quantity, as much of them as can be added, or as it was read. */
function describePhotoLinePair(line: IPhotoItemLine): string {
    const itemId: string = line.itemId || "";
    if (line.problem === "unreadable" || itemId.length === 0) {
        return line.text.replace(/\s+/g, " ").trim();
    }

    return line.problem === "noQuantity" || typeof line.quantity !== "number" ? itemId : `${itemId} ${line.quantity}`;
}

/** The line as written, when it doesn't show the item ID it was matched by. */
function describeReadAs(line: IPhotoItemLine): string | undefined {
    const text: string = line.text.replace(/\s+/g, " ").trim();
    const itemId: string = (line.itemId || "").trim();
    return text.length > 0 && text.toLowerCase().indexOf(itemId.toLowerCase()) < 0 ? text : undefined;
}

function shortenLineText(text: string): string {
    const value: string = text.replace(/\s+/g, " ").trim();
    return value.length > MAX_LINE_LABEL_LENGTH ? `${value.slice(0, MAX_LINE_LABEL_LENGTH - 1)}\u2026` : value;
}

function isRecordId(value: unknown): value is number {
    return typeof value === "number" && isFinite(value) && value > 0 && Math.floor(value) === value;
}
