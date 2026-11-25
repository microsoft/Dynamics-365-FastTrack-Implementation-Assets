/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The rules the shipCart action uses to read the associate's request against the sale, the customer
 * and the delivery modes Commerce offers.
 *
 * Nothing here calls POS, so each rule can be checked on its own and ShipCartHelper reads as the steps
 * it takes. Commerce enumerations are written as their numeric values for the same reason: this module
 * needs no POS API at run time. Every rule that rejects a request throws an Error whose message is
 * shown to the associate, so the messages say what to do next.
 */

import { ProxyEntities } from "PosApi/Entities";
import { IAgentShippingItem, IAgentShippingRequest } from "ContosoSideChat";

/** The furthest ahead a delivery can be requested, in days. */
export const MAX_DELIVERY_DAYS: number = 365;

/** Decimal places shipping charges are split to, as POS does for currencies with cents. */
export const CHARGE_DECIMALS: number = 2;

// ProxyEntities.CartType, CustomerOrderMode and TenderLineStatus values.
const CART_TYPE_NONE: number = 0;
const CART_TYPE_SHOPPING: number = 1;
const CART_TYPE_CUSTOMER_ORDER: number = 3;
const ORDER_MODE_NONE: number = 0;
const ORDER_MODE_CREATE_OR_EDIT: number = 1;
const ORDER_MODE_QUOTE: number = 6;
const TENDER_LINE_VOIDED: number = 3;

/** ProxyEntities.AddressType values, by the names the agent may use. "Work" is a business address. */
const ADDRESS_TYPES: { [name: string]: number } = {
    home: 7,
    work: 9,
    business: 9,
    delivery: 2,
    invoice: 1,
    other: 8
};

/** How an address type reads to the associate. */
const ADDRESS_TYPE_NAMES: { [type: number]: string } = {
    1: "Invoice",
    2: "Delivery",
    3: "Alternate delivery",
    4: "SWIFT",
    5: "Payment",
    6: "Service",
    7: "Home",
    8: "Other",
    9: "Business",
    10: "Remit-to",
    11: "Third-party shipping",
    12: "Statement",
    15: "Fixed asset",
    16: "One-time",
    17: "Recruit",
    18: "SMS",
    101: "Lading",
    102: "Unlading",
    103: "Consignment"
};

/**
 * Words that name an address type in an address's name or its purposes' labels, which stores often use
 * instead of the type: an address of type Other can be named "Home address".
 */
const ADDRESS_TYPE_WORDS: { [type: number]: string[] } = {
    1: ["invoice", "billing"],
    2: ["delivery", "shipping"],
    7: ["home"],
    8: ["other"],
    9: ["work", "business", "office"]
};

/** The most saved addresses a message lists. */
const MAX_LISTED_ADDRESSES: number = 6;

/** Words that say a delivery mode ships, without saying which one. */
const DELIVERY_MODE_FILLER_WORDS: string[] = [
    "a", "an", "the", "by", "via", "with", "use", "using",
    "ship", "shipping", "shipped", "shipment", "delivery", "deliver", "delivered", "mode", "method", "service"
];

/** The fewest letters that may stand for a whole word, as "stand" does for "Standard". */
const MIN_PREFIX_LENGTH: number = 3;

/** One sale line to ship, and the store number it ships from. */
export interface IShippingTarget {
    line: ProxyEntities.CartLine;
    /** Upper case, as Commerce stores organization unit numbers. */
    storeNumber: string;
    /** The agent's item for the line, when the request listed items. */
    item?: IAgentShippingItem;
}

/** The lines that ship from one store. */
export interface IStoreShipment {
    storeNumber: string;
    targets: IShippingTarget[];
}

/** The saved address an order ships to. */
export interface IShippingDestination {
    address: ProxyEntities.Address;
    /** How the address reads, for example "Home". */
    typeName?: string;
}

/** What one shipped line gets. */
export interface ILineDelivery {
    deliveryModeCode: string;
    charge: number;
    deliveryDate: Date;
    address: ProxyEntities.Address;
    fulfillmentStoreId: string;
    /** Set only when Commerce ships from a chosen warehouse; the line keeps its own otherwise. */
    warehouseId?: string;
}

/**
 * Checks the agent's request before POS reads anything.
 * @param request The shipping request the agent returned.
 * @returns What is wrong with it, or undefined when it can be carried out.
 */
