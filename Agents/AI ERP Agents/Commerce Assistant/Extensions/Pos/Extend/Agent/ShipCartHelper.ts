/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Sets the products on the sale to ship to one of a customer's saved addresses, from the associate's
 * words, for example "ship to Karen Berg's home address, standard shipping, in 2 days".
 *
 * It does what the POS Ship selected operation does, with the public POS API and out-of-box Retail
 * Server operations (see OobRetailServerRequests), so no Commerce Scale Unit extension is involved.
 * POS finds the customer, the address and the delivery mode itself: the agent only passes on what the
 * associate said and which store has the stock. Everything is read and checked, and the shipping
 * charge entered, before the sale changes, so a request POS can't carry out leaves the sale as it was.
 * The order stays on the sale for the associate to take payment; nothing here concludes it. The cart
 * then opens to show what was set.
 */

import {
    CreateCustomerOrderOperationRequest,
    CreateCustomerOrderOperationResponse,
    GetCurrentCartClientRequest,
    GetCurrentCartClientResponse,
    GetShippingChargeClientRequest,
    GetShippingChargeClientResponse,
    RefreshCartClientRequest,
    RefreshCartClientResponse,
    SetCustomerOnCartOperationRequest,
    SetCustomerOnCartOperationResponse
} from "PosApi/Consume/Cart";
import {
    GetCustomerClientRequest,
    GetCustomerClientResponse,
    SelectCustomerClientRequest,
    SelectCustomerClientResponse
} from "PosApi/Consume/Customer";
import { GetChannelConfigurationClientRequest, GetChannelConfigurationClientResponse } from "PosApi/Consume/Device";
import { CurrencyFormatter, DateFormatter } from "PosApi/Consume/Formatters";
import { GetProductsByIdsClientRequest, GetProductsByIdsClientResponse } from "PosApi/Consume/Products";
import { GetFeatureStatesServiceRequest, GetFeatureStatesServiceResponse } from "PosApi/Consume/StoreOperations";
import { Request, Response } from "PosApi/Create/RequestHandlers";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import {
    IAgentShippingReceipt,
    IAgentShippingReceiptLine,
    IAgentShippingRequest,
    IAgentStoreContext
} from "ContosoSideChat";
import { getCurrentStoreAsync } from "./CurrentStoreHelper";
import {
    GetChannelDeliveryOptionConfigurationRequest,
    GetChannelDeliveryOptionConfigurationResponse,
    GetLineDeliveryOptionsByChannelIdRequest,
    GetLineDeliveryOptionsByChannelIdResponse,
    SearchCustomersRequest,
    SearchCustomersResponse,
    SearchOrgUnitsRequest,
    SearchOrgUnitsResponse,
    UpdateCartLinesRequest,
    UpdateCartLinesResponse
} from "./OobRetailServerRequests";
import {
    applyDelivery,
    CHARGE_DECIMALS,
    checkSale,
    chooseLinesToShip,
    computeDeliveryDate,
    describeLine,
    describeShipFromStock,
    formatAddress,
    getShipFromAddress,
    getShipFromWarehouse,
    getShippableOptions,
    getSoldLines,
    groupByStore,
    isSameCustomerName,
    isText,
    IShippingDestination,
    IShippingTarget,
    IStoreShipment,
    matchCustomersByName,
    matchDeliveryOption,
    pickShippingAddress,
    splitCharge,
    toDeliveryAddress,
    toSearchKeyword,
    validateShippingRequest
} from "./shippingRules";

/** What the shipCart action did. */
export interface IShipCartExecutionResult {
    /** One line for the action's receipt in the chat. */
    summary: string;
    /** What POS set on the sale, for the card in the chat. */
    receipt: IAgentShippingReceipt;
}

/** The Commerce feature that has lines record the warehouse they ship from, as the POS shipping screen checks it. */
const CHANGE_SHIPPING_LOCATION_FEATURE: string = "Dynamics.AX.Application.ChangeShippingLocationFeature";

/** The most customers a name search reads. */
const CUSTOMER_SEARCH_LIMIT: number = 20;

// ProxyEntities.CartType.CustomerOrder and ProxyEntities.CustomerOrderMode.CreateOrEdit.
const CART_TYPE_CUSTOMER_ORDER: number = 3;
const ORDER_MODE_CREATE_OR_EDIT: number = 1;

