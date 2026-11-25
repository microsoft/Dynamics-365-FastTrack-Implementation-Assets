/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * CustomerOrderLookupView — looks up a customer order by its number.
 *
 * It shows how the side panel helps with an error on the associate's screen. When a lookup fails, POS
 * tells the panel what failed, with the diagnostic details the IT support guide asks for, and the panel
 * offers to get help with it; Ask Copilot here does the same. The agent answers from the guide.
 *
 * Lookups fail by default, so the page always has an error to get help with. The page does not say so;
 * SIMULATE_OUTAGE_BY_DEFAULT in Extend/Agent/CustomerOrderLookup turns it off to look up real orders.
 *
 * The lookup itself lives in Extend/Agent/CustomerOrderLookup, because the agent can retry it from the
 * panel. This view only mirrors it.
 */

import * as Views from "PosApi/Create/Views";
import * as SideChat from "ContosoSideChat";
import { CurrencyFormatter, DateFormatter } from "PosApi/Consume/Formatters";
import { ObjectExtensions, StringExtensions } from "PosApi/TypeExtensions";
import ko from "knockout";
import {
    CUSTOMER_ORDER_LOOKUP_OPERATION,
    getCustomerOrderLookupState,
    ICustomerOrderLookupState,
    ICustomerOrderSummary,
    lookUpCustomerOrderAsync,
    MAX_LOOKUP_RETRIES,
    subscribeToCustomerOrderLookup
} from "../../../Extend/Agent/CustomerOrderLookup";
import { showSideChatPanel } from "../../../Extend/Triggers/SideChatPanelHost";

/** A labelled value in the error details or the order summary. */
export interface ICustomerOrderLookupDetail {
    label: string;
    value: string;
}

/**
 * The controller for CustomerOrderLookupView.
 */
export default class CustomerOrderLookupView extends Views.CustomViewControllerBase {
    /** The order number in the box. */
    public readonly orderNumber: ko.Observable<string>;

    /** Whether a lookup is running, from this view or from the agent. */
    public readonly isSearching: ko.Observable<boolean>;

    /** Read out while a lookup runs. */
    public readonly statusText: ko.Observable<string>;

    /** Why a lookup could not start, shown under the box. */
    public readonly inputMessage: ko.Observable<string>;

    /** The failed lookup, when the last lookup failed. */
    public readonly hasFailed: ko.Observable<boolean>;
    public readonly failureTitle: ko.Observable<string>;
    public readonly failureMessage: ko.Observable<string>;
    public readonly failureDetails: ko.ObservableArray<ICustomerOrderLookupDetail>;

    /** Whether the failed lookup can still be retried, and what to say once it cannot. */
    public readonly canRetry: ko.Observable<boolean>;
    public readonly retriedText: ko.Observable<string>;

    /** The order, when the last lookup found it. */
    public readonly hasOrder: ko.Observable<boolean>;
    public readonly orderTitle: ko.Observable<string>;
    public readonly orderDetails: ko.ObservableArray<ICustomerOrderLookupDetail>;

    /** Shown when Commerce has no such order. */
    public readonly notFoundText: ko.Observable<string>;

    private _unsubscribeFromLookup: (() => void) | null;

    /**
     * Creates a new instance of the CustomerOrderLookupView class.
     * @param {Views.ICustomViewControllerContext} context The custom view controller context.
     */
    constructor(context: Views.ICustomViewControllerContext) {
        super(context);
        this.state.title = CUSTOMER_ORDER_LOOKUP_OPERATION;

        const initial: ICustomerOrderLookupState = getCustomerOrderLookupState();
        this.orderNumber = ko.observable(initial.orderNumber);
        this.isSearching = ko.observable(false);
        this.statusText = ko.observable(StringExtensions.EMPTY);
        this.inputMessage = ko.observable(StringExtensions.EMPTY);
        this.hasFailed = ko.observable(false);
        this.failureTitle = ko.observable(StringExtensions.EMPTY);
        this.failureMessage = ko.observable(StringExtensions.EMPTY);
        this.failureDetails = ko.observableArray([]);
        this.canRetry = ko.observable(false);
        this.retriedText = ko.observable(StringExtensions.EMPTY);
        this.hasOrder = ko.observable(false);
        this.orderTitle = ko.observable(StringExtensions.EMPTY);
        this.orderDetails = ko.observableArray([]);
        this.notFoundText = ko.observable(StringExtensions.EMPTY);

        // The agent can retry the lookup from the panel, so the view follows the lookup, not its own buttons.
        this._unsubscribeFromLookup = subscribeToCustomerOrderLookup((state: ICustomerOrderLookupState): void => {
            this._showState(state);
        });
        this._showState(initial);
    }

    /**
     * Binds the html element with the view controller.
     * @param {HTMLElement} element DOM element.
     */
    public onReady(element: HTMLElement): void {
        ko.applyBindings(this, element);
    }

    /**
     * Looks up the order number in the box.
     */
    public lookUp(): void {
        if (this.isSearching()) {
            return;
        }

        const orderNumber: string = (this.orderNumber() || StringExtensions.EMPTY).trim();
        if (orderNumber.length === 0) {
            this.inputMessage("Enter an order number to look up.");
            return;
        }

        this.inputMessage(StringExtensions.EMPTY);
        this._run(lookUpCustomerOrderAsync(orderNumber, this.context, 0));
    }