export function validateShippingRequest(request: IAgentShippingRequest | undefined): string | undefined {
    if (!request || typeof request !== "object") {
        return "The shipping action didn't say how to ship the sale.";
    }

    if (!isText(request.deliveryMode)) {
        return "Say how the order should ship, for example standard shipping.";
    }

    if (request.deliveryInDays !== undefined && request.deliveryInDays !== null) {
        if (!isWholeNumber(request.deliveryInDays) || request.deliveryInDays < 0 || request.deliveryInDays > MAX_DELIVERY_DAYS) {
            return `The delivery must be between today and ${MAX_DELIVERY_DAYS} days from now.`;
        }
    } else if (!isText(request.deliveryDate)) {
        return "Say when the order should be delivered, for example in 2 days.";
    }

    if (isText(request.addressType) && getAddressType(request.addressType) === undefined
        && normalizeText(request.addressType) !== "primary") {
        return `POS doesn't know a "${request.addressType}" address. Say home, work, delivery, invoice, other or primary.`;
    }

    if (request.items !== undefined && request.items !== null) {
        if (!Array.isArray(request.items)) {
            return "The shipping action listed its products in a form POS can't read.";
        }

        const unreadable: boolean = request.items.some((item: IAgentShippingItem) =>
            !item || typeof item !== "object" || !isRecordId(item.productId));
        if (unreadable) {
            return "The shipping action named a product without its identifier.";
        }
    }

    return undefined;
}

/**
 * Checks that the sale can be set to ship.
 * @param cart The current cart.
 * @returns Why it can't, or undefined when it can.
 */
export function checkSale(cart: ProxyEntities.Cart | undefined): string | undefined {
    if (!cart || !isText(cart.Id)) {
        return "There's no sale to ship. Add the products first.";
    }

    const activeLines: ProxyEntities.CartLine[] = (cart.CartLines || []).filter(
        (line: ProxyEntities.CartLine) => line && !line.IsVoided);
    if (cart.IsReturnByReceipt || activeLines.some((line: ProxyEntities.CartLine) => (line.Quantity || 0) < 0)) {
        return "This sale has returns, so it can't ship. Finish the return first.";
    }

    const cartType: number = typeof cart.CartTypeValue === "number" ? cart.CartTypeValue : CART_TYPE_NONE;
    if (cartType !== CART_TYPE_NONE && cartType !== CART_TYPE_SHOPPING && cartType !== CART_TYPE_CUSTOMER_ORDER) {
        return "Only a sale or a customer order can ship, and this transaction is neither.";
    }

    const orderMode: number = typeof cart.CustomerOrderModeValue === "number" ? cart.CustomerOrderModeValue : ORDER_MODE_NONE;
    if (orderMode === ORDER_MODE_QUOTE) {
        return "This is a quote. Only a sale or a customer order can ship from the chat.";
    }

    if (orderMode !== ORDER_MODE_NONE && orderMode !== ORDER_MODE_CREATE_OR_EDIT) {
        return "This customer order is being picked up, returned or canceled, so it can't ship from the chat.";
    }

    if ((cart.TenderLines || []).some((tenderLine: ProxyEntities.TenderLine) =>
        tenderLine && tenderLine.StatusValue !== TENDER_LINE_VOIDED)) {
        return "Payment has started on this sale. Set up shipping before taking payment.";
    }

    if (isText(cart.DeliveryMode)) {
        return "Delivery is already set for the whole order. Change it in POS with Ship all or Pick up all.";
    }

    if (activeLines.some((line: ProxyEntities.CartLine) => line.IsGiftCardLine)) {
        return "This sale has a gift card, which can't go on a customer order. Sell it separately.";
    }

    if (getSoldLines(cart).length === 0) {
        return "There's nothing on the sale to ship. Add the products first.";
    }

    return undefined;
}

/**
 * Picks the lines that sell a product: not voided, returned, gift card or deposit lines.
 * @param cart The current cart.
 * @returns The lines, in sale order.
 */
export function getSoldLines(cart: ProxyEntities.Cart | undefined): ProxyEntities.CartLine[] {
    return ((cart && cart.CartLines) || []).filter((line: ProxyEntities.CartLine) =>
        line
        && !line.IsVoided
        && !line.IsGiftCardLine
        && !line.IsCustomerAccountDeposit
        && isRecordId(line.ProductId)
        && (line.Quantity || 0) > 0
        && isText(line.LineId));
}

