/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import {
    GetActivePricesServiceRequest,
    GetActivePricesServiceResponse,
    GetCurrentProductCatalogStoreClientRequest,
    GetCurrentProductCatalogStoreClientResponse,
    GetProductsByIdsClientRequest,
    GetProductsByIdsClientResponse
} from "PosApi/Consume/Products";
import { GetCurrentCartClientRequest, GetCurrentCartClientResponse } from "PosApi/Consume/Cart";
import { GetChannelConfigurationClientRequest, GetChannelConfigurationClientResponse } from "PosApi/Consume/Device";
import { CurrencyFormatter } from "PosApi/Consume/Formatters";
import { ObjectExtensions, StringExtensions } from "PosApi/TypeExtensions";
import { IAgentProductCard, IAgentProductSelection } from "ContosoSideChat";

const RICH_MEDIA_BASE_URL_PROFILE_KEY: number = 2;

/** Commerce's number for the Color product dimension. */
const PRODUCT_DIMENSION_COLOR: number = 1;

/** Commerce's number for the Size product dimension. */
const PRODUCT_DIMENSION_SIZE: number = 3;

export interface IResolvedProductCards {
    cards: IAgentProductCard[];
    productsByRecordId: { [recordId: number]: ProxyEntities.SimpleProduct };
    saleProductsByRecordId: { [recordId: number]: ProxyEntities.SimpleProduct };
    productSelections: IAgentProductSelection[];
}

export async function resolveProductCardsAsync(
    productIds: number[],
    context: IExtensionContext,
    productSelections: ReadonlyArray<IAgentProductSelection> = []
): Promise<IResolvedProductCards> {
    const correlationId: string = context.logger.getNewCorrelationId();
    const variantIds: number[] = productSelections
        .map((selection: IAgentProductSelection) => selection.variantProductId)
        .filter((id: number) => typeof id === "number" && isFinite(id) && id > 0);
    const requestedIds: number[] = productIds.concat(variantIds)
        .filter((id: number, index: number, ids: number[]) => ids.indexOf(id) === index);
    const productsResult: ClientEntities.ICancelableDataResult<GetProductsByIdsClientResponse> =
        await context.runtime.executeAsync(
            new GetProductsByIdsClientRequest<GetProductsByIdsClientResponse>(requestedIds, correlationId));

    if (productsResult.canceled || ObjectExtensions.isNullOrUndefined(productsResult.data)) {
        return { cards: [], productsByRecordId: {}, saleProductsByRecordId: {}, productSelections: [] };
    }

    const products: ProxyEntities.SimpleProduct[] = productsResult.data.result ?? [];
    const mediaBaseUrl: string = await getMediaBaseUrlAsync(context);
    const prices: { [productId: number]: number } =
        await getActivePricesAsync(requestedIds, correlationId, context);
    const productsByRecordId: { [recordId: number]: ProxyEntities.SimpleProduct } = {};
    const saleProductsByRecordId: { [recordId: number]: ProxyEntities.SimpleProduct } = {};
    const validatedSelections: IAgentProductSelection[] = [];

    products.forEach((product: ProxyEntities.SimpleProduct) => {
        productsByRecordId[product.RecordId] = product;
    });

    const cards: IAgentProductCard[] = [];
    productIds.forEach((productId: number) => {
        const product: ProxyEntities.SimpleProduct = productsByRecordId[productId];
        if (ObjectExtensions.isNullOrUndefined(product)) {
            context.logger.logInformational(
                `ProductCardResolver: product ${productId} was not found in this channel and was skipped.`);
            return;
        }

        const selection: IAgentProductSelection | undefined = productSelections.filter(
            (candidate: IAgentProductSelection) => candidate.productId === productId)[0];
        const selectedVariant: ProxyEntities.SimpleProduct | undefined = selection
            ? productsByRecordId[selection.variantProductId]
            : undefined;
        const validatedVariant: ProxyEntities.SimpleProduct | undefined =
            isValidVariantSelection(product, selectedVariant, selection) ? selectedVariant : undefined;

        if (selection && !validatedVariant) {
            context.logger.logInformational(
                `ProductCardResolver: variant ${selection.variantProductId} was not a valid selection `
                + `for product ${productId}; the standard dimension prompt will be used.`);
        }

        if (validatedVariant && selection) {
            validatedSelections.push(selection);
        }

        saleProductsByRecordId[productId] = validatedVariant ?? product;

        const priceProductId: number = validatedVariant?.RecordId ?? productId;
        const price: number = prices[priceProductId] ?? validatedVariant?.Price ?? product.Price;
        const card: IAgentProductCard = {
            recordId: product.RecordId,
            name: product.Name ?? StringExtensions.EMPTY,
            itemId: product.ItemId,
            priceText: formatPrice(price),
            imageUrl: formatImageUrl(product.PrimaryImageUrl, mediaBaseUrl),
            description: product.Description,
            productNumber: product.ProductNumber,
            unitOfMeasure: product.DefaultUnitOfMeasure,
            selectedVariantId: validatedVariant?.RecordId,
            dimensionValues: getDimensionValues(validatedVariant ?? product)
        };

        if (typeof price === "number" && isFinite(price)) {
            card.price = price;
        }

        // Only a variant has a single colour and size, which the filters can then match in POS.
        const variantColor: string | undefined = getDimensionValue(validatedVariant ?? product, PRODUCT_DIMENSION_COLOR);
        if (variantColor) {
            card.variantColor = variantColor;
        }

        const variantSize: string | undefined = getDimensionValue(validatedVariant ?? product, PRODUCT_DIMENSION_SIZE);
        if (variantSize) {
            card.variantSize = variantSize;
        }

        cards.push(card);
    });

    return {
        cards: cards,
        productsByRecordId: productsByRecordId,
        saleProductsByRecordId: saleProductsByRecordId,
        productSelections: validatedSelections
    };
}

