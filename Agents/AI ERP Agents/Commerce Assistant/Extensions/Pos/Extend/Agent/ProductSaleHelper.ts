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
    AddItemToCartOperationRequest,
    AddItemToCartOperationResponse
} from "PosApi/Consume/Cart";
import {
    GetProductsByIdsClientRequest,
    GetProductsByIdsClientResponse
} from "PosApi/Consume/Products";
import { ObjectExtensions } from "PosApi/TypeExtensions";

/**
 * Adds one resolved product or variant to the current transaction through the standard POS
 * operation, preserving dimension prompts, pricing, reason codes, and sale triggers. After the
 * operation succeeds, opens the cart so the operator can see the updated transaction.
 * @param recordId The product or variant record identifier.
 * @param context The POS extension context.
 * @param resolvedProduct The product when the caller already loaded it.
 */
export async function addProductToSaleAsync(
    recordId: number,
    context: IExtensionContext,
    resolvedProduct?: ProxyEntities.SimpleProduct
): Promise<void> {
    const correlationId: string = context.logger.getNewCorrelationId();
    let product: ProxyEntities.SimpleProduct | undefined = resolvedProduct;

    if (ObjectExtensions.isNullOrUndefined(product)) {
        const productResult: ClientEntities.ICancelableDataResult<GetProductsByIdsClientResponse> =
            await context.runtime.executeAsync(
                new GetProductsByIdsClientRequest<GetProductsByIdsClientResponse>([recordId], correlationId));

        if (productResult.canceled || ObjectExtensions.isNullOrUndefined(productResult.data)) {
            throw new Error(`Product ${recordId} could not be loaded.`);
        }

        product = (productResult.data.result ?? []).filter(
            (candidate: ProxyEntities.SimpleProduct) => candidate.RecordId === recordId)[0];
    }

    if (ObjectExtensions.isNullOrUndefined(product)) {
        throw new Error(`Product ${recordId} is no longer available to add.`);
    }

    const details: ClientEntities.IProductSaleReturnDetails[] = [
        { product: product, productId: product.RecordId, quantity: 1 }
    ];
    const result: ClientEntities.ICancelableDataResult<AddItemToCartOperationResponse> =
        await context.runtime.executeAsync(
            new AddItemToCartOperationRequest<AddItemToCartOperationResponse>(details, correlationId));

    if (result.canceled) {
        throw new Error("Adding the product to the sale was canceled.");
    }

    context.navigator.navigateToPOSView(
        "CartView",
        new ClientEntities.CartViewNavigationParameters(correlationId));
}

/**
 * Adds several resolved products or variants to the current transaction in one standard POS operation,
 * in the order given, then opens the cart. A product that still needs a variant chosen prompts for it
 * as usual.
 * @param recordIds The product or variant record identifiers. Repeats are added once.
 * @param context The POS extension context.
 */
export async function addProductsToSaleAsync(
    recordIds: ReadonlyArray<number>,
    context: IExtensionContext
): Promise<void> {
    const ids: number[] = recordIds.filter((id: number, index: number) =>
        typeof id === "number" && isFinite(id) && id > 0 && recordIds.indexOf(id) === index);
    if (ids.length === 0) {
        throw new Error("There were no products to add.");
    }

    const correlationId: string = context.logger.getNewCorrelationId();
    const productResult: ClientEntities.ICancelableDataResult<GetProductsByIdsClientResponse> =
        await context.runtime.executeAsync(
            new GetProductsByIdsClientRequest<GetProductsByIdsClientResponse>(ids, correlationId));

    if (productResult.canceled || ObjectExtensions.isNullOrUndefined(productResult.data)) {
        throw new Error("The products could not be loaded.");
    }

    const products: ProxyEntities.SimpleProduct[] = productResult.data.result ?? [];
    const details: ClientEntities.IProductSaleReturnDetails[] = [];
    const missingIds: number[] = [];
    ids.forEach((id: number) => {
        const product: ProxyEntities.SimpleProduct | undefined = products.filter(
            (candidate: ProxyEntities.SimpleProduct) => candidate.RecordId === id)[0];
        if (ObjectExtensions.isNullOrUndefined(product)) {
            missingIds.push(id);
            return;
        }

        details.push({ product: product, productId: product.RecordId, quantity: 1 });
    });

    // All or nothing, so the associate never has to work out which of the products made it.
    if (missingIds.length > 0) {
        if (ids.length === 1) {
            throw new Error(`Product ${missingIds[0]} is no longer available to add.`);
        }

        throw new Error(`${missingIds.length === 1 ? "One of the products is" : `${missingIds.length} of the products are`} `
            + "no longer available to add, so none were added.");
    }

    const result: ClientEntities.ICancelableDataResult<AddItemToCartOperationResponse> =
        await context.runtime.executeAsync(
            new AddItemToCartOperationRequest<AddItemToCartOperationResponse>(details, correlationId));

    if (result.canceled) {
        throw new Error(details.length === 1
            ? "Adding the product to the sale was canceled."
            : "Adding the products to the sale was canceled.");
    }

    context.navigator.navigateToPOSView(
        "CartView",
        new ClientEntities.CartViewNavigationParameters(correlationId));
}