/**
 * Decides which lines ship, and from which store.
 * @param request The shipping request.
 * @param soldLines The lines that sell a product.
 * @param masterProductIds The master of each variant on the sale, so an item may name either.
 * @param currentStoreNumber The associate's store, which ships whatever the request gives no store for.
 * @returns One target per line, in the order the request named them.
 */
export function chooseLinesToShip(
    request: IAgentShippingRequest,
    soldLines: ProxyEntities.CartLine[],
    masterProductIds: { [productId: number]: number },
    currentStoreNumber: string
): IShippingTarget[] {
    const defaultStore: string = normalizeStoreNumber(request.shipFromStoreNumber) || normalizeStoreNumber(currentStoreNumber);
    const items: IAgentShippingItem[] = Array.isArray(request.items) ? request.items : [];

    if (items.length === 0) {
        return soldLines.map((line: ProxyEntities.CartLine): IShippingTarget => ({ line: line, storeNumber: defaultStore }));
    }

    const targetsByLine: { [lineId: string]: IShippingTarget } = {};
    const lineOrder: string[] = [];
    items.forEach((item: IAgentShippingItem): void => {
        let lines: ProxyEntities.CartLine[] = soldLines.filter((line: ProxyEntities.CartLine) => line.ProductId === item.productId);
        if (lines.length === 0) {
            lines = soldLines.filter((line: ProxyEntities.CartLine) => masterProductIds[line.ProductId] === item.productId);
        }

        if (lines.length === 0) {
            throw new Error(`Product ${item.productId} isn't on the sale. Nothing was changed.`);
        }

        const storeNumber: string = normalizeStoreNumber(item.shipFromStoreNumber) || defaultStore;
        lines.forEach((line: ProxyEntities.CartLine): void => {
            const existing: IShippingTarget | undefined = targetsByLine[line.LineId];
            if (existing) {
                if (existing.storeNumber !== storeNumber) {
                    throw new Error(`${describeLine(line)} can ship from only one store. Nothing was changed.`);
                }

                return;
            }

            targetsByLine[line.LineId] = { line: line, storeNumber: storeNumber, item: item };
            lineOrder.push(line.LineId);
        });
    });

    return lineOrder.map((lineId: string) => targetsByLine[lineId]);
}

/**
 * Groups the lines by the store that ships them, in the order the stores first appear.
 * @param targets The lines to ship.
 * @returns One shipment per store.
 */
export function groupByStore(targets: IShippingTarget[]): IStoreShipment[] {
    const shipments: IStoreShipment[] = [];
    targets.forEach((target: IShippingTarget): void => {
        const shipment: IStoreShipment | undefined = shipments.filter(
            (candidate: IStoreShipment) => candidate.storeNumber === target.storeNumber)[0];
        if (shipment) {
            shipment.targets.push(target);
        } else {
            shipments.push({ storeNumber: target.storeNumber, targets: [target] });
        }
    });

    return shipments;
}

/**
 * Normalizes a person's name for comparison: lower case, without possessives, punctuation or extra
 * spaces. "Karen Berg's" becomes "karen berg".
 * @param value The name.
 * @returns The normalized name, empty when there is none.
 */