const NOTHING_CHANGED: string = "Nothing was changed.";

/** What POS knows about the products on the sale. */
interface IProductDetails {
    /** Each product's name with its dimension values, for example "Puffer jacket · Black · M". */
    names: { [productId: number]: string };
    /** Each variant's master product. */
    masterProductIds: { [productId: number]: number };
}

/** The store settings that decide how lines ship. */
interface IShippingSettings {
    /** Commerce works out shipping charges itself, so POS doesn't ask for them. */
    useAdvancedAutoCharges: boolean;
    /** Lines record the warehouse they ship from. */
    setWarehouse: boolean;
    /** The pickup, carry-out and email delivery modes, which don't ship. */
    nonShippingModes: string[];
}

/** How the lines from one store ship. */
interface IShipmentPlan {
    shipment: IStoreShipment;
    store: ProxyEntities.OrgUnit;
    option: ProxyEntities.DeliveryOption;
    /** Each line's share of the shipping charge, in line order. */
    charges: number[];
}

/**
 * Sets products on the sale to ship, as the associate asked.
 * @param request What the associate asked for, as the agent read it.
 * @param context The POS extension context.
 * @returns What was set, for the chat.
 */
export async function shipCartAsync(
    request: IAgentShippingRequest,
    context: IExtensionContext
): Promise<IShipCartExecutionResult> {
    const problem: string | undefined = validateShippingRequest(request);
    if (problem) {
        throw new Error(problem);
    }

    const correlationId: string = context.logger.getNewCorrelationId();
    const cart: ProxyEntities.Cart | undefined = await readCartAsync(context, correlationId, "read the sale", NOTHING_CHANGED);
    const saleProblem: string | undefined = checkSale(cart);
    if (saleProblem) {
        throw new Error(saleProblem);
    }

    const soldLines: ProxyEntities.CartLine[] = getSoldLines(cart);
    const products: IProductDetails = await getProductDetailsAsync(soldLines, context, correlationId);
    const currentStore: IAgentStoreContext | undefined = await getCurrentStoreAsync(context, correlationId);
    if (!currentStore || !isText(currentStore.number)) {
        throw new Error(`POS couldn't tell which store this is. ${NOTHING_CHANGED}`);
    }

    const targets: IShippingTarget[] = chooseLinesToShip(request, soldLines, products.masterProductIds, currentStore.number);
    const shipments: IStoreShipment[] = groupByStore(targets);
    const stores: { [storeNumber: string]: ProxyEntities.OrgUnit } = await findStoresAsync(shipments, context, correlationId);
    const settings: IShippingSettings = await getShippingSettingsAsync(context, correlationId);
    const customer: ProxyEntities.Customer = await findCustomerAsync(request, cart, context, correlationId);
    const customerName: string = describeCustomer(customer);
    const destination: IShippingDestination = pickShippingAddress(customer.Addresses, request.addressType, customerName);
    const deliveryDate: Date = computeDeliveryDate(new Date(), request.deliveryInDays, request.deliveryDate);
    const plans: IShipmentPlan[] = await planShipmentsAsync(
        request.deliveryMode, cart.Id, shipments, stores, destination, settings, context, correlationId);
    await enterShippingChargesAsync(plans, destination, settings, context, correlationId);

    await saveShippingAsync(cart, customer, plans, destination, deliveryDate, settings, context, correlationId);

    const refreshed: RefreshCartClientResponse | undefined = await runAsync<RefreshCartClientResponse>(
        new RefreshCartClientRequest<RefreshCartClientResponse>(correlationId),
        context,
        "show the shipping on the sale",
        "Shipping was set; open the cart to check it before checkout.");
    const shippedCart: ProxyEntities.Cart | undefined = refreshed?.result;
    if (!shippedCart) {
        throw new Error("Shipping was set, but POS couldn't refresh the sale. Open the cart to check it before checkout.");
    }

    try {
        context.navigator.navigateToPOSView("CartView", new ClientEntities.CartViewNavigationParameters(correlationId));
    } catch (error) {
        context.logger.logWarning(`Side chat: shipCart couldn't open the cart. ${describeError(error)}`, correlationId);
    }

    const deliveryMethod: string = describeOption(plans[0].option);
    const formattedDate: string = formatDate(deliveryDate);
    const enteredCharges: number = plans.reduce((total: number, plan: IShipmentPlan) =>
        plan.charges.reduce((sum: number, charge: number) => sum + charge, total), 0);
    const shippingCharges: number = (shippedCart.ShippingChargeAmount || 0) > 0 ? shippedCart.ShippingChargeAmount : enteredCharges;
    const shipTo: string = destination.typeName
        ? `${possessive(customerName)} ${destination.typeName.toLowerCase()} address`
        : customerName;

    return {
        summary: `Set ${describeCount(targets.length)} to ship to ${shipTo} by ${deliveryMethod}, `
            + `for delivery ${formattedDate}. Ready for checkout.`,
        receipt: {
            customerName: customerName,
            customerAccount: customer.AccountNumber,
            addressType: destination.typeName,
            shippingAddress: formatAddress(destination.address),
            deliveryMethod: deliveryMethod,
            deliveryDate: formattedDate,
            lines: targets.map((target: IShippingTarget): IAgentShippingReceiptLine => ({
                name: products.names[target.line.ProductId] || describeLine(target.line),
                quantity: target.line.Quantity,
                shipFrom: describeStore(stores[target.storeNumber]),
                shipFromDetail: describeShipFromStock(target.item)
            })),
            total: formatAmount(shippedCart.TotalAmount),
            shippingCharges: formatAmount(shippingCharges),
            amountDue: formatAmount(shippedCart.AmountDue),
            status: "Ready for checkout"
        }
    };
}

