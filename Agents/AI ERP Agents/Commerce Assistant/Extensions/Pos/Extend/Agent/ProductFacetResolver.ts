/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Reads the filters for a set of recommended products from Commerce, and finds which of those products
 * have the tags the associate selected.
 *
 * Both use the out-of-box Retail Server product search, scoped to the products shown, exactly as the
 * POS search view's Filter command and the Similar looks view use it. Nothing here asks the agent.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { GetCurrentProductCatalogStoreClientRequest, GetCurrentProductCatalogStoreClientResponse } from "PosApi/Consume/Products";
import { CurrencyFormatter } from "PosApi/Consume/Formatters";
import { ObjectExtensions } from "PosApi/TypeExtensions";
import { IAgentProductCard, IAgentProductFacetValue, IAgentProductFilterRequest } from "ContosoSideChat";
import { buildProductFacets, IProductFacets } from "./ProductFilters";
import {
    GetProductSearchRefinersRequest,
    GetProductSearchRefinersResponse,
    SearchByCriteriaRequest,
    SearchByCriteriaResponse
} from "./OobRetailServerRequests";

/** The most products one filter search returns. Far more than the agent ever shows. */
const MAX_FILTERED_PRODUCTS: number = 250;

/**
 * Builds the filter tags for a set of recommended products: Color, Size and Price, then the other
 * refiners Commerce returns for them, such as Rating and Category.
 *
 * When Commerce cannot list the products' refiners, only the Price tags are built, since they come
 * from the prices POS already read.
 * @param cards The products shown, in the agent's order.
 * @param agentFilters The filters the agent reported, which only tell which tags are already applied.
 * @param context The POS extension context.
 * @returns The rows of tags to show, and the products as the tags see them.
 */
export async function getProductFacetsAsync(
    cards: ReadonlyArray<IAgentProductCard>,
    agentFilters: unknown,
    context: IExtensionContext
): Promise<IProductFacets> {
    let refiners: ProxyEntities.ProductRefiner[] = [];

    if (cards.length > 1) {
        try {
            const catalogContext: ProxyEntities.ProjectionDomain | undefined = await getStoreCatalogContextAsync(context);
            if (catalogContext) {
                const productIds: number[] = cards.map((card: IAgentProductCard) => card.recordId);
                const result: ClientEntities.ICancelableDataResult<GetProductSearchRefinersResponse> =
                    await context.runtime.executeAsync(new GetProductSearchRefinersRequest<GetProductSearchRefinersResponse>(
                        context.logger.getNewCorrelationId(),
                        productIds,
                        catalogContext));
                if (!result.canceled && !ObjectExtensions.isNullOrUndefined(result.data)) {
                    refiners = result.data.result ?? [];
                }
            }
        } catch (error) {
            context.logger.logInformational(
                `Side chat: the filters for the products shown could not be read. ${JSON.stringify(error)}`);
        }
    }

    return buildProductFacets({
        refiners: refiners,
        cards: cards,
        agentFilters: agentFilters,
        formatPrice: (price: number): string => CurrencyFormatter.toCurrency(price)
    });
}

/**
 * Finds which of the products shown have the selected tags other than prices.
 *
 * Within a row any selected value matches, and across rows every row must match, as in the POS search
 * view's filters. Each value is sent to Commerce as it returned it.
 * @param request The products shown and the selected tags other than prices.
 * @param context The POS extension context.
 * @returns The products that match, as the request listed them. Rejects when Commerce could not be asked.
 */
export async function filterProductsAsync(
    request: IAgentProductFilterRequest,
    context: IExtensionContext
): Promise<ReadonlyArray<number>> {
    const productIds: number[] = (request?.productIds ?? []).filter((id: number, index: number, ids: ReadonlyArray<number>) =>
        typeof id === "number" && isFinite(id) && id > 0 && ids.indexOf(id) === index);
    const refinement: ProxyEntities.ProductRefinerValue[] = [];
    (request?.values ?? []).forEach((value: IAgentProductFacetValue) => {
        const refinerValue: unknown = value?.refinerValue;
        if (refinerValue && typeof refinerValue === "object" && !Array.isArray(refinerValue)) {
            refinement.push(refinerValue as ProxyEntities.ProductRefinerValue);
        }
    });

    if (productIds.length === 0 || refinement.length === 0) {
        return productIds;
    }

    const catalogContext: ProxyEntities.ProjectionDomain | undefined = await getStoreCatalogContextAsync(context);
    if (!catalogContext) {
        throw new Error("Products can be filtered only in the store's own catalog.");
    }

    const result: ClientEntities.ICancelableDataResult<SearchByCriteriaResponse> =
        await context.runtime.executeAsync(new SearchByCriteriaRequest<SearchByCriteriaResponse>(
            context.logger.getNewCorrelationId(),
            productIds,
            catalogContext,
            refinement,
            MAX_FILTERED_PRODUCTS));
    if (result.canceled || ObjectExtensions.isNullOrUndefined(result.data)) {
        throw new Error("Filtering the products was canceled.");
    }

    // Commerce may answer with a product's variants, so a product matches through its master too.
    const matched: { [productId: number]: boolean } = {};
    (result.data.result ?? []).forEach((product: ProxyEntities.ProductSearchResult) => {
        if (product) {
            matched[product.RecordId] = true;
            if (typeof product.MasterProductId === "number") {
                matched[product.MasterProductId] = true;
            }
        }
    });

    return productIds.filter((id: number) => matched[id] === true);
}

/**
 * Reads the catalog to search in, as the POS search view's Filter command does.
 * @param context The POS extension context.
 * @returns The store's own catalog context, or undefined when POS is browsing another store's catalog
 * or the catalog could not be read, in which case the search view offers no filters either.
 */
async function getStoreCatalogContextAsync(context: IExtensionContext): Promise<ProxyEntities.ProjectionDomain | undefined> {
    const result: ClientEntities.ICancelableDataResult<GetCurrentProductCatalogStoreClientResponse> =
        await context.runtime.executeAsync(
            new GetCurrentProductCatalogStoreClientRequest<GetCurrentProductCatalogStoreClientResponse>());
    if (result.canceled || ObjectExtensions.isNullOrUndefined(result.data)) {
        return undefined;
    }

    const catalogContext: ProxyEntities.ProjectionDomain | undefined = result.data.context;
    const store: ProxyEntities.OrgUnit | undefined = result.data.store;
    if (ObjectExtensions.isNullOrUndefined(catalogContext) || ObjectExtensions.isNullOrUndefined(store)
        || catalogContext.ChannelId !== store.RecordId) {
        return undefined;
    }

    return catalogContext;
}