export function normalizeName(value: string | undefined): string {
    if (typeof value !== "string") {
        return "";
    }

    return value
        .toLowerCase()
        .replace(/[\u2018\u2019\u02bc`]/g, "'")
        .replace(/'s\b/g, "")
        .replace(/[^a-z0-9\u00c0-\u024f]+/g, " ")
        .trim();
}

/**
 * Turns the name the associate said into a customer search keyword: without a possessive or extra
 * spaces, otherwise as said.
 * @param value The name.
 * @returns The keyword.
 */
export function toSearchKeyword(value: string): string {
    return value
        .replace(/[\u2018\u2019\u02bc`]/g, "'")
        .replace(/'s\b/gi, "")
        .replace(/\s+/g, " ")
        .trim();
}

/**
 * Picks the customers a name means, out of a customer search.
 * @param name The name the associate said.
 * @param customers What the search found.
 * @returns The customers named exactly that if there are any, otherwise those whose name contains every
 * word of it. One per account; empty when none match.
 */
export function matchCustomersByName(name: string, customers: ProxyEntities.GlobalCustomer[]): ProxyEntities.GlobalCustomer[] {
    const wanted: string = normalizeName(name);
    if (!wanted) {
        return [];
    }

    const accounts: string[] = [];
    const unique: ProxyEntities.GlobalCustomer[] = (customers || []).filter((customer: ProxyEntities.GlobalCustomer) => {
        if (!customer || !isText(customer.AccountNumber)) {
            return false;
        }

        const account: string = customer.AccountNumber.toUpperCase();
        if (accounts.indexOf(account) >= 0) {
            return false;
        }

        accounts.push(account);
        return true;
    });

    const exact: ProxyEntities.GlobalCustomer[] = unique.filter(
        (customer: ProxyEntities.GlobalCustomer) => normalizeName(customer.FullName) === wanted);
    if (exact.length > 0) {
        return exact;
    }

    const words: string[] = wanted.split(" ");
    return unique.filter((customer: ProxyEntities.GlobalCustomer) =>
        containsAll(splitWords(normalizeName(customer.FullName)), words));
}

/**
 * Answers whether a customer is the one the associate named.
 * @param said The name the associate said.
 * @param customerName The customer's name.
 * @returns True when the names match, or the customer's name contains every word the associate said.
 */
export function isSameCustomerName(said: string, customerName: string | undefined): boolean {
    const wanted: string = normalizeName(said);
    const actual: string = normalizeName(customerName);
    if (!wanted || !actual) {
        return false;
    }

    return wanted === actual || containsAll(actual.split(" "), wanted.split(" "));
}

/**
 * Picks the saved address to ship to.
 * @param addresses The customer's saved addresses.
 * @param addressType The kind of address the associate asked for. The primary address when omitted.
 * @param customerName The customer's name, for messages.
 * @returns The address, and how its kind reads. An address of the kind's type comes first, then one whose
 * purpose labels name the kind, then one whose name does, as "Home address" does; the primary one first
 * in each.
 */
export function pickShippingAddress(
    addresses: ProxyEntities.Address[] | undefined,
    addressType: string | undefined,
    customerName: string
): IShippingDestination {
    const usable: ProxyEntities.Address[] = (addresses || []).filter((address: ProxyEntities.Address) =>
        address && !address.Deactivate && (address.RecordId || 0) > 0);
    if (usable.length === 0) {
        throw new Error(`${customerName} has no saved address to ship to. Add one in POS first. Nothing was changed.`);
    }

    const wanted: string = normalizeText(addressType);
    if (!wanted || wanted === "primary") {
        const primary: ProxyEntities.Address | undefined = usable.filter((address: ProxyEntities.Address) => address.IsPrimary)[0]
            || (usable.length === 1 ? usable[0] : undefined);
        if (!primary) {
            throw new Error(`${customerName} has no primary address. Saved addresses: ${listSavedAddresses(usable)}. `
                + "Say which one to use. Nothing was changed.");
        }

        return { address: primary, typeName: describeAddressType(primary) };
    }

    const type: number | undefined = getAddressType(wanted);
    const words: string[] = type === undefined ? [] : (ADDRESS_TYPE_WORDS[type] || [wanted]);
    const tiers: ProxyEntities.Address[][] = type === undefined ? [] : [
        usable.filter((address: ProxyEntities.Address) => hasAddressType(address, type)),
        usable.filter((address: ProxyEntities.Address) => (address.AddressPurposes || []).some((purpose: ProxyEntities.AddressPurpose) =>
            purpose && (hasAnyWord(purpose.Description, words) || hasAnyWord(purpose.Name, words)))),
        usable.filter((address: ProxyEntities.Address) => hasAnyWord(address.Name, words))
    ];
    const matches: ProxyEntities.Address[] = tiers.filter((tier: ProxyEntities.Address[]) => tier.length > 0)[0] || [];
    const label: string = wanted.charAt(0).toUpperCase() + wanted.slice(1);
    if (matches.length === 0) {
        throw new Error(`${customerName} has no ${wanted} address. Saved addresses: ${listSavedAddresses(usable)}. `
            + "Nothing was changed.");
    }

    const chosen: ProxyEntities.Address = matches.filter((address: ProxyEntities.Address) => address.IsPrimary)[0] || matches[0];
    return { address: chosen, typeName: label };
}

/**
 * Reduces an address to the fields Commerce reads to work out delivery modes, as the POS shipping
 * screen sends it.
 * @param address The address to ship to.
 * @returns The reduced address.
 */
export function toDeliveryAddress(address: ProxyEntities.Address): ProxyEntities.Address {
    return {
        Name: address.Name,
        RecordId: address.RecordId,
        ThreeLetterISORegionName: address.ThreeLetterISORegionName,
        TwoLetterISORegionName: address.TwoLetterISORegionName,
        State: address.State,
        County: address.County,
        City: address.City,
        DistrictName: address.DistrictName,
        Street: address.Street,
        StreetNumber: address.StreetNumber,
        ZipCode: address.ZipCode,
        Email: address.Email,
        Phone: address.Phone,
        Url: address.Url
    };
}

/**
 * Lists the delivery modes that can ship every line, as the POS shipping screen does, leaving out
 * the pickup, carry-out and email modes, which don't ship.
 * @param lineOptions The delivery modes Commerce returned for each line.
 * @param lineIds The lines that ship together.
 * @param excludedCodes The codes of the modes that don't ship.
 * @returns The modes, in the order Commerce listed them for the first line.
 */
export function getShippableOptions(
    lineOptions: ProxyEntities.SalesLineDeliveryOption[] | undefined,
    lineIds: string[],
    excludedCodes: string[]
): ProxyEntities.DeliveryOption[] {
    if (lineIds.length === 0) {
        return [];
    }

    const optionsByLine: { [lineId: string]: ProxyEntities.DeliveryOption[] } = {};
    (lineOptions || []).forEach((lineOption: ProxyEntities.SalesLineDeliveryOption): void => {
        if (lineOption && isText(lineOption.SalesLineId)) {
            optionsByLine[lineOption.SalesLineId] = (lineOption.DeliveryOptions || []).filter(
                (option: ProxyEntities.DeliveryOption) => option && isText(option.Code));
        }
    });

    const excluded: string[] = excludedCodes.filter(isText).map((code: string) => code.toUpperCase());
    const seen: string[] = [];
    return (optionsByLine[lineIds[0]] || []).filter((option: ProxyEntities.DeliveryOption) => {
        const code: string = option.Code.toUpperCase();
        if (excluded.indexOf(code) >= 0 || seen.indexOf(code) >= 0) {
            return false;
        }

        seen.push(code);
        return lineIds.every((lineId: string) => (optionsByLine[lineId] || []).some(
            (candidate: ProxyEntities.DeliveryOption) => candidate.Code.toUpperCase() === code));
    });
}

/**
 * Finds the delivery mode the associate named among those that can ship the lines.
 * @param said The delivery mode as the associate said it, for example "standard shipping".
 * @param options The modes that can ship the lines.
 * @returns The one mode meant.
 */
export function matchDeliveryOption(said: string, options: ProxyEntities.DeliveryOption[]): ProxyEntities.DeliveryOption {
    if (options.length === 0) {
        throw new Error("No delivery mode can ship these products to that address. Nothing was changed.");
    }

    const wanted: string = normalizeText(said);
    const exact: ProxyEntities.DeliveryOption[] = options.filter((option: ProxyEntities.DeliveryOption) =>
        normalizeText(option.Description) === wanted || normalizeText(option.Code) === wanted);
    if (exact.length > 0) {
        return pickOne(said, exact);
    }

    const words: string[] = getModeWords(said);
    if (words.length === 0) {
        return pickOne(said, options);
    }

    // A mode named by exactly these words wins over modes that only contain them: "standard shipping" is Standard, not Standard overnight.
    const byWholeName: ProxyEntities.DeliveryOption[] = options.filter((option: ProxyEntities.DeliveryOption) =>
        hasSameWords(getModeWords(option.Description), words) || hasSameWords(getModeWords(option.Code), words));
    if (byWholeName.length > 0) {
        return pickOne(said, byWholeName);
    }

    const byWords: ProxyEntities.DeliveryOption[] = options.filter((option: ProxyEntities.DeliveryOption) =>
        containsAll(getOptionWords(option), words));
    if (byWords.length > 0) {
        return pickOne(said, byWords);
    }

    const byPrefix: ProxyEntities.DeliveryOption[] = options.filter((option: ProxyEntities.DeliveryOption) => {
        const optionWords: string[] = getOptionWords(option);
        return words.every((word: string) => optionWords.some((optionWord: string) =>
            isPrefix(word, optionWord) || isPrefix(optionWord, word)));
    });
    if (byPrefix.length > 0) {
        return pickOne(said, byPrefix);
    }

    throw new Error(`There's no "${said.trim()}" delivery for this sale. Available: ${listDeliveryOptions(options)}. `
        + "Nothing was changed.");
}

/**
 * Works out the requested delivery date: noon on the day, so no time zone moves it to another day.
 * @param today Now.
 * @param deliveryInDays Days from today, when the associate said "in 2 days". Wins over the date.
 * @param deliveryDate The date the associate gave, as YYYY-MM-DD.
 * @returns The date.
 */
export function computeDeliveryDate(today: Date, deliveryInDays: number | undefined, deliveryDate: string | undefined): Date {
    const start: Date = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12, 0, 0, 0);

    if (typeof deliveryInDays === "number") {
        if (!isWholeNumber(deliveryInDays) || deliveryInDays < 0 || deliveryInDays > MAX_DELIVERY_DAYS) {
            throw new Error(`The delivery must be between today and ${MAX_DELIVERY_DAYS} days from now. Nothing was changed.`);
        }

        return new Date(start.getFullYear(), start.getMonth(), start.getDate() + deliveryInDays, 12, 0, 0, 0);
    }

    const match: RegExpExecArray | null = /^(\d{4})-(\d{2})-(\d{2})$/.exec(typeof deliveryDate === "string" ? deliveryDate.trim() : "");
    if (!match) {
        throw new Error("Say when the order should be delivered, for example in 2 days. Nothing was changed.");
    }

    const year: number = Number(match[1]);
    const month: number = Number(match[2]) - 1;
    const day: number = Number(match[3]);
    const date: Date = new Date(year, month, day, 12, 0, 0, 0);
    if (date.getFullYear() !== year || date.getMonth() !== month || date.getDate() !== day) {
        throw new Error(`${match[0]} isn't a date. Nothing was changed.`);
    }

    const days: number = Math.round((date.getTime() - start.getTime()) / 86400000);
    if (days < 0) {
        throw new Error("That delivery date has passed. Say a date from today on. Nothing was changed.");
    }

    if (days > MAX_DELIVERY_DAYS) {
        throw new Error(`The delivery must be within ${MAX_DELIVERY_DAYS} days. Nothing was changed.`);
    }

    return date;
}