/**
 * Reads each product on the sale, for its name and master product. Optional: the lines ship without it.
 */
async function getProductDetailsAsync(
    lines: ProxyEntities.CartLine[],
    context: IExtensionContext,
    correlationId: string
): Promise<IProductDetails> {
    const details: IProductDetails = { names: {}, masterProductIds: {} };
    const productIds: number[] = [];
    lines.forEach((line: ProxyEntities.CartLine): void => {
        if (productIds.indexOf(line.ProductId) < 0) {
            productIds.push(line.ProductId);
        }
    });

    try {
        const result: ClientEntities.ICancelableDataResult<GetProductsByIdsClientResponse> = await context.runtime.executeAsync(
            new GetProductsByIdsClientRequest<GetProductsByIdsClientResponse>(productIds, correlationId));
        const products: ProxyEntities.SimpleProduct[] = result.canceled ? [] : (result.data?.result ?? []);
        products.forEach((product: ProxyEntities.SimpleProduct): void => {
            if (!product || !(product.RecordId > 0)) {
                return;
            }

            if (isText(product.Name)) {
                details.names[product.RecordId] = describeProduct(product);
            }

            if (product.MasterProductId > 0 && product.MasterProductId !== product.RecordId) {
                details.masterProductIds[product.RecordId] = product.MasterProductId;
            }
        });
    } catch (error) {
        // The card falls back to each line's description, and the agent names products as the sale lists them.
        context.logger.logWarning(`Side chat: shipCart couldn't read the products on the sale. ${describeError(error)}`, correlationId);
    }

    return details;
}

/** Finds each store that ships, by its number. */
async function findStoresAsync(
    shipments: IStoreShipment[],
    context: IExtensionContext,
    correlationId: string
): Promise<{ [storeNumber: string]: ProxyEntities.OrgUnit }> {
    const stores: { [storeNumber: string]: ProxyEntities.OrgUnit } = {};
    for (const shipment of shipments) {
        const response: SearchOrgUnitsResponse | undefined = await runAsync<SearchOrgUnitsResponse>(
            new SearchOrgUnitsRequest<SearchOrgUnitsResponse>(correlationId, shipment.storeNumber),
            context,
            `find store ${shipment.storeNumber}`);
        const store: ProxyEntities.OrgUnit | undefined = (response?.result ?? []).filter((candidate: ProxyEntities.OrgUnit) =>
            candidate
            && isText(candidate.OrgUnitNumber)
            && candidate.OrgUnitNumber.trim().toUpperCase() === shipment.storeNumber)[0];
        if (!store || !(store.RecordId > 0)) {
            throw new Error(`POS can't find store ${shipment.storeNumber} to ship from. ${NOTHING_CHANGED}`);
        }

        stores[shipment.storeNumber] = store;
    }

    return stores;
}

