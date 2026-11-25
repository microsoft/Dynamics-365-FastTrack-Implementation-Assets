/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Looks up a customer order by its number, for the Customer order lookup view and the agent's
 * `retryOrderLookup` action.
 *
 * When a lookup fails, POS tells the side panel what failed, with the diagnostic context the Adventure
 * Works IT support guide (AW-POS-IT-014) asks for: the error code, the store and register, the POS
 * version, when it happened, the correlation identifier and whether POS was online. The agent then
 * answers from the guide, which allows one retry and then an email to IT support.
 *
 * Commerce rarely fails a lookup on demand, so while SIMULATE_OUTAGE_BY_DEFAULT is on, every lookup fails
 * without calling Commerce. The simulated failure is reported exactly like a real one; only the call to
 * Commerce is skipped, and the page does not say it was simulated.
 *
 * The state lives in this module rather than in the view, because the agent can retry the lookup from
 * the panel while the view shows the result.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import {
    GetApplicationVersionClientRequest,
    GetApplicationVersionClientResponse,
    GetConnectionStatusClientRequest,
    GetConnectionStatusClientResponse,
    GetDeviceConfigurationClientRequest,
    GetDeviceConfigurationClientResponse
} from "PosApi/Consume/Device";
import {
    GetSalesOrderDetailsBySalesIdServiceRequest,
    GetSalesOrderDetailsBySalesIdServiceResponse
} from "PosApi/Consume/SalesOrders";
import { ObjectExtensions, StringExtensions } from "PosApi/TypeExtensions";
import * as SideChat from "ContosoSideChat";

/** The error code the IT support guide is keyed on. */
export const CUSTOMER_ORDER_LOOKUP_FAILED: string = "CUSTOMER_ORDER_LOOKUP_FAILED";

/** The operation's name, as POS reports it and the IT support guide knows it. */
export const CUSTOMER_ORDER_LOOKUP_OPERATION: string = "Customer order lookup";

/** What POS shows when a lookup fails. */
export const CUSTOMER_ORDER_LOOKUP_FAILED_MESSAGE: string = "The customer order could not be retrieved.";

/** How many times the IT support guide lets the associate retry a failed lookup. */
export const MAX_LOOKUP_RETRIES: number = 1;

/**
 * Whether lookups fail without calling Commerce, so that the Customer order lookup page always has an
 * error to get help with. Set it to false to look up real orders.
 */
const SIMULATE_OUTAGE_BY_DEFAULT: boolean = true;

/** How long a simulated lookup takes, so it looks like a call to Commerce. */
const SIMULATED_LOOKUP_DELAY_MS: number = 1200;

/** Commerce's number for being online. The other connection states are kinds of offline. */
const CONNECTION_STATUS_ONLINE: number = 0;

/** The longest order number accepted. Commerce sales order numbers are much shorter. */
const MAX_ORDER_NUMBER_LENGTH: number = 40;

/** Where a lookup stands. */
export type CustomerOrderLookupStatus = "idle" | "searching" | "found" | "notFound" | "failed";

/** The order a lookup found, as the view shows it. */
export interface ICustomerOrderSummary {
    orderNumber: string;
    customerName?: string;
    customerAccount?: string;
    total?: number;
    currency?: string;
    createdOn?: Date;
    lineCount: number;
}

/** The last lookup, as the view shows it. */
export interface ICustomerOrderLookupState {
    status: CustomerOrderLookupStatus;
    /** The order number looked up last. */
    orderNumber: string;
    /** How many times the failed lookup was retried. */
    retryCount: number;
    /** True while lookups fail without calling Commerce. */
    simulateOutage: boolean;
    /** Present when the lookup failed: what POS reported to the panel. */
    error?: SideChat.IAgentPosErrorContext;
    /** Present when the lookup found the order. */
    order?: ICustomerOrderSummary;
}

/** How a lookup turned out, for the agent's retry. */
export interface ICustomerOrderLookupResult {
    status: CustomerOrderLookupStatus;
    order?: ICustomerOrderSummary;
    error?: SideChat.IAgentPosErrorContext;
}

type LookupListener = (state: ICustomerOrderLookupState) => void;

let state: ICustomerOrderLookupState = createInitialState();
let lookupNumber: number = 0;
const listeners: LookupListener[] = [];

