/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import {
    AddItemToCartOperationRequest,
    AddItemToCartOperationResponse,
    ConcludeTransactionClientRequest,
    ConcludeTransactionClientResponse,
    CreateCustomerOrderOperationRequest,
    CreateCustomerOrderOperationResponse,
    GetCurrentCartClientRequest,
    GetCurrentCartClientResponse,
    RefreshCartClientRequest,
    RefreshCartClientResponse,
    SetCustomerOnCartOperationRequest,
    SetCustomerOnCartOperationResponse
} from "PosApi/Consume/Cart";
import { GetCustomerClientRequest, GetCustomerClientResponse } from "PosApi/Consume/Customer";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ArrayExtensions, ObjectExtensions, StringExtensions } from "PosApi/TypeExtensions";
import {
    IAgentCustomerOrderReceipt,
    IAgentCustomerOrderRequest,
    IAgentProductSelection
} from "ContosoSideChat";
import { StoreOperations } from "../../DataService/DataServiceRequests.g";
import { IResolvedProductCards, resolveProductCardsAsync } from "./ProductCardResolver";

export interface ICustomerOrderExecutionResult {
    summary: string;
    receipt?: IAgentCustomerOrderReceipt;
}

/**
 * Creates and concludes one shipped customer order from Commerce-grounded identifiers.
 * @param request The customer-order intent returned by the agent.
 * @param context The POS extension context.
 * @returns The action summary and a receipt when checkout completed.
 */
export async function createCustomerOrderAsync(
    request: IAgentCustomerOrderRequest,
    context: IExtensionContext
): Promise<ICustomerOrderExecutionResult> {
    validateRequest(request);

    const correlationId: string = context.logger.getNewCorrelationId();
    const initialCart: ProxyEntities.Cart | undefined = await getCurrentCartAsync(context, correlationId);
    const activeLines: ProxyEntities.CartLine[] = (initialCart?.CartLines ?? []).filter(
        (line: ProxyEntities.CartLine) => !line.IsVoided);

    if (ArrayExtensions.hasElements(activeLines)) {
        throw new Error("Finish or void the current transaction before creating this customer order.");
    }

    const customerResult: ClientEntities.ICancelableDataResult<GetCustomerClientResponse> =
        await context.runtime.executeAsync(
            new GetCustomerClientRequest<GetCustomerClientResponse>(
                request.customerAccountNumber,
                correlationId));
    const customer: ProxyEntities.Customer | undefined = customerResult.canceled
        ? undefined
        : customerResult.data?.result;

    if (ObjectExtensions.isNullOrUndefined(customer)) {
        throw new Error(`Customer ${request.customerAccountNumber} could not be loaded.`);
    }

    const shippingAddress: ProxyEntities.Address | undefined = (customer.Addresses ?? []).filter(
        (address: ProxyEntities.Address) => address.RecordId === request.shippingAddressRecordId)[0];
    if (ObjectExtensions.isNullOrUndefined(shippingAddress)) {
        throw new Error("The selected saved address no longer belongs to this customer.");
    }

    const productSelection: IAgentProductSelection = {
        productId: request.productId,
        variantProductId: request.variantProductId,
        dimensions: request.dimensions
    };
    const products: IResolvedProductCards = await resolveProductCardsAsync(
        [request.productId],
        context,
        [productSelection]);
    const productCard = products.cards[0];
    const variant: ProxyEntities.SimpleProduct | undefined =
        products.saleProductsByRecordId[request.productId];

    if (ObjectExtensions.isNullOrUndefined(productCard)
        || ObjectExtensions.isNullOrUndefined(productCard.selectedVariantId)
        || ObjectExtensions.isNullOrUndefined(variant)
        || variant.RecordId !== request.variantProductId) {
        throw new Error("The requested product variant could not be validated.");
    }

    const saleResult: ClientEntities.ICancelableDataResult<AddItemToCartOperationResponse> =
        await context.runtime.executeAsync(
            new AddItemToCartOperationRequest<AddItemToCartOperationResponse>([
                {
                    product: variant,
                    productId: variant.RecordId,
                    quantity: request.quantity
                }
            ], correlationId));
    throwIfCanceled(saleResult, "Adding the selected product was canceled.");

    const customerOnCartResult: ClientEntities.ICancelableDataResult<SetCustomerOnCartOperationResponse> =
        await context.runtime.executeAsync(
            new SetCustomerOnCartOperationRequest<SetCustomerOnCartOperationResponse>(
                correlationId,
                customer.AccountNumber,
                undefined,
                true));
    throwIfCanceled(customerOnCartResult, "Adding the customer to the order was canceled.");

    const createOrderResult: ClientEntities.ICancelableDataResult<CreateCustomerOrderOperationResponse> =
        await context.runtime.executeAsync(
            new CreateCustomerOrderOperationRequest<CreateCustomerOrderOperationResponse>(correlationId));
    throwIfCanceled(createOrderResult, "Creating the customer-order transaction was canceled.");

    const cart: ProxyEntities.Cart | undefined = createOrderResult.data?.cart
        ?? await getCurrentCartAsync(context, correlationId);
    if (ObjectExtensions.isNullOrUndefined(cart) || StringExtensions.isNullOrWhitespace(cart.Id)) {
        throw new Error("The customer-order cart could not be loaded.");
    }

    const deliveryResult:
        ClientEntities.ICancelableDataResult<StoreOperations.ConfigureAgentCustomerOrderDeliveryResponse> =
        await context.runtime.executeAsync(
            new StoreOperations.ConfigureAgentCustomerOrderDeliveryRequest<
                StoreOperations.ConfigureAgentCustomerOrderDeliveryResponse>(
                cart.Id,
                request.deliveryModeCode,
                shippingAddress,
                request.fulfillmentStoreId,
                request.warehouseId ?? StringExtensions.EMPTY,
                request.requestedShipDate));
    throwIfCanceled(deliveryResult, "Configuring shipping was canceled.");

    const refreshedCartResult: ClientEntities.ICancelableDataResult<RefreshCartClientResponse> =
        await context.runtime.executeAsync(new RefreshCartClientRequest<RefreshCartClientResponse>(correlationId));
    throwIfCanceled(refreshedCartResult, "Refreshing the customer order was canceled.");

    const refreshedCart: ProxyEntities.Cart | undefined = refreshedCartResult.data?.result;
    if (ObjectExtensions.isNullOrUndefined(refreshedCart)) {
        throw new Error("The configured customer order could not be refreshed.");
    }

    if (Math.abs(refreshedCart.AmountDue ?? 0) > 0.0001) {
        context.navigator.navigateToPOSView(
            "CartView",
            new ClientEntities.CartViewNavigationParameters(correlationId));
        return {
            summary: "Prepared the shipped customer order. Payment or deposit is required before it can be submitted."
        };
    }

    const concludeResult: ClientEntities.ICancelableDataResult<ConcludeTransactionClientResponse> =
        await context.runtime.executeAsync(
            new ConcludeTransactionClientRequest<ConcludeTransactionClientResponse>(correlationId));
    throwIfCanceled(concludeResult, "Submitting the customer order was canceled.");

    const salesOrder: ProxyEntities.SalesOrder | undefined = concludeResult.data?.salesOrder;
    if (ObjectExtensions.isNullOrUndefined(salesOrder)
        || StringExtensions.isNullOrWhitespace(salesOrder.SalesId)) {
        throw new Error("Commerce did not return a customer order number.");
    }

    return {
        summary: `Created customer order ${salesOrder.SalesId}.`,
        receipt: {
            orderNumber: salesOrder.SalesId,
            customerName: customer.Name || customer.AccountNumber,
            itemName: `${productCard.name}${formatDimensions(productCard.dimensionValues)}`,
            sourceStore: request.sourceStoreName || request.fulfillmentStoreId,
            sourceStoreAvailability: formatAvailability(request.sourceStoreAvailableQuantity),
            sourceStoreDistance: formatOptionalText(request.sourceStoreDistance),
            currentStoreAvailability: formatAvailability(request.currentStoreAvailableQuantity),
            shippingAddress: formatAddress(shippingAddress),
            deliveryMethod: request.deliveryModeName || request.deliveryModeCode,
            status: "Created"
        }
    };
}