/** Reads the store settings that decide how lines ship. */
async function getShippingSettingsAsync(context: IExtensionContext, correlationId: string): Promise<IShippingSettings> {
    const configuration: GetChannelConfigurationClientResponse | undefined = await runAsync<GetChannelConfigurationClientResponse>(
        new GetChannelConfigurationClientRequest<GetChannelConfigurationClientResponse>(correlationId),
        context,
        "read the store's settings");
    const channel: ProxyEntities.ChannelConfiguration | undefined = configuration?.result;
    if (!channel) {
        throw new Error(`POS couldn't read the store's settings. ${NOTHING_CHANGED}`);
    }

    const nonShippingModes: string[] = [
        channel.PickupDeliveryModeCode,
        channel.CarryoutDeliveryModeCode,
        channel.EmailDeliveryModeCode
    ];
    try {
        const result: ClientEntities.ICancelableDataResult<GetChannelDeliveryOptionConfigurationResponse> =
            await context.runtime.executeAsync(
                new GetChannelDeliveryOptionConfigurationRequest<GetChannelDeliveryOptionConfigurationResponse>(correlationId));
        const pickupModes: string[] = result.canceled ? [] : (result.data?.result?.PickupDeliveryModeCodes ?? []);
        pickupModes.forEach((code: string): void => {
            nonShippingModes.push(code);
        });
    } catch (error) {
        // The store's own pickup mode is still left out; only other pickup modes could be offered.
        context.logger.logWarning(`Side chat: shipCart couldn't read the pickup delivery modes. ${describeError(error)}`, correlationId);
    }

    return {
        useAdvancedAutoCharges: channel.UseAdvancedAutoCharges === true,
        setWarehouse: await isFeatureEnabledAsync(CHANGE_SHIPPING_LOCATION_FEATURE, context, correlationId),
        nonShippingModes: nonShippingModes.filter(isText)
    };
}

/** Answers whether a Commerce feature is on. Off when POS can't tell, as the POS shipping screen treats it. */
async function isFeatureEnabledAsync(featureName: string, context: IExtensionContext, correlationId: string): Promise<boolean> {
    try {
        const result: ClientEntities.ICancelableDataResult<GetFeatureStatesServiceResponse> = await context.runtime.executeAsync(
            new GetFeatureStatesServiceRequest<GetFeatureStatesServiceResponse>(correlationId, [featureName]));
        const states: ReadonlyArray<Readonly<ProxyEntities.FeatureState>> = result.canceled ? [] : (result.data?.featureStates ?? []);
        return states.some((state: Readonly<ProxyEntities.FeatureState>) =>
            state
            && state.IsEnabled === true
            && isText(state.Name)
            && state.Name.toLowerCase() === featureName.toLowerCase());
    } catch (error) {
        context.logger.logWarning(`Side chat: shipCart couldn't read feature ${featureName}. ${describeError(error)}`, correlationId);
        return false;
    }
}

/**
 * Finds the customer the order is for: the one on the sale, otherwise the one the associate named.
 * When several customers have the name, the associate picks one in the POS customer search.
 */
async function findCustomerAsync(
    request: IAgentShippingRequest,
    cart: ProxyEntities.Cart,
    context: IExtensionContext,
    correlationId: string
): Promise<ProxyEntities.Customer> {
    const said: string = isText(request.customerName) ? request.customerName.trim() : "";
    if (isText(cart.CustomerId)) {
        const onSale: ProxyEntities.Customer = await loadCustomerAsync(cart.CustomerId, context, correlationId);
        const onSaleName: string = describeCustomer(onSale);
        if (said && !isSameCustomerName(said, onSale.Name)) {
            throw new Error(`The sale is for ${onSaleName}, not ${said}. To ship to ${said}, remove ${onSaleName} `
                + `from the sale in POS first. ${NOTHING_CHANGED}`);
        }

        return onSale;
    }

    if (!said) {
        throw new Error(`Say who the order is for. ${NOTHING_CHANGED}`);
    }

    const keyword: string = toSearchKeyword(said);
    const response: SearchCustomersResponse | undefined = await runAsync<SearchCustomersResponse>(
        new SearchCustomersRequest<SearchCustomersResponse>(correlationId, keyword, CUSTOMER_SEARCH_LIMIT),
        context,
        `search for ${said}`);
    const matches: ProxyEntities.GlobalCustomer[] = matchCustomersByName(said, response?.result ?? []);
    if (matches.length === 0) {
        throw new Error(`POS found no customer named ${said}. Check the name, or add the customer in POS. ${NOTHING_CHANGED}`);
    }

    let accountNumber: string = matches[0].AccountNumber;
    if (matches.length > 1) {
        const picked: SelectCustomerClientResponse | undefined = await runAsync<SelectCustomerClientResponse>(
            new SelectCustomerClientRequest<SelectCustomerClientResponse>(correlationId, keyword),
            context,
            "open the customer search");
        const customer: ProxyEntities.Customer | undefined = picked?.result;
        if (!customer || !isText(customer.AccountNumber)) {
            throw new Error(`${matches.length} customers are named ${said}, and none was chosen. ${NOTHING_CHANGED}`);
        }

        accountNumber = customer.AccountNumber;
    }

    return loadCustomerAsync(accountNumber, context, correlationId);
}