function createInitialState(): ICustomerOrderLookupState {
    return { status: "idle", orderNumber: StringExtensions.EMPTY, retryCount: 0, simulateOutage: SIMULATE_OUTAGE_BY_DEFAULT };
}

function setState(next: ICustomerOrderLookupState): void {
    state = next;
    listeners.slice().forEach((listener: LookupListener) => listener(state));
}

/**
 * Reads the last lookup.
 * @returns The state, which callers must not change.
 */
export function getCustomerOrderLookupState(): ICustomerOrderLookupState {
    return state;
}

/**
 * Tells the caller whenever a lookup starts or finishes, from the view or from the agent.
 * @param listener Called with the new state.
 * @returns A function that stops the notifications.
 */
export function subscribeToCustomerOrderLookup(listener: LookupListener): () => void {
    listeners.push(listener);
    return (): void => {
        const index: number = listeners.indexOf(listener);
        if (index >= 0) {
            listeners.splice(index, 1);
        }
    };
}

/**
 * Turns the simulated outage on or off, for tests and for debugging. Takes effect from the next lookup.
 * @param simulateOutage True to fail every lookup without calling Commerce.
 */
export function setSimulateOutage(simulateOutage: boolean): void {
    if (state.simulateOutage !== simulateOutage) {
        setState({ ...state, simulateOutage: simulateOutage });
    }
}

/**
 * Forgets the last lookup, for example when the operator signs out. A lookup still running is ignored
 * when it finishes.
 */
export function resetCustomerOrderLookup(): void {
    lookupNumber += 1;
    setState(createInitialState());
}

/**
 * Looks up a customer order by its number. A failure is reported to the side panel, and a lookup that
 * finds the order, or finds there is none, clears the failure.
 * @param orderNumber The order number the associate entered.
 * @param context The POS extension context.
 * @param retryCount How many times this lookup was already retried. 0 for a new lookup.
 * @returns How the lookup turned out.
 */
export async function lookUpCustomerOrderAsync(
    orderNumber: string,
    context: IExtensionContext,
    retryCount: number = 0
): Promise<ICustomerOrderLookupResult> {
    const salesId: string = (orderNumber || StringExtensions.EMPTY).trim().slice(0, MAX_ORDER_NUMBER_LENGTH);
    if (salesId.length === 0) {
        throw new Error("Enter an order number to look up.");
    }

    lookupNumber += 1;
    const thisLookup: number = lookupNumber;
    const simulateOutage: boolean = state.simulateOutage;
    const correlationId: string = context.logger.getNewCorrelationId();
    setState({ status: "searching", orderNumber: salesId, retryCount: retryCount, simulateOutage: simulateOutage });

    let result: ICustomerOrderLookupResult;
    if (simulateOutage) {
        await delayAsync(SIMULATED_LOOKUP_DELAY_MS);
        context.logger.logInformational(
            `Customer order lookup: simulated a ${CUSTOMER_ORDER_LOOKUP_FAILED} failure for order ${salesId}.`);
        result = { status: "failed" };
    } else {
        result = await readOrderAsync(salesId, correlationId, context);
    }

    if (result.status === "failed") {
        result.error = await describeFailureAsync(salesId, correlationId, retryCount, context);
    }

    // Signed out, or a newer lookup started, while this one ran.
    if (thisLookup !== lookupNumber) {
        return result;
    }

    if (result.error) {
        SideChat.reportPosError(result.error);
    } else if (result.status === "found" || result.status === "notFound") {
        SideChat.clearPosError();
    }

    setState({
        status: result.status,
        orderNumber: salesId,
        retryCount: retryCount,
        simulateOutage: state.simulateOutage,
        error: result.error,
        order: result.order
    });
    return result;
}

/**
 * Retries the lookup that failed last, once, as the IT support guide allows: only while POS is online,
 * and never a second time.
 * @param context The POS extension context.
 * @returns A short summary for the panel when the retry finds the order, or finds there is none.
 * @throws When there is nothing to retry, when the rules do not allow a retry, or when it fails again or is canceled.
 */