/**
 * Splits a shipping charge across lines as POS does: an equal, rounded share each, with the rounding
 * difference on the last line. 10.00 across three lines is 3.33, 3.33 and 3.34.
 * @param total The charge.
 * @param count How many lines share it.
 * @param decimals The decimal places to round to.
 * @returns Each line's share, in line order.
 */
export function splitCharge(total: number, count: number, decimals: number): number[] {
    if (count <= 0) {
        return [];
    }

    const factor: number = Math.pow(10, decimals);
    const round = (value: number): number => Math.round(value * factor) / factor;
    const share: number = round(total / count);
    const charges: number[] = [];
    for (let index: number = 0; index < count; index++) {
        charges.push(share);
    }

    const remainder: number = round(total - share * count);
    if (remainder !== 0) {
        charges[count - 1] = round(charges[count - 1] + remainder);
    }

    return charges;
}

/**
 * The address a store ships from, as the POS shipping screen shows it in the charge dialog.
 * @param store The store.
 * @returns Its shipping warehouse's address when it has one, otherwise its own.
 */
export function getShipFromAddress(store: ProxyEntities.OrgUnit): ProxyEntities.Address {
    const warehouse: ProxyEntities.Address | undefined = store.ShippingWarehouseAddress;
    if (warehouse && (warehouse.RecordId || 0) !== 0) {
        return { ...warehouse, Name: warehouse.Name || store.OrgUnitName };
    }

    if (store.OrgUnitAddress) {
        return { ...store.OrgUnitAddress, Name: store.OrgUnitAddress.Name || store.OrgUnitName };
    }

    return { Name: "" };
}