/** Reads a customer with their saved addresses. */
async function loadCustomerAsync(
    accountNumber: string,
    context: IExtensionContext,
    correlationId: string
): Promise<ProxyEntities.Customer> {
    const response: GetCustomerClientResponse | undefined = await runAsync<GetCustomerClientResponse>(
        new GetCustomerClientRequest<GetCustomerClientResponse>(accountNumber, correlationId),
        context,
        `read customer ${accountNumber}`);
    const customer: ProxyEntities.Customer | undefined = response?.result;
    if (!customer || !isText(customer.AccountNumber)) {
        throw new Error(`POS couldn't read customer ${accountNumber}. ${NOTHING_CHANGED}`);
    }

    return customer;
}

/** Finds the delivery mode the associate named at each store that ships, as the POS shipping screen lists them. */
async function planShipmentsAsync(
    deliveryMode: string,
    cartId: string,
    shipments: IStoreShipment[],
    stores: { [storeNumber: string]: ProxyEntities.OrgUnit },
    destination: IShippingDestination,
    settings: IShippingSettings,
    context: IExtensionContext,
    correlationId: string
): Promise<IShipmentPlan[]> {
    const deliveryAddress: ProxyEntities.Address = toDeliveryAddress(destination.address);
    const plans: IShipmentPlan[] = [];
    for (const shipment of shipments) {
        const store: ProxyEntities.OrgUnit = stores[shipment.storeNumber];
        const lineIds: string[] = shipment.targets.map((target: IShippingTarget) => target.line.LineId);
        const response: GetLineDeliveryOptionsByChannelIdResponse | undefined =
            await runAsync<GetLineDeliveryOptionsByChannelIdResponse>(
                new GetLineDeliveryOptionsByChannelIdRequest<GetLineDeliveryOptionsByChannelIdResponse>(
                    correlationId,
                    cartId,
                    lineIds.map((lineId: string): ProxyEntities.LineShippingAddress => ({
                        LineId: lineId,
                        ShippingAddress: deliveryAddress
                    })),
                    store.RecordId),
                context,
                `find the delivery modes from ${describeStore(store)}`);
        const options: ProxyEntities.DeliveryOption[] = getShippableOptions(response?.result, lineIds, settings.nonShippingModes);
        if (options.length === 0) {
            throw new Error(`No delivery mode can ship ${describeTargets(shipment.targets)} from ${describeStore(store)} `
                + `to that address. ${NOTHING_CHANGED}`);
        }

        plans.push({ shipment: shipment, store: store, option: matchDeliveryOption(deliveryMode, options), charges: [] });
    }

    const codes: string[] = [];
    plans.forEach((plan: IShipmentPlan): void => {
        const code: string = plan.option.Code.toUpperCase();
        if (codes.indexOf(code) < 0) {
            codes.push(code);
        }
    });
    if (codes.length > 1) {
        const modes: string = plans.map((plan: IShipmentPlan) => `${describeOption(plan.option)} from ${describeStore(plan.store)}`)
            .join(", ");
        throw new Error(`"${deliveryMode.trim()}" is a different delivery mode at each store: ${modes}. `
            + `Ship from one store, or set the delivery in POS. ${NOTHING_CHANGED}`);
    }

    return plans;
}