export async function retryCustomerOrderLookupAsync(context: IExtensionContext): Promise<string> {
    const failure: SideChat.IAgentPosErrorContext | null = SideChat.getPosError();
    if (!failure || failure.code !== CUSTOMER_ORDER_LOOKUP_FAILED) {
        throw new Error("There is no failed customer order lookup to retry.");
    }

    if (failure.retryCount >= MAX_LOOKUP_RETRIES) {
        throw new Error("The lookup was already retried once, so it was not retried again. Contact IT support "
            + "with the error details.");
    }

    const orderNumber: string = failure.orderNumber || state.orderNumber;
    if (StringExtensions.isNullOrWhitespace(orderNumber)) {
        throw new Error("POS does not know which order to look up again.");
    }

    const correlationId: string = context.logger.getNewCorrelationId();
    if (await readConnectivityAsync(correlationId, context) === "Offline") {
        throw new Error("POS is offline. Customer order lookup needs a connection to Commerce, so it was not retried.");
    }

    const result: ICustomerOrderLookupResult =
        await lookUpCustomerOrderAsync(orderNumber, context, failure.retryCount + 1);
    if (result.status === "found" && result.order) {
        return result.order.customerName
            ? `Retried the lookup. Found order ${result.order.orderNumber} for ${result.order.customerName}.`
            : `Retried the lookup. Found order ${result.order.orderNumber}.`;
    }

    if (result.status === "notFound") {
        return `Retried the lookup. Commerce has no order ${orderNumber}.`;
    }

    if (result.status === "idle") {
        throw new Error("The retried lookup was canceled before it finished.");
    }

    throw new Error(`The lookup failed again with ${CUSTOMER_ORDER_LOOKUP_FAILED}. It will not be retried again.`);
}

/**
 * Reads the order from Commerce.
 * @param salesId The order number.
 * @param correlationId The correlation identifier of the lookup.
 * @param context The POS extension context.
 * @returns The order, "notFound" when Commerce has no such order, or "failed".
 */
async function readOrderAsync(
    salesId: string,
    correlationId: string,
    context: IExtensionContext
): Promise<ICustomerOrderLookupResult> {
    try {
        const response: ClientEntities.ICancelableDataResult<GetSalesOrderDetailsBySalesIdServiceResponse> =
            await context.runtime.executeAsync(new GetSalesOrderDetailsBySalesIdServiceRequest(correlationId, salesId));
        if (response.canceled) {
            return { status: "idle" };
        }

        const order: Readonly<ProxyEntities.SalesOrder> | undefined = response.data?.salesOrder;
        if (ObjectExtensions.isNullOrUndefined(order)) {
            return { status: "notFound" };
        }

        return { status: "found", order: summarizeOrder(order, salesId) };
    } catch (error) {
        if (isNotFoundError(error)) {
            return { status: "notFound" };
        }

        context.logger.logError(`Customer order lookup: order ${salesId} could not be retrieved. ${describeError(error)}`, correlationId);
        return { status: "failed" };
    }
}

function summarizeOrder(order: Readonly<ProxyEntities.SalesOrder>, salesId: string): ICustomerOrderSummary {
    const summary: ICustomerOrderSummary = {
        orderNumber: order.SalesId || salesId,
        lineCount: (order.SalesLines ?? []).length
    };

    if (!StringExtensions.isNullOrWhitespace(order.CustomerName)) {
        summary.customerName = order.CustomerName;
    } else if (!StringExtensions.isNullOrWhitespace(order.Name)) {
        summary.customerName = order.Name;
    }

    if (!StringExtensions.isNullOrWhitespace(order.CustomerId)) {
        summary.customerAccount = order.CustomerId;
    }

    if (typeof order.TotalAmount === "number" && isFinite(order.TotalAmount)) {
        summary.total = order.TotalAmount;
    }

    if (!StringExtensions.isNullOrWhitespace(order.CurrencyCode)) {
        summary.currency = order.CurrencyCode;
    }

    if (order.CreatedDateTime instanceof Date && !isNaN(order.CreatedDateTime.getTime())) {
        summary.createdOn = order.CreatedDateTime;
    }

    return summary;
}

/**
 * Collects what the IT support guide asks for about a failed lookup. Each part is read on its own, so
 * one that cannot be read leaves only itself out.
 */