/**
 * The warehouse a store ships from.
 * @param store The store.
 * @returns Its shipping warehouse, otherwise its own inventory location; empty when it has neither.
 */
export function getShipFromWarehouse(store: ProxyEntities.OrgUnit): string {
    const warehouse: ProxyEntities.WarehouseDetails | undefined = store.ShippingWarehouseAddress as ProxyEntities.WarehouseDetails;
    if (warehouse && isText(warehouse.InventoryLocationId)) {
        return warehouse.InventoryLocationId;
    }

    return isText(store.InventoryLocationId) ? store.InventoryLocationId : "";
}

/**
 * Sets one line to ship, the way the POS Ship selected operation does.
 * @param line The line, as the cart holds it now.
 * @param delivery What it ships with.
 * @returns A changed copy; the line itself is left alone.
 */
export function applyDelivery(line: ProxyEntities.CartLine, delivery: ILineDelivery): ProxyEntities.CartLine {
    const updated: ProxyEntities.CartLine = { ...line };
    updated.DeliveryMode = delivery.deliveryModeCode;
    updated.DeliveryModeChargeAmount = delivery.charge;
    updated.RequestedDeliveryDate = delivery.deliveryDate;
    updated.PickupTimeslotStartDateTime = undefined;
    updated.PickupTimeslotEndDateTime = undefined;
    updated.ShippingAddress = delivery.address;
    updated.FulfillmentStoreId = delivery.fulfillmentStoreId;
    if (isText(delivery.warehouseId)) {
        updated.WarehouseId = delivery.warehouseId;
    }

    updated.Expedite = "";
    return updated;
}