/**
 * Has the associate enter the shipping charge for each store's lines, as the POS shipping screen does,
 * unless Commerce works charges out itself. Each line gets its share.
 */
async function enterShippingChargesAsync(
    plans: IShipmentPlan[],
    destination: IShippingDestination,
    settings: IShippingSettings,
    context: IExtensionContext,
    correlationId: string
): Promise<void> {
    for (const plan of plans) {
        const lines: ProxyEntities.CartLine[] = plan.shipment.targets.map((target: IShippingTarget) => target.line);
        let charge: number = 0;
        if (!settings.useAdvancedAutoCharges) {
            const response: GetShippingChargeClientResponse | undefined = await runAsync<GetShippingChargeClientResponse>(
                new GetShippingChargeClientRequest<GetShippingChargeClientResponse>(
                    correlationId, lines, plan.option, getShipFromAddress(plan.store), destination.address),
                context,
                "ask for the shipping charge");
            if (!response) {
                throw new Error(`No shipping charge was entered. ${NOTHING_CHANGED}`);
            }

            charge = response.result;
            if (typeof charge !== "number" || !isFinite(charge) || charge < 0) {
                throw new Error(`The shipping charge isn't an amount POS can use. ${NOTHING_CHANGED}`);
            }
        }

        plan.charges = splitCharge(charge, lines.length, CHARGE_DECIMALS);
    }
}

/**
 * Changes the sale: adds the customer, makes it a customer order and saves each line's shipping, as the
 * POS Ship selected operation does.
 */
async function saveShippingAsync(
    cart: ProxyEntities.Cart,
    customer: ProxyEntities.Customer,
    plans: IShipmentPlan[],
    destination: IShippingDestination,
    deliveryDate: Date,
    settings: IShippingSettings,
    context: IExtensionContext,
    correlationId: string
): Promise<void> {
    const customerName: string = describeCustomer(customer);
    const changes: string[] = [];

    if (!isText(cart.CustomerId)) {
        const added: SetCustomerOnCartOperationResponse | undefined = await runAsync<SetCustomerOnCartOperationResponse>(
            new SetCustomerOnCartOperationRequest<SetCustomerOnCartOperationResponse>(
                correlationId, customer.AccountNumber, undefined, true),
            context,
            `add ${customerName} to the sale`);
        if (!added) {
            throw new Error(`Adding ${customerName} to the sale was canceled. ${NOTHING_CHANGED}`);
        }

        changes.push(`added ${customerName} to the sale`);
    }

    if (cart.CartTypeValue !== CART_TYPE_CUSTOMER_ORDER || cart.CustomerOrderModeValue !== ORDER_MODE_CREATE_OR_EDIT) {
        const created: CreateCustomerOrderOperationResponse | undefined = await runAsync<CreateCustomerOrderOperationResponse>(
            new CreateCustomerOrderOperationRequest<CreateCustomerOrderOperationResponse>(correlationId),
            context,
            "make the sale a customer order",
            describeChanges(changes));
        if (!created) {
            throw new Error(`Making the sale a customer order was canceled. ${describeChanges(changes)}`);
        }

        changes.push("made it a customer order");
    }

    const order: ProxyEntities.Cart | undefined = await readCartAsync(
        context, correlationId, "read the customer order", describeChanges(changes));
    if (!order || !isText(order.Id)) {
        throw new Error(`POS couldn't read the customer order. ${describeChanges(changes)}`);
    }

    const lines: ProxyEntities.CartLine[] = [];
    plans.forEach((plan: IShipmentPlan): void => {
        const warehouseId: string | undefined = settings.setWarehouse ? getShipFromWarehouse(plan.store) : undefined;
        plan.shipment.targets.forEach((target: IShippingTarget, index: number): void => {
            const line: ProxyEntities.CartLine | undefined = (order.CartLines || []).filter((candidate: ProxyEntities.CartLine) =>
                candidate && candidate.LineId === target.line.LineId && !candidate.IsVoided)[0];
            if (!line) {
                throw new Error(`${describeLine(target.line)} is no longer on the sale. ${describeChanges(changes)}`);
            }

            lines.push(applyDelivery(line, {
                deliveryModeCode: plan.option.Code,
                charge: plan.charges[index] || 0,
                deliveryDate: deliveryDate,
                address: destination.address,
                fulfillmentStoreId: plan.store.OrgUnitNumber,
                warehouseId: warehouseId
            }));
        });
    });

    const saved: UpdateCartLinesResponse | undefined = await runAsync<UpdateCartLinesResponse>(
        new UpdateCartLinesRequest<UpdateCartLinesResponse>(correlationId, order.Id, lines, order.Version),
        context,
        "save the shipping",
        describeChanges(changes));
    if (!saved || !saved.result) {
        throw new Error(`Commerce didn't confirm the shipping. ${describeChanges(changes)} Open the cart to check it.`);
    }
}