async function describeFailureAsync(
    salesId: string,
    correlationId: string,
    retryCount: number,
    context: IExtensionContext
): Promise<SideChat.IAgentPosErrorContext> {
    const failure: SideChat.IAgentPosErrorContext = {
        code: CUSTOMER_ORDER_LOOKUP_FAILED,
        message: CUSTOMER_ORDER_LOOKUP_FAILED_MESSAGE,
        operation: CUSTOMER_ORDER_LOOKUP_OPERATION,
        correlationId: correlationId,
        occurredAt: formatLocalTimestamp(new Date()),
        retryCount: retryCount,
        orderNumber: salesId
    };

    try {
        const device: ClientEntities.ICancelableDataResult<GetDeviceConfigurationClientResponse> =
            await context.runtime.executeAsync(
                new GetDeviceConfigurationClientRequest<GetDeviceConfigurationClientResponse>(correlationId));
        const configuration: ProxyEntities.DeviceConfiguration | undefined = device.canceled ? undefined : device.data?.result;
        if (configuration && !StringExtensions.isNullOrWhitespace(configuration.StoreNumber)) {
            failure.storeId = configuration.StoreNumber;
        }

        if (configuration && !StringExtensions.isNullOrWhitespace(configuration.TerminalId)) {
            failure.registerId = configuration.TerminalId;
        }
    } catch (error) {
        context.logger.logInformational(`Customer order lookup: the store and register could not be read. ${describeError(error)}`);
    }

    try {
        const version: ClientEntities.ICancelableDataResult<GetApplicationVersionClientResponse> =
            await context.runtime.executeAsync(
                new GetApplicationVersionClientRequest<GetApplicationVersionClientResponse>(correlationId));
        const appVersion: string | undefined = version.canceled ? undefined : version.data?.result;
        if (typeof appVersion === "string" && !StringExtensions.isNullOrWhitespace(appVersion)) {
            failure.posVersion = appVersion;
        }
    } catch (error) {
        context.logger.logInformational(`Customer order lookup: the POS version could not be read. ${describeError(error)}`);
    }

    const connectivity: SideChat.AgentPosConnectivity | undefined = await readConnectivityAsync(correlationId, context);
    if (connectivity) {
        failure.connectivity = connectivity;
    }

    return failure;
}

/**
 * Reads whether POS can reach Commerce.
 * @returns "Online" or "Offline", or undefined when POS does not say.
 */
async function readConnectivityAsync(
    correlationId: string,
    context: IExtensionContext
): Promise<SideChat.AgentPosConnectivity | undefined> {
    try {
        const status: ClientEntities.ICancelableDataResult<GetConnectionStatusClientResponse> =
            await context.runtime.executeAsync(
                new GetConnectionStatusClientRequest<GetConnectionStatusClientResponse>(correlationId));
        const value: unknown = status.canceled ? undefined : status.data?.result;
        if (typeof value !== "number") {
            return undefined;
        }

        return value === CONNECTION_STATUS_ONLINE ? "Online" : "Offline";
    } catch (error) {
        context.logger.logInformational(`Customer order lookup: the connection status could not be read. ${describeError(error)}`);
        return undefined;
    }
}

/**
 * Formats a time as ISO 8601 with the register's UTC offset, for example "2026-10-01T09:42:05-05:00",
 * which is how the IT support guide asks for it.
 * @param date The time.
 * @returns The formatted time.
 */
export function formatLocalTimestamp(date: Date): string {
    const offsetMinutes: number = -date.getTimezoneOffset();
    const absoluteOffset: number = Math.abs(offsetMinutes);
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
        + `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
        + `${offsetMinutes >= 0 ? "+" : "-"}${pad(Math.floor(absoluteOffset / 60))}:${pad(absoluteOffset % 60)}`;
}

function pad(value: number): string {
    return value < 10 ? `0${value}` : String(value);
}

function delayAsync(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
        window.setTimeout(resolve, milliseconds);
    });
}

function isNotFoundError(error: unknown): boolean {
    return /not\s?found|does\s+not\s+exist/i.test(describeError(error));
}

function describeError(error: unknown): string {
    if (error instanceof Error) {
        return error.message;
    }

    try {
        return JSON.stringify(error) || String(error);
    } catch {
        return String(error);
    }
}