    /**
     * Retries the failed lookup, once, as the IT support guide allows.
     */
    public retry(): void {
        const state: ICustomerOrderLookupState = getCustomerOrderLookupState();
        if (this.isSearching() || state.status !== "failed" || state.retryCount >= MAX_LOOKUP_RETRIES) {
            return;
        }

        this._run(lookUpCustomerOrderAsync(state.orderNumber, this.context, state.retryCount + 1));
    }

    /**
     * Opens the side panel and asks the agent for help with the failed lookup.
     */
    public askCopilot(): void {
        // The panel offers help for ten minutes, or until the associate dismisses it. Asking from here
        // brings the failure back in either case.
        const failure: SideChat.IAgentPosErrorContext | undefined = getCustomerOrderLookupState().error;
        if (failure) {
            const reported: SideChat.IAgentPosErrorContext | null = SideChat.getPosError();
            if (!reported || reported.correlationId !== failure.correlationId) {
                SideChat.reportPosError(failure);
            }
        }

        showSideChatPanel(this.context);
        if (!SideChat.requestPosErrorHelp()) {
            SideChat.setOpen(true);
        }
    }

    /**
     * Called when the object is disposed.
     */
    public dispose(): void {
        if (this._unsubscribeFromLookup) {
            this._unsubscribeFromLookup();
            this._unsubscribeFromLookup = null;
        }

        ObjectExtensions.disposeAllProperties(this);
    }

    /**
     * Runs a lookup. Its outcome arrives through the subscription; only an error that stopped it from
     * starting is shown from here.
     */
    private _run(lookup: Promise<unknown>): void {
        lookup.catch((error: unknown): void => {
            this.inputMessage(error instanceof Error ? error.message : "The lookup could not be started.");
        });
    }

    private _showState(state: ICustomerOrderLookupState): void {
        const isSearching: boolean = state.status === "searching";
        this.isSearching(isSearching);
        this.statusText(isSearching ? `Looking up order ${state.orderNumber}…` : StringExtensions.EMPTY);
        if (isSearching && StringExtensions.isNullOrWhitespace(this.orderNumber())) {
            this.orderNumber(state.orderNumber);
        }

        const failure: SideChat.IAgentPosErrorContext | undefined = state.status === "failed" ? state.error : undefined;
        this.hasFailed(!!failure);
        this.failureTitle(failure ? `${failure.operation || CUSTOMER_ORDER_LOOKUP_OPERATION} failed` : StringExtensions.EMPTY);
        this.failureMessage(failure && failure.message ? failure.message : StringExtensions.EMPTY);
        this.failureDetails(failure ? describeFailure(failure) : []);
        this.canRetry(!!failure && state.retryCount < MAX_LOOKUP_RETRIES);
        this.retriedText(failure && state.retryCount >= MAX_LOOKUP_RETRIES
            ? "The lookup was retried once and failed again."
            : StringExtensions.EMPTY);

        const order: ICustomerOrderSummary | undefined = state.status === "found" ? state.order : undefined;
        this.hasOrder(!!order);
        this.orderTitle(order ? `Order ${order.orderNumber}` : StringExtensions.EMPTY);
        this.orderDetails(order ? describeOrder(order) : []);

        this.notFoundText(state.status === "notFound"
            ? `There is no customer order ${state.orderNumber}.`
            : StringExtensions.EMPTY);
    }
}

/**
 * Lists the details POS reported about a failed lookup, as a POS error dialog would. The message is shown above them.
 * @param failure The failure.
 * @returns The details that are known.
 */
function describeFailure(failure: SideChat.IAgentPosErrorContext): ICustomerOrderLookupDetail[] {
    const details: ICustomerOrderLookupDetail[] = [];
    const add = (label: string, value: string | undefined): void => {
        if (!StringExtensions.isNullOrWhitespace(value)) {
            details.push({ label: label, value: value });
        }
    };

    add("Error code", failure.code);
    add("Order number", failure.orderNumber);
    add("Reference", failure.correlationId);
    add("Time", formatOccurredAt(failure.occurredAt));
    add("Store", failure.storeId);
    add("Register", failure.registerId);
    add("POS version", failure.posVersion);
    add("Connectivity", failure.connectivity);
    add("Retries", String(failure.retryCount || 0));
    return details;
}

/**
 * Shows when a failure happened in the store's short date and time format.
 * @param occurredAt The local timestamp POS recorded, such as 2026-10-01T14:03:22-05:00.
 * @returns The formatted time, or the timestamp as recorded when it cannot be read.
 */
function formatOccurredAt(occurredAt: string | undefined): string | undefined {
    if (StringExtensions.isNullOrWhitespace(occurredAt)) {
        return occurredAt;
    }

    const occurred: Date = new Date(occurredAt);
    return isNaN(occurred.getTime()) ? occurredAt : DateFormatter.toShortDateAndTime(occurred);
}

/**
 * Lists what the lookup found about an order.
 * @param order The order.
 * @returns The details that are known.
 */
function describeOrder(order: ICustomerOrderSummary): ICustomerOrderLookupDetail[] {
    const details: ICustomerOrderLookupDetail[] = [];
    if (order.customerName || order.customerAccount) {
        details.push({
            label: "Customer",
            value: order.customerName && order.customerAccount
                ? `${order.customerName} (${order.customerAccount})`
                : (order.customerName || order.customerAccount)
        });
    }

    if (typeof order.total === "number") {
        details.push({ label: "Total", value: CurrencyFormatter.toCurrency(order.total) });
    }

    if (order.createdOn) {
        details.push({ label: "Created", value: DateFormatter.toShortDateAndTime(order.createdOn) });
    }

    details.push({ label: "Lines", value: String(order.lineCount) });
    return details;
}