/**
 * Describes a line for a message.
 * @param line The line.
 * @returns Its description, otherwise its item number.
 */
export function describeLine(line: ProxyEntities.CartLine): string {
    return isText(line.Description) ? line.Description.trim() : (isText(line.ItemId) ? line.ItemId : "A product");
}

/**
 * Formats an address on one line.
 * @param address The address.
 * @returns Its full address with commas for line breaks, otherwise its street, city, state and ZIP code.
 */
export function formatAddress(address: ProxyEntities.Address): string {
    if (isText(address.FullAddress)) {
        return address.FullAddress.replace(/\s*[\r\n]+\s*/g, ", ").replace(/,\s*,/g, ",").trim();
    }

    return [address.Street, address.City, address.State, address.ZipCode]
        .filter((part: string | undefined): part is string => isText(part))
        .map((part: string) => part.trim())
        .join(", ");
}

/**
 * Describes what the agent reported about the store that ships a line.
 * @param item The agent's item for the line.
 * @returns For example "195.3 mi · 4 available"; undefined when it reported nothing usable.
 */
export function describeShipFromStock(item: IAgentShippingItem | undefined): string | undefined {
    if (!item) {
        return undefined;
    }

    const parts: string[] = [];
    if (isText(item.distance)) {
        parts.push(item.distance.trim());
    }

    if (typeof item.availableQuantity === "number" && isFinite(item.availableQuantity) && item.availableQuantity >= 0) {
        parts.push(`${item.availableQuantity} available`);
    }

    return parts.length > 0 ? parts.join(" \u00b7 ") : undefined;
}

/**
 * Answers whether a value is text with something other than spaces in it.
 * @param value The value.
 * @returns True for non-blank text.
 */
export function isText(value: unknown): value is string {
    return typeof value === "string" && value.trim().length > 0;
}

function isRecordId(value: unknown): boolean {
    return typeof value === "number" && isFinite(value) && value > 0;
}

function isWholeNumber(value: unknown): value is number {
    return typeof value === "number" && isFinite(value) && Math.floor(value) === value;
}

function normalizeStoreNumber(value: string | undefined): string {
    return isText(value) ? value.trim().toUpperCase() : "";
}

function normalizeText(value: string | undefined): string {
    if (typeof value !== "string") {
        return "";
    }

    return value
        .toLowerCase()
        .replace(/(\d)([a-z])/g, "$1 $2")
        .replace(/([a-z])(\d)/g, "$1 $2")
        .replace(/[^a-z0-9\u00c0-\u024f]+/g, " ")
        .trim();
}

function splitWords(value: string): string[] {
    return value ? value.split(" ") : [];
}

function containsAll(words: string[], wanted: string[]): boolean {
    return wanted.every((word: string) => words.indexOf(word) >= 0);
}

function hasSameWords(words: string[], wanted: string[]): boolean {
    return words.length === wanted.length && containsAll(words, wanted) && containsAll(wanted, words);
}