async function readCartAsync(
    context: IExtensionContext,
    correlationId: string,
    step: string,
    afterwards: string
): Promise<ProxyEntities.Cart | undefined> {
    const response: GetCurrentCartClientResponse | undefined = await runAsync<GetCurrentCartClientResponse>(
        new GetCurrentCartClientRequest<GetCurrentCartClientResponse>(correlationId), context, step, afterwards);
    return response?.result;
}

/**
 * Runs a POS request.
 * @returns The response, or undefined when the associate canceled.
 * @throws An Error that says which step failed, why, and what had already changed.
 */
async function runAsync<TResponse extends Response>(
    request: Request<TResponse>,
    context: IExtensionContext,
    step: string,
    afterwards: string = NOTHING_CHANGED
): Promise<TResponse | undefined> {
    let result: ClientEntities.ICancelableDataResult<TResponse>;
    try {
        result = await context.runtime.executeAsync(request);
    } catch (error) {
        throw new Error(`POS couldn't ${step}: ${describeError(error)} ${afterwards}`);
    }

    return result.canceled ? undefined : result.data;
}

/** Reads the reason out of whatever POS or Commerce rejected with. */
function describeError(error: unknown): string {
    const first: unknown = Array.isArray(error) ? error[0] : error;
    let text: string = "";
    if (typeof first === "string") {
        text = first;
    } else if (first && typeof first === "object") {
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
            if (isText(value)) {
                text = value;
                break;
            }
        }
    }

    text = text.trim();
    if (!text) {
        return "Commerce gave no reason.";
    }

    return /[.!?]$/.test(text) ? text : `${text}.`;
}

function describeChanges(changes: string[]): string {
    if (changes.length === 0) {
        return NOTHING_CHANGED;
    }

    return `POS ${changes.join(" and ")}, but shipping wasn't set.`;
}

function describeCustomer(customer: ProxyEntities.Customer): string {
    return isText(customer.Name) ? customer.Name.trim() : customer.AccountNumber;
}

function describeStore(store: ProxyEntities.OrgUnit): string {
    return isText(store.OrgUnitName) ? store.OrgUnitName.trim() : store.OrgUnitNumber;
}

function describeOption(option: ProxyEntities.DeliveryOption): string {
    return isText(option.Description) ? option.Description.trim() : option.Code;
}

function describeProduct(product: ProxyEntities.SimpleProduct): string {
    const values: string[] = (product.Dimensions || [])
        .map((dimension: ProxyEntities.ProductDimension) =>
            dimension && dimension.DimensionValue ? dimension.DimensionValue.Value : undefined)
        .filter(isText)
        .map((value: string) => value.trim());

    return [product.Name.trim()].concat(values).join(" \u00b7 ");
}

function describeTargets(targets: IShippingTarget[]): string {
    return targets.length === 1 ? describeLine(targets[0].line) : `these ${targets.length} products`;
}

function describeCount(count: number): string {
    return count === 1 ? "1 product" : `${count} products`;
}

function possessive(name: string): string {
    return /s$/i.test(name) ? `${name}'` : `${name}'s`;
}

function formatAmount(value: number | undefined): string | undefined {
    if (typeof value !== "number" || !isFinite(value)) {
        return undefined;
    }

    try {
        const text: string = CurrencyFormatter.toCurrency(value);
        if (isText(text)) {
            return text;
        }
    } catch (error) {
        // Shown as a plain amount below.
    }

    return value.toFixed(2);
}

function formatDate(date: Date): string {
    try {
        const text: string = DateFormatter.toShortDate(date);
        if (isText(text)) {
            return text;
        }
    } catch (error) {
        // Shown as a plain date below.
    }

    return date.toDateString();
}