function isValidVariantSelection(
    product: ProxyEntities.SimpleProduct,
    variant: ProxyEntities.SimpleProduct | undefined,
    selection: IAgentProductSelection | undefined
): variant is ProxyEntities.SimpleProduct {
    if (ObjectExtensions.isNullOrUndefined(variant) || ObjectExtensions.isNullOrUndefined(selection)) {
        return false;
    }

    if (variant.RecordId !== selection.variantProductId || variant.RecordId === product.RecordId) {
        return false;
    }

    if (!StringExtensions.isNullOrWhitespace(product.ItemId)
        && !StringExtensions.isNullOrWhitespace(variant.ItemId)
        && product.ItemId.toLowerCase() !== variant.ItemId.toLowerCase()) {
        return false;
    }

    const actualValues: string[] = getDimensionValues(variant)
        .map((value: string) => value.trim().toLowerCase());
    const requestedValues: string[] = (selection.dimensions ?? [])
        .map((dimension) => dimension?.value)
        .filter((value: string | undefined): value is string =>
            typeof value === "string" && !StringExtensions.isNullOrWhitespace(value))
        .map((value: string) => value.trim().toLowerCase());

    return requestedValues.length > 0
        && requestedValues.every((value: string) => actualValues.indexOf(value) >= 0);
}

function getDimensionValues(product: ProxyEntities.SimpleProduct): string[] {
    return (product.Dimensions ?? [])
        .map((dimension: ProxyEntities.ProductDimension) => dimension.DimensionValue?.Value)
        .filter((value: string | undefined): value is string =>
            typeof value === "string" && !StringExtensions.isNullOrWhitespace(value));
}

/**
 * Reads one of a variant's dimension values.
 * @param product The product. A master product has no values.
 * @param dimensionType The dimension, as Commerce numbers it.
 * @returns The value, or undefined when the product has none for that dimension.
 */
function getDimensionValue(product: ProxyEntities.SimpleProduct, dimensionType: number): string | undefined {
    const value: string | undefined = (product.Dimensions ?? []).filter((dimension: ProxyEntities.ProductDimension) =>
        dimension?.DimensionTypeValue === dimensionType)[0]?.DimensionValue?.Value;

    return typeof value === "string" && !StringExtensions.isNullOrWhitespace(value) ? value.trim() : undefined;
}