/** The words of a delivery mode, or of what the associate said, that tell one mode from another. */
function getModeWords(value: string | undefined): string[] {
    return splitWords(normalizeText(value)).filter((word: string) => DELIVERY_MODE_FILLER_WORDS.indexOf(word) < 0);
}

/** Answers whether a word starts another, ignoring a letter or two, which start too many words. */
function isPrefix(prefix: string, word: string): boolean {
    return prefix.length >= MIN_PREFIX_LENGTH && word.indexOf(prefix) === 0;
}

function getOptionWords(option: ProxyEntities.DeliveryOption): string[] {
    return splitWords(normalizeText(option.Description)).concat(splitWords(normalizeText(option.Code)));
}

function pickOne(said: string, candidates: ProxyEntities.DeliveryOption[]): ProxyEntities.DeliveryOption {
    if (candidates.length === 1) {
        return candidates[0];
    }

    throw new Error(`"${said.trim()}" could be ${listDeliveryOptions(candidates)}. Say which one. Nothing was changed.`);
}

function listDeliveryOptions(options: ProxyEntities.DeliveryOption[]): string {
    return options.map((option: ProxyEntities.DeliveryOption) => isText(option.Description) ? option.Description.trim() : option.Code)
        .join(", ");
}

function getAddressType(name: string): number | undefined {
    const key: string = normalizeText(name);
    return Object.prototype.hasOwnProperty.call(ADDRESS_TYPES, key) ? ADDRESS_TYPES[key] : undefined;
}

function hasAddressType(address: ProxyEntities.Address, type: number): boolean {
    return address.AddressTypeValue === type
        || (address.AddressPurposes || []).some((purpose: ProxyEntities.AddressPurpose) => purpose && purpose.AddressType === type);
}

function describeAddressType(address: ProxyEntities.Address): string | undefined {
    const type: number | undefined = typeof address.AddressTypeValue === "number"
        ? address.AddressTypeValue
        : ((address.AddressPurposes || [])[0] || { AddressType: undefined }).AddressType;

    return typeof type === "number" ? ADDRESS_TYPE_NAMES[type] : undefined;
}

function hasAnyWord(value: string | undefined, words: string[]): boolean {
    const said: string[] = splitWords(normalizeText(value));
    return words.some((word: string) => said.indexOf(word) >= 0);
}

/** Lists saved addresses as POS shows them: by name, with their types and purposes, for example "Home address (Other)". */
function listSavedAddresses(addresses: ProxyEntities.Address[]): string {
    const names: string[] = [];
    addresses.forEach((address: ProxyEntities.Address): void => {
        addUnique(names, describeSavedAddress(address));
    });

    const more: number = names.length - MAX_LISTED_ADDRESSES;
    return more > 0
        ? `${names.slice(0, MAX_LISTED_ADDRESSES).join(", ")} and ${more} more`
        : names.join(", ");
}

function describeSavedAddress(address: ProxyEntities.Address): string {
    const kinds: string[] = [];
    addUnique(kinds, getAddressTypeName(address.AddressTypeValue));
    (address.AddressPurposes || []).forEach((purpose: ProxyEntities.AddressPurpose): void => {
        if (purpose) {
            addUnique(kinds, isText(purpose.Description) ? purpose.Description
                : (isText(purpose.Name) ? purpose.Name : getAddressTypeName(purpose.AddressType)));
        }
    });

    if (!isText(address.Name)) {
        return kinds.length > 0 ? kinds.join("/") : (isText(address.Street) ? address.Street.trim() : "one with no name or type");
    }

    const name: string = address.Name.trim();
    const others: string[] = kinds.filter((kind: string) => kind.toLowerCase() !== name.toLowerCase());
    return others.length > 0 ? `${name} (${others.join("/")})` : name;
}

function getAddressTypeName(type: number | undefined): string | undefined {
    return typeof type === "number" && Object.prototype.hasOwnProperty.call(ADDRESS_TYPE_NAMES, type)
        ? ADDRESS_TYPE_NAMES[type]
        : undefined;
}

/** Adds text to a list unless it is blank or listed already, in any case. */
function addUnique(list: string[], value: string | undefined): void {
    const text: string = isText(value) ? value.trim() : "";
    if (text && !list.some((listed: string) => listed.toLowerCase() === text.toLowerCase())) {
        list.push(text);
    }
}