function validateRequest(request: IAgentCustomerOrderRequest): void {
    if (ObjectExtensions.isNullOrUndefined(request)
        || StringExtensions.isNullOrWhitespace(request.customerAccountNumber)
        || !isPositiveNumber(request.productId)
        || !isPositiveNumber(request.variantProductId)
        || !isPositiveNumber(request.quantity)
        || !isPositiveNumber(request.shippingAddressRecordId)
        || StringExtensions.isNullOrWhitespace(request.fulfillmentStoreId)
        || StringExtensions.isNullOrWhitespace(request.deliveryModeCode)
        || StringExtensions.isNullOrWhitespace(request.requestedShipDate)
        || !ArrayExtensions.hasElements(request.dimensions)) {
        throw new Error("The customer-order action did not include all required Commerce identifiers.");
    }
}

async function getCurrentCartAsync(
    context: IExtensionContext,
    correlationId: string
): Promise<ProxyEntities.Cart | undefined> {
    const result: ClientEntities.ICancelableDataResult<GetCurrentCartClientResponse> =
        await context.runtime.executeAsync(
            new GetCurrentCartClientRequest<GetCurrentCartClientResponse>(correlationId));

    return result.canceled ? undefined : result.data?.result;
}

function throwIfCanceled(
    result: ClientEntities.ICancelableDataResult<unknown>,
    message: string
): void {
    if (result.canceled) {
        throw new Error(message);
    }
}

function isPositiveNumber(value: number): boolean {
    return typeof value === "number" && isFinite(value) && value > 0;
}

function formatDimensions(values: ReadonlyArray<string> | undefined): string {
    return ArrayExtensions.hasElements(values) ? ` \u00b7 ${values.join(" \u00b7 ")}` : StringExtensions.EMPTY;
}

// Agent-reported, display-only inventory context. It is read after checkout, so an unusable value is
// dropped rather than thrown: failing here would report a created order as failed.
function formatAvailability(quantity: unknown): string | undefined {
    if (typeof quantity !== "number" || !isFinite(quantity) || quantity < 0) {
        return undefined;
    }

    return quantity === 0 ? "Out of stock" : `${quantity} available`;
}

function formatOptionalText(value: unknown): string | undefined {
    return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function formatAddress(address: ProxyEntities.Address): string {
    if (!StringExtensions.isNullOrWhitespace(address.FullAddress)) {
        return address.FullAddress;
    }

    return [
        address.Street,
        address.City,
        address.State,
        address.ZipCode
    ].filter((part: string | undefined): part is string =>
        typeof part === "string" && !StringExtensions.isNullOrWhitespace(part)).join(", ");
}