async function getActivePricesAsync(
    productIds: number[],
    correlationId: string,
    context: IExtensionContext
): Promise<{ [productId: number]: number }> {
    const prices: { [productId: number]: number } = {};

    try {
        const catalogResult: ClientEntities.ICancelableDataResult<GetCurrentProductCatalogStoreClientResponse> =
            await context.runtime.executeAsync(
                new GetCurrentProductCatalogStoreClientRequest<GetCurrentProductCatalogStoreClientResponse>());

        if (catalogResult.canceled || ObjectExtensions.isNullOrUndefined(catalogResult.data)) {
            return prices;
        }

        const projectionDomain: ProxyEntities.ProjectionDomain = catalogResult.data.context;
        let customerId: string = StringExtensions.EMPTY;
        let affiliations: ProxyEntities.AffiliationLoyaltyTier[] = [];
        const cartResult: ClientEntities.ICancelableDataResult<GetCurrentCartClientResponse> =
            await context.runtime.executeAsync(
                new GetCurrentCartClientRequest<GetCurrentCartClientResponse>());

        if (!cartResult.canceled && !ObjectExtensions.isNullOrUndefined(cartResult.data)) {
            const cart: ProxyEntities.Cart = cartResult.data.result;
            if (!ObjectExtensions.isNullOrUndefined(cart)) {
                customerId = cart.CustomerId ?? StringExtensions.EMPTY;
                affiliations = cart.AffiliationLines ?? [];
            }
        }

        const priceResult: ClientEntities.ICancelableDataResult<GetActivePricesServiceResponse> =
            await context.runtime.executeAsync(
                new GetActivePricesServiceRequest<GetActivePricesServiceResponse>(
                    correlationId,
                    productIds,
                    projectionDomain,
                    new Date(),
                    customerId,
                    affiliations));

        if (priceResult.canceled || ObjectExtensions.isNullOrUndefined(priceResult.data)) {
            return prices;
        }

        (priceResult.data.activeProductPrices ?? []).forEach((productPrice: ProxyEntities.ProductPrice) => {
            if (ObjectExtensions.isNullOrUndefined(productPrice.ProductId)) {
                return;
            }

            const resolved: number | undefined = productPrice.CustomerContextualPrice
                ?? productPrice.AdjustedPrice
                ?? productPrice.TradeAgreementPrice
                ?? productPrice.BasePrice;

            if (!ObjectExtensions.isNullOrUndefined(resolved)) {
                prices[productPrice.ProductId] = resolved;
            }
        });
    } catch (error) {
        context.logger.logInformational(
            `ProductCardResolver could not read active prices: ${JSON.stringify(error)}`);
    }

    return prices;
}

async function getMediaBaseUrlAsync(context: IExtensionContext): Promise<string> {
    try {
        const result: ClientEntities.ICancelableDataResult<GetChannelConfigurationClientResponse> =
            await context.runtime.executeAsync(
                new GetChannelConfigurationClientRequest<GetChannelConfigurationClientResponse>());

        if (result.canceled || ObjectExtensions.isNullOrUndefined(result.data)) {
            return StringExtensions.EMPTY;
        }

        const configuration: ProxyEntities.ChannelConfiguration = result.data.result;
        const properties: ProxyEntities.ChannelProfileProperty[] = configuration?.ProfileProperties ?? [];
        const mediaProperty: ProxyEntities.ChannelProfileProperty | undefined = properties.filter(
            (property: ProxyEntities.ChannelProfileProperty) =>
                property.Key === RICH_MEDIA_BASE_URL_PROFILE_KEY)[0];

        return mediaProperty?.Value ?? StringExtensions.EMPTY;
    } catch (error) {
        context.logger.logInformational(
            `ProductCardResolver could not read the channel media base URL: ${JSON.stringify(error)}`);

        return StringExtensions.EMPTY;
    }
}

function formatImageUrl(url: string | undefined, mediaBaseUrl: string): string | undefined {
    if (StringExtensions.isNullOrWhitespace(url)) {
        return undefined;
    }

    if (/^(https?:)?\/\//i.test(url) || /^data:/i.test(url)) {
        return url;
    }

    if (StringExtensions.isNullOrWhitespace(mediaBaseUrl)) {
        return url;
    }

    const base: string = mediaBaseUrl.replace(/\/+$/, "");
    const path: string = url.replace(/^\/+/, "");

    return `${base}/${path}`;
}

function formatPrice(price: number | undefined): string | undefined {
    return ObjectExtensions.isNullOrUndefined(price) ? undefined : CurrencyFormatter.toCurrency(price);
}
