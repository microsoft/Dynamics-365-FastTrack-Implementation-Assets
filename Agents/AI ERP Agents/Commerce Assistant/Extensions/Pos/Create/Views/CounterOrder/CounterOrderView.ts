/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * CounterOrderView — builds a counter order from the customer's list of items.
 *
 * Bulk add items opens a dialog that takes a pasted list the way the POS bulk item entry dialog does: one item ID
 * and quantity per line, with the same parsing, limits and messages. The dialog finds the products first and lists
 * them, so the associate can check them before adding them to the cart. Lines that can't be read, found or added
 * stay in the list with their errors, and a toast says how it went once the dialog closes.
 *
 * Add from photo takes a photo of the customer's list, chosen, dropped on the dialog or pasted. Copilot resolves
 * the item IDs and adds the requested quantities through Commerce tools (see ItemListPhoto). POS reloads the
 * server cart and verifies the changes; photo additions never also run the pasted-list add operation.
 *
 * The grid shows the cart. POS doesn't tell a custom view when the cart changes, so the view reads the cart when
 * it opens or is shown again, and CartUpdatesPostProductSaleTrigger passes it on whenever products are added,
 * including from the side panel.
 */

import * as Views from "PosApi/Create/Views";
import * as SideChat from "ContosoSideChat";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { GetCurrentCartClientRequest, GetCurrentCartClientResponse } from "PosApi/Consume/Cart";
import {
    GetChannelConfigurationClientRequest,
    GetChannelConfigurationClientResponse,
    TriggerToastNotificationClientRequest,
    TriggerToastNotificationClientResponse
} from "PosApi/Consume/Device";
import { CurrencyFormatter } from "PosApi/Consume/Formatters";
import { ObjectExtensions, StringExtensions } from "PosApi/TypeExtensions";
import ko from "knockout";
import { publishCartUpdate, subscribeToCartUpdates } from "../../../Extend/Triggers/CartUpdates";
import { showSideChatPanel } from "../../../Extend/Triggers/SideChatPanelHost";
import {
    addIdentifiedLinesAsync,
    buildRemainingText,
    countValidLines,
    describeAddToast,
    describeError,
    findItemsAsync,
    formatAddedCount,
    formatLineCount,
    IAddItemsResult,
    IBulkAddToast,
    IBulkLineError,
    IFindItemsResult,
    IIdentifiedLine,
    MAX_BULK_ITEM_TEXT_LENGTH,
    requiresVariantSelection
} from "./BulkItemEntry";
import { addPhotoItemsToCartAsync, IItemListPhoto, IPhotoCartResult, preparePhotoAsync } from "./ItemListPhoto";

/**
 * Where the Bulk add items dialog is: choosing how to add items, adding a photo's items, entering the list,
 * or checking what was found.
 */
export type BulkAddStep = "choose" | "photo" | "paste" | "review";

/** Whether what the dialog says about a photo is an error, or only says that no list was read. */
export type PhotoMessageKind = "error" | "info";

/** Whether the grid has the cart yet. */
export type CounterOrderCartStatus = "loading" | "ready" | "failed";

/**
 * A cart line as the grid shows it.
 */
export interface ICounterOrderLine {
    readonly key: string;
    readonly name: string;
    readonly itemId: string;
    readonly quantity: string;
    readonly unit: string;
    /** The price of one unit after discounts. */
    readonly netPrice: string;
    readonly fulfillment: string;
}

/**
 * A product the dialog found, as it's listed for the associate to check.
 */
export interface ICounterOrderFoundItem {
    readonly key: string;
    readonly name: string;
    /** The item ID, then the variant's options, such as its size and colour. */
    readonly detail: string;
    readonly quantity: string;
    /** True when the associate chooses the product's options as it's added. */
    readonly needsOptions: boolean;
    /** The line as the photo has it, when it doesn't show the item ID; otherwise empty. */
    readonly readAs: string;
}

/**
 * A line the dialog couldn't find or add, as it's shown.
 */
export interface ICounterOrderError {
    readonly key: string;
    readonly message: string;
}

/** The delivery mode codes the store uses, so each line's fulfillment is named as POS names it. */
interface IDeliveryModeCodes {
    readonly pickup: string;
    readonly carryout: string;
    readonly email: string;
}

const VIEW_TITLE: string = "Counter order";
const FINDING_TEXT: string = "Finding items...";
const ADDING_TEXT: string = "Adding lines...";
const PREPARING_PHOTO_TEXT: string = "Preparing the photo...";
const READING_PHOTO_TEXT: string = "Reading and adding the photo's items...";
const FIND_FAILED: string = "The items couldn't be looked up. Try again.";
const ADD_FAILED: string = "The items couldn't be added. Check the cart before you try again.";
const PHOTO_FAILED: string = "The photo couldn't be prepared. Try another photo.";
const READ_FAILED: string = "Copilot couldn't finish the photo request.";
const COPILOT_UNREACHABLE: string = "Copilot couldn't be reached. Check the connection and try again.";

/** What gets focus when the dialog shows each step. */
const STEP_FOCUS_SELECTORS: { [step: string]: string } = {
    choose: ".counterOrderPhotoTile",
    photo: ".counterOrderPhotoStatus",
    paste: ".counterOrderBulkText",
    review: ".counterOrderReviewTitle"
};

const FOCUSABLE_SELECTOR: string = "button, input, select, textarea, a[href], [tabindex]";

/**
 * The controller for CounterOrderView.
 */
export default class CounterOrderView extends Views.CustomViewControllerBase {
    /** The box above the grid, for an item ID and quantity or a pasted list. */
    public readonly entryText: ko.Observable<string>;

    /** The most characters a list can have, as in POS. */
    public readonly maxTextLength: number;

    /** Whether the grid has the cart yet. */
    public readonly cartStatus: ko.Observable<CounterOrderCartStatus>;

    /** The cart lines, without the voided ones. */
    public readonly cartLines: ko.ObservableArray<ICounterOrderLine>;

    /** The totals, as the POS cart shows them. */
    public readonly lineCountText: ko.Observable<string>;
    public readonly subtotalText: ko.Observable<string>;
    public readonly savingsText: ko.Observable<string>;
    public readonly totalText: ko.Observable<string>;

    /** Whether the Bulk add items dialog is open, and its step. */
    public readonly isDialogOpen: ko.Observable<boolean>;
    public readonly step: ko.Observable<BulkAddStep>;

    /** The list in the dialog, and how many lines it will add, counted as it's typed. */
    public readonly bulkText: ko.Observable<string>;
    public readonly lineCountToAdd: ko.Computed<number>;
    public readonly lineCountToAddText: ko.Computed<string>;

    /** Whether the dialog is finding the products or adding them, and what it says meanwhile. */
    public readonly isFinding: ko.Observable<boolean>;
    public readonly isAdding: ko.Observable<boolean>;
    public readonly isBusy: ko.Computed<boolean>;
    public readonly busyText: ko.Computed<string>;

    /** Why lines couldn't be found or added. Three or more are grouped under a header that can hide them. */
    public readonly errors: ko.ObservableArray<ICounterOrderError>;
    public readonly errorsExpanded: ko.Observable<boolean>;
    public readonly errorCountText: ko.Computed<string>;

    /** The lines added since the dialog opened. */
    public readonly addedCount: ko.Observable<number>;
    public readonly addedText: ko.Computed<string>;

    /** The products found in the list, for the associate to check before adding them. */
    public readonly foundItems: ko.ObservableArray<ICounterOrderFoundItem>;
    public readonly reviewTitle: ko.Observable<string>;

    /** The photo being read: its name, a small copy of it, and what the dialog is doing with it. */
    public readonly photoName: ko.Observable<string>;
    public readonly photoPreview: ko.Observable<string>;
    public readonly photoStatus: ko.Observable<string>;

    /** Said with the ways to add items when no list could be read from a photo, and whether it's an error. */
    public readonly photoMessage: ko.Observable<string>;
    public readonly photoMessageKind: ko.Observable<PhotoMessageKind>;

    /** Read out by screen readers as the dialog works. */
    public readonly statusText: ko.Observable<string>;

    private _element: HTMLElement | null = null;
    private _opener: HTMLElement | null = null;
    private _dialogRun: number = 0;
    private _photoRun: number = 0;
    private _dialogCorrelationId: string = StringExtensions.EMPTY;
    private _lastFind: IFindItemsResult | null = null;
    private _findText: string = StringExtensions.EMPTY;
    private _lastAddErrors: IBulkLineError[] = [];
    private _hasAddRun: boolean = false;
    private _cartSequence: number = 0;
    private _hasCart: boolean = false;
    private _deliveryModeCodes: IDeliveryModeCodes | null = null;
    private _wasHidden: boolean = false;
    private _isDisposed: boolean = false;
    private _unsubscribeFromCart: (() => void) | null = null;

    /**
     * Creates a new instance of the CounterOrderView class.
     * @param {Views.ICustomViewControllerContext} context The custom view controller context.
     */
    constructor(context: Views.ICustomViewControllerContext) {
        super(context);
        this.state.title = VIEW_TITLE;

        this.entryText = ko.observable(StringExtensions.EMPTY);
        this.maxTextLength = MAX_BULK_ITEM_TEXT_LENGTH;
        this.cartStatus = ko.observable("loading");
        this.cartLines = ko.observableArray([]);
        this.lineCountText = ko.observable(formatLines(0));
        this.subtotalText = ko.observable(formatAmount(0));
        this.savingsText = ko.observable(formatAmount(0));
        this.totalText = ko.observable(formatAmount(0));

        this.isDialogOpen = ko.observable(false);
        this.step = ko.observable("choose");
        this.bulkText = ko.observable(StringExtensions.EMPTY);
        this.lineCountToAdd = ko.pureComputed((): number => countValidLines(this.bulkText() || StringExtensions.EMPTY));
        this.lineCountToAddText = ko.pureComputed((): string => formatLineCount(this.lineCountToAdd()));
        this.isFinding = ko.observable(false);
        this.isAdding = ko.observable(false);
        this.isBusy = ko.pureComputed((): boolean => this.isFinding() || this.isAdding());
        this.busyText = ko.pureComputed((): string => this.isAdding() ? ADDING_TEXT : FINDING_TEXT);
        this.errors = ko.observableArray([]);
        this.errorsExpanded = ko.observable(true);
        this.errorCountText = ko.pureComputed((): string => formatErrorCount(this.errors().length));
        this.addedCount = ko.observable(0);
        this.addedText = ko.pureComputed((): string => formatAddedCount(this.addedCount()));
        this.foundItems = ko.observableArray([]);
        this.reviewTitle = ko.observable(StringExtensions.EMPTY);
        this.photoName = ko.observable(StringExtensions.EMPTY);
        this.photoPreview = ko.observable(StringExtensions.EMPTY);
        this.photoStatus = ko.observable(StringExtensions.EMPTY);
        this.photoMessage = ko.observable(StringExtensions.EMPTY);
        this.photoMessageKind = ko.observable("error");
        this.statusText = ko.observable(StringExtensions.EMPTY);

        this._unsubscribeFromCart = subscribeToCartUpdates(this._onCartUpdated);
    }

    /**
     * Binds the html element with the view controller.
     * @param {HTMLElement} element DOM element.
     */
    public onReady(element: HTMLElement): void {
        this._element = element;
        ko.applyBindings(this, element);
        this._refreshCart();
    }

    /**
     * Called when the view is shown again. The cart may have changed while it was hidden.
     */
    public onShown(): void {
        if (this._wasHidden) {
            this._wasHidden = false;
            this._refreshCart();
        }
    }

    /**
     * Called when the view is hidden.
     */
    public onHidden(): void {
        this._wasHidden = true;
    }

    /**
     * Called when the object is disposed.
     */
    public dispose(): void {
        this._isDisposed = true;
        if (this._unsubscribeFromCart) {
            this._unsubscribeFromCart();
            this._unsubscribeFromCart = null;
        }

        ObjectExtensions.disposeAllProperties(this);

        // disposeAllProperties deletes the flag with everything else; the lookups and adds still running check it.
        this._isDisposed = true;
    }

    /**
     * Opens the dialog with what was typed in the box, and finds the products when it has an item ID and quantity.
     */
    public readonly submitEntry = (): void => {
        const text: string = (this.entryText() || StringExtensions.EMPTY).trim();
        if (text.length === 0 || this.isDialogOpen()) {
            return;
        }

        this.entryText(StringExtensions.EMPTY);
        this._openWithList(text);
    };

    /**
     * Takes a pasted list. A box holds one line, so a list with several lines goes to the dialog instead.
     * @param {unknown} data The view model.
     * @param {Event} event The paste event.
     * @returns {boolean} True to let the box take what was pasted.
     */
    public readonly onEntryPaste = (data: unknown, event: Event): boolean => {
        const pasted: string = readClipboardText(event);
        if (!/[\r\n]/.test(pasted) || this.isDialogOpen()) {
            return true;
        }

        const typed: string = (this.entryText() || StringExtensions.EMPTY).trim();
        this.entryText(StringExtensions.EMPTY);
        this._openWithList(typed.length > 0 ? `${typed}\n${pasted}` : pasted);
        return false;
    };

    /**
     * Opens the Bulk add items dialog.
     */
    public readonly openBulkAdd = (): void => {
        if (!this.isDialogOpen()) {
            this._openDialog("choose");
        }
    };

    /**
     * Opens the side panel.
     */
    public readonly askCopilot = (): void => {
        showSideChatPanel(this.context);
        SideChat.setOpen(true);
    };

    /**
     * Goes to the cart to take payment.
     */
    public readonly takePayment = (): void => {
        if (this.cartLines().length === 0) {
            return;
        }

        const correlationId: string = this.context.logger.getNewCorrelationId();
        this.context.navigator.navigateToPOSView("CartView", new ClientEntities.CartViewNavigationParameters(correlationId));
    };

    /**
     * Reads the cart again after it couldn't be read.
     */
    public readonly retryCart = (): void => {
        this._refreshCart();
    };

    /**
     * Shows the box for the list.
     */
    public readonly choosePaste = (): void => {
        if (!this.isBusy()) {
            this.photoMessage(StringExtensions.EMPTY);
            this._goTo("paste");
        }
    };

    /**
     * Opens the device's file picker for a photo of the customer's list.
     */
    public readonly choosePhoto = (): void => {
        const input: HTMLElement | null = this._canTakePhoto() ? this._find(".counterOrderPhotoInput") : null;
        if (input) {
            input.click();
        }
    };

    /**
     * Reads the photo chosen in the file picker.
     * @param {unknown} data The view model.
     * @param {Event} event The input's change event.
     * @returns {boolean} True, to let the input do what it normally does.
     */
    public readonly onPhotoChosen = (data: unknown, event: Event): boolean => {
        const browserEvent: Event | undefined = browserEventOf(event);
        const target: EventTarget | null = browserEvent ? browserEvent.target : null;
        const input: HTMLInputElement | null = (target || this._find(".counterOrderPhotoInput")) as HTMLInputElement;
        const file: File | undefined = input && input.files && input.files.length > 0 ? input.files[0] : undefined;
        if (input) {
            // Emptied, so that choosing the same photo again still reads it.
            input.value = StringExtensions.EMPTY;
        }

        if (file) {
            this._readPhoto(file);
        }

        return true;
    };

    /**
     * Cancels photo preparation, before a request that can add items has started.
     */
    public readonly cancelPhoto = (): void => {
        if (this.step() === "photo" && !this.isBusy()) {
            this._photoRun++;
            this._clearPhoto();
            this._goTo("choose");
        }
    };

    /**
     * Lets a photo be dropped on the dialog while it shows the ways to add items. Other files are refused
     * everywhere in it, so that the browser doesn't open a dropped file in place of POS.
     * @param {unknown} data The view model.
     * @param {Event} event The dragover event.
     * @returns {boolean} True to let text and links be dragged as usual.
     */
    public readonly onDialogDragOver = (data: unknown, event: Event): boolean => {
        const dataTransfer: DataTransfer | null = readDataTransfer(event);
        if (!isDraggingFiles(dataTransfer)) {
            return true;
        }

        dataTransfer.dropEffect = this._canTakePhoto() ? "copy" : "none";
        return false;
    };

    /**
     * Reads a photo dropped on the dialog while it shows the ways to add items.
     * @param {unknown} data The view model.
     * @param {Event} event The drop event.
     * @returns {boolean} True to let text and links be dropped as usual.
     */
    public readonly onDialogDrop = (data: unknown, event: Event): boolean => {
        const dataTransfer: DataTransfer | null = readDataTransfer(event);
        if (!isDraggingFiles(dataTransfer)) {
            return true;
        }

        const files: FileList | null = dataTransfer.files;
        if (files && files.length > 0 && this._canTakePhoto()) {
            this._readPhoto(files[0]);
        }

        return false;
    };

    /**
     * Reads a pasted photo, such as a screenshot of the customer's email, while the dialog shows the ways to add items.
     * @param {unknown} data The view model.
     * @param {Event} event The paste event.
     * @returns {boolean} True to let anything else be pasted as usual.
     */
    public readonly onDialogPaste = (data: unknown, event: Event): boolean => {
        const file: File | undefined = this._canTakePhoto() ? readPastedFile(readClipboardData(event)) : undefined;
        if (!file) {
            return true;
        }

        this._readPhoto(file);
        return false;
    };

    /**
     * Goes back to choosing how to add items. The list is kept.
     */
    public readonly backToChoose = (): void => {
        if (!this.isBusy()) {
            this._goTo("choose", ".counterOrderPasteTile");
        }
    };

    /**
     * Finds the product for each line of the list.
     */
    public readonly findItems = (): void => {
        if (!this.isDialogOpen() || this.isBusy() || this.step() !== "paste") {
            return;
        }

        const text: string = this.bulkText() || StringExtensions.EMPTY;
        if (countValidLines(text) === 0) {
            return;
        }

        // As in POS, the errors stay while the list is edited and clear when it's tried again.
        const run: number = this._dialogRun;
        this._setErrors([]);
        this.isFinding(true);
        this._announce(FINDING_TEXT);
        this._focusDialog();
        this._findAsync(text, run).catch((error: unknown): void => {
            this._logUnexpected("showing the items found", error);
        });
    };

    /**
     * Goes back to the list as it was entered, with the lines that weren't found still marked.
     */
    public readonly editList = (): void => {
        if (this.isBusy() || this.step() !== "review") {
            return;
        }

        this._lastFind = null;
        this.foundItems([]);
        this.bulkText(this._findText);
        this._goTo("paste");
    };

    /**
     * Adds the products found to the cart, as POS does.
     */
    public readonly addToCart = (): void => {
        const found: IFindItemsResult | null = this._lastFind;
        if (!this.isDialogOpen() || this.isBusy() || this.step() !== "review" || !found) {
            return;
        }

        const run: number = this._dialogRun;
        this.isAdding(true);
        this._announce(ADDING_TEXT);
        this._focusDialog();
        this._addAsync(found, run, this._dialogCorrelationId).catch((error: unknown): void => {
            this._logUnexpected("showing the lines added", error);
        });
    };

    /**
     * Closes the dialog, unless it's finding or adding items.
     */
    public readonly closeDialog = (): void => {
        if (this.isDialogOpen() && !this.isBusy()) {
            this._closeDialog();
        }
    };

    /**
     * Shows or hides the errors when there are three or more.
     */
    public readonly toggleErrors = (): void => {
        this.errorsExpanded(!this.errorsExpanded());
    };

    /**
     * Closes the dialog on Escape and keeps Tab inside it.
     * @param {unknown} data The view model.
     * @param {KeyboardEvent} event The key press.
     * @returns {boolean} True to let the key do what it normally does.
     */
    public readonly onDialogKeyDown = (data: unknown, event: KeyboardEvent): boolean => {
        if (event.key === "Escape" || event.key === "Esc") {
            event.stopPropagation();
            this.closeDialog();
            return false;
        }

        return event.key === "Tab" ? this._keepFocusInDialog(event) : true;
    };

    private readonly _onCartUpdated = (cart: ProxyEntities.Cart): void => {
        if (this._isDisposed) {
            return;
        }

        // Each line's fulfillment is named from the store's delivery modes, so they're read with the cart first.
        if (!this._deliveryModeCodes) {
            this._refreshCart();
            return;
        }

        this._cartSequence++;
        this._showCart(cart);
    };

    private _openWithList(text: string): void {
        this._openDialog("paste");
        this.bulkText(text);
        if (countValidLines(text) > 0) {
            this.findItems();
        }
    }

    private _openDialog(step: BulkAddStep): void {
        const active: Element | null = document.activeElement;
        this._opener = active && active !== document.body && typeof (active as HTMLElement).focus === "function"
            ? active as HTMLElement
            : null;
        this._dialogRun++;
        this._dialogCorrelationId = this.context.logger.getNewCorrelationId();
        this._resetDialog();
        this.step(step);
        this.isDialogOpen(true);
        this._focusStep();
    }

    private _closeDialog(photoToast?: IBulkAddToast): void {
        // As in POS, the toast says how the adds went once the dialog closes; finding alone adds nothing to report.
        const toast: IBulkAddToast | undefined = photoToast
            || (this._hasAddRun ? describeAddToast(this.addedCount(), this._lastAddErrors) : undefined);
        const correlationId: string = this._dialogCorrelationId;
        this._dialogRun++;
        this.isDialogOpen(false);
        this._resetDialog();
        this._restoreFocus();
        if (toast) {
            setTimeout((): void => {
                this._showToast(toast, correlationId);
            }, 0);
        }
    }

    private _resetDialog(): void {
        this._lastFind = null;
        this._findText = StringExtensions.EMPTY;
        this._lastAddErrors = [];
        this._hasAddRun = false;
        this.isFinding(false);
        this.isAdding(false);
        this.step("choose");
        this.bulkText(StringExtensions.EMPTY);
        this.errors([]);
        this.errorsExpanded(true);
        this.addedCount(0);
        this.foundItems([]);
        this.reviewTitle(StringExtensions.EMPTY);
        this._photoRun++;
        this._clearPhoto();
        this.photoMessage(StringExtensions.EMPTY);
        this.photoMessageKind("error");
        this.statusText(StringExtensions.EMPTY);
    }

    private _goTo(step: BulkAddStep, focusSelector?: string): void {
        this.step(step);
        this._focusStep(focusSelector);
    }

    private _canTakePhoto(): boolean {
        return !this._isDisposed && this.isDialogOpen() && !this.isBusy() && this.step() === "choose";
    }

    private _readPhoto(file: File): void {
        if (!this._canTakePhoto()) {
            return;
        }

        const run: number = ++this._photoRun;
        this.photoMessage(StringExtensions.EMPTY);
        this._setErrors([]);
        this._clearPhoto();
        this.photoStatus(PREPARING_PHOTO_TEXT);
        this._announce(PREPARING_PHOTO_TEXT);
        this._goTo("photo");
        this._readPhotoAsync(file, run).catch((error: unknown): void => {
            this._logUnexpected("reading the photo", error);
        });
    }

    /**
     * Prepares a photo, then asks Copilot to add its items and reloads the actual cart. Once the request
     * starts it cannot be canceled: ignoring its reply would not undo its additions.
     */
    private async _readPhotoAsync(file: File, run: number): Promise<void> {
        let photo: IItemListPhoto;
        try {
            photo = await preparePhotoAsync(file);
        } catch (error) {
            // Not logged: the message names the file, and a name can say who the customer is.
            if (this._isCurrentPhotoRun(run)) {
                this._showPhotoMessage(describeError(error) || PHOTO_FAILED, "error");
            }

            return;
        }

        if (!this._isCurrentPhotoRun(run)) {
            return;
        }

        this.photoName(photo.name);
        this.photoPreview(photo.previewUrl);
        this.photoStatus(READING_PHOTO_TEXT);
        this._announce(READING_PHOTO_TEXT);
        this.isAdding(true);

        let result: IPhotoCartResult;
        try {
            result = await addPhotoItemsToCartAsync(this.context, photo, this._dialogCorrelationId);
        } catch (error) {
            if (this._isCurrentPhotoRun(run)) {
                this.isAdding(false);
                this._showPhotoMessage(describeReadFailure(error), "error");
            }

            return;
        }

        publishCartUpdate(result.cart);
        if (!this._isCurrentPhotoRun(run)) {
            return;
        }

        this.isAdding(false);
        if (result.needsAttention) {
            this._showPhotoMessage(`${result.summary} ${result.message}`, "error");
        } else {
            this._closeDialog({ title: result.summary, body: result.message, kind: "info" });
        }
    }

    /** Goes back to the ways to add items, saying why no list was read from the photo. */
    private _showPhotoMessage(message: string, kind: PhotoMessageKind): void {
        this._clearPhoto();
        this.photoMessage(message);
        this.photoMessageKind(kind);
        this._announce(message);
        this._goTo("choose");
    }

    private _clearPhoto(): void {
        this.photoName(StringExtensions.EMPTY);
        this.photoPreview(StringExtensions.EMPTY);
        this.photoStatus(StringExtensions.EMPTY);
    }

    private _isCurrentPhotoRun(run: number): boolean {
        return !this._isDisposed && run === this._photoRun;
    }

    private async _findAsync(text: string, run: number): Promise<void> {
        let result: IFindItemsResult;
        try {
            result = await findItemsAsync(this.context, text, this._dialogCorrelationId);
        } catch (error) {
            if (this._isCurrentRun(run)) {
                this.context.logger.logWarning(`Counter order: finding the items failed. ${describeError(error)}`, this._dialogCorrelationId);
                this.isFinding(false);
                this._showFailure(FIND_FAILED);
            }

            return;
        }

        if (this._isCurrentRun(run)) {
            this.isFinding(false);
            this._showFound(text, result);
        }
    }

    private _showFound(text: string, result: IFindItemsResult): void {
        // The list is kept so the associate can shorten it.
        if (result.tooManyLines) {
            this.bulkText(text);
            this._setErrors(result.errors);
            this._announce(result.errors.length > 0 ? result.errors[0].message : StringExtensions.EMPTY);
            this._goTo("paste");
            return;
        }

        // As in POS, the list keeps only the lines that need attention.
        if (result.identified.length === 0) {
            this.bulkText(buildRemainingText(result.errors));
            this._setErrors(result.errors);
            this._announce(`No items found. ${formatErrorCount(result.errors.length)}`);
            this._goTo("paste");
            return;
        }

        this._lastFind = result;
        this._findText = text;
        this.foundItems(result.identified.map(describeFoundItem));
        this.reviewTitle(describeFound(result));
        this._setErrors(result.errors);
        this._announce(result.errors.length > 0
            ? `${this.reviewTitle()}. ${formatErrorCount(result.errors.length)}`
            : this.reviewTitle());
        this._goTo("review");
    }

    private async _addAsync(found: IFindItemsResult, run: number, correlationId: string): Promise<void> {
        let result: IAddItemsResult;
        try {
            result = await addIdentifiedLinesAsync(this.context, found.identified, correlationId);
        } catch (error) {
            if (this._isDisposed) {
                return;
            }

            // Some lines may be in the cart, so the grid is read again and the associate checks it.
            this.context.logger.logWarning(`Counter order: adding the items failed. ${describeError(error)}`, correlationId);
            this._refreshCart();
            if (run === this._dialogRun) {
                this.isAdding(false);
                this._showFailure(ADD_FAILED);
            }

            return;
        }

        if (this._isDisposed) {
            return;
        }

        if (result.addedCount > 0) {
            this._refreshCart();
        }

        if (run === this._dialogRun) {
            this.isAdding(false);
            this._showAdded(found, result);
        }
    }

    private _showAdded(found: IFindItemsResult, result: IAddItemsResult): void {
        const errors: IBulkLineError[] = found.errors.concat(result.errors);
        this._hasAddRun = true;
        this._lastAddErrors = errors;
        this.addedCount(this.addedCount() + result.addedCount);

        // As in POS, the dialog closes once every line is in the cart.
        if (errors.length === 0 && result.addedCount === found.totalLines) {
            this._closeDialog();
            return;
        }

        // The lines added leave the list, so they can't be added twice.
        this._lastFind = null;
        this.foundItems([]);
        this.bulkText(buildRemainingText(errors));
        this._setErrors(errors);
        const added: string = result.addedCount > 0 ? formatAddedCount(result.addedCount) : "Lines not added to transaction";
        this._announce(`${added}. ${formatErrorCount(errors.length)}`);
        this._goTo("paste");
    }

    private _setErrors(errors: ReadonlyArray<IBulkLineError>): void {
        this.errors(errors.map((error: IBulkLineError, index: number): ICounterOrderError => {
            return { key: `${error.lineNumber}-${index}`, message: error.message };
        }));
    }

    private _showFailure(message: string): void {
        this.errors([{ key: "failure", message: message }]);
        this._announce(message);
        this._focusStep();
    }

    private _announce(text: string): void {
        // Clearing first lets a screen reader read the same text again.
        this.statusText(StringExtensions.EMPTY);
        this.statusText(text);
    }

    private _isCurrentRun(run: number): boolean {
        return !this._isDisposed && run === this._dialogRun;
    }

    private _showToast(toast: IBulkAddToast, correlationId: string): void {
        if (this._isDisposed) {
            return;
        }

        const messageType: ClientEntities.ToastMessageType = toToastMessageType(toast.kind);
        const content: ClientEntities.IToastNotificationComponentContent = toast.body
            ? { notificationTitle: toast.title, notificationBody: toast.body, notificationMessageType: messageType }
            : { notificationTitle: toast.title, notificationMessageType: messageType };
        this.context.runtime.executeAsync(
            new TriggerToastNotificationClientRequest<TriggerToastNotificationClientResponse>(correlationId, content)
        ).catch((error: unknown): void => {
            if (!this._isDisposed) {
                this.context.logger.logWarning(`Counter order: the toast couldn't be shown. ${describeError(error)}`, correlationId);
            }
        });
    }

    private _logUnexpected(action: string, error: unknown): void {
        if (!this._isDisposed) {
            this.context.logger.logWarning(`Counter order: ${action} failed. ${describeError(error)}`, this._dialogCorrelationId);
        }
    }

    private _refreshCart(): void {
        if (this._isDisposed) {
            return;
        }

        const sequence: number = ++this._cartSequence;
        const correlationId: string = this.context.logger.getNewCorrelationId();
        if (!this._hasCart) {
            this.cartStatus("loading");
        }

        this._readCartAsync(correlationId)
            .then((cart: ProxyEntities.Cart | undefined): void => {
                if (!this._isDisposed && sequence === this._cartSequence) {
                    this._showCart(cart);
                }
            })
            .catch((error: unknown): void => {
                if (this._isDisposed || sequence !== this._cartSequence) {
                    return;
                }

                this.context.logger.logWarning(`Counter order: the cart couldn't be read. ${describeError(error)}`, correlationId);
                if (!this._hasCart) {
                    this.cartStatus("failed");
                }
            });
    }

    private async _readCartAsync(correlationId: string): Promise<ProxyEntities.Cart | undefined> {
        if (!this._deliveryModeCodes) {
            this._deliveryModeCodes = await this._readDeliveryModeCodesAsync(correlationId);
            if (this._isDisposed) {
                return undefined;
            }
        }

        const response: ClientEntities.ICancelableDataResult<GetCurrentCartClientResponse> = await this.context.runtime.executeAsync(
            new GetCurrentCartClientRequest<GetCurrentCartClientResponse>(correlationId));
        return response.canceled ? undefined : response.data.result;
    }

    private async _readDeliveryModeCodesAsync(correlationId: string): Promise<IDeliveryModeCodes | null> {
        try {
            const response: ClientEntities.ICancelableDataResult<GetChannelConfigurationClientResponse> = await this.context.runtime.executeAsync(
                new GetChannelConfigurationClientRequest<GetChannelConfigurationClientResponse>(correlationId));
            const configuration: ProxyEntities.ChannelConfiguration | undefined = response.canceled ? undefined : response.data.result;
            if (!configuration) {
                return null;
            }

            return {
                pickup: configuration.PickupDeliveryModeCode || StringExtensions.EMPTY,
                carryout: configuration.CarryoutDeliveryModeCode || StringExtensions.EMPTY,
                email: configuration.EmailDeliveryModeCode || StringExtensions.EMPTY
            };
        } catch (error) {
            // The lines are still shown; ones with a delivery mode show as shipped until the modes can be read.
            if (!this._isDisposed) {
                this.context.logger.logWarning(`Counter order: the delivery modes couldn't be read. ${describeError(error)}`, correlationId);
            }

            return null;
        }
    }

    private _showCart(cart: ProxyEntities.Cart | undefined): void {
        const codes: IDeliveryModeCodes | null = this._deliveryModeCodes;
        const lines: ProxyEntities.CartLine[] = cart && cart.CartLines
            ? cart.CartLines.filter((line: ProxyEntities.CartLine): boolean => !line.IsVoided)
            : [];

        this.cartLines(lines.map((line: ProxyEntities.CartLine, index: number): ICounterOrderLine => describeCartLine(line, index, codes)));
        this.lineCountText(formatLines(lines.length));
        this.subtotalText(formatAmount(cart ? cart.SubtotalAmountWithoutTax : 0));
        this.savingsText(formatAmount(cart ? cart.DiscountAmount : 0));
        this.totalText(formatAmount(cart ? cart.TotalAmount : 0));
        this._hasCart = true;
        this.cartStatus("ready");
    }

    private _focusStep(focusSelector?: string): void {
        const run: number = this._dialogRun;
        setTimeout((): void => {
            if (!this._isCurrentRun(run) || !this.isDialogOpen() || this.isBusy()) {
                return;
            }

            const target: HTMLElement | null = this._find(focusSelector || STEP_FOCUS_SELECTORS[this.step()]);
            if (target) {
                target.focus();
            }
        }, 0);
    }

    /** The dialog's controls are disabled while it works, so it holds the focus itself. */
    private _focusDialog(): void {
        const surface: HTMLElement | null = this._find(".counterOrderDialog");
        if (surface) {
            surface.focus();
        }
    }

    private _restoreFocus(): void {
        const opener: HTMLElement | null = this._opener;
        this._opener = null;
        const target: HTMLElement | null = opener && opener.isConnected ? opener : this._find(".counterOrderBulkAddButton");
        if (target) {
            target.focus();
        }
    }

    private _keepFocusInDialog(event: KeyboardEvent): boolean {
        const surface: HTMLElement | null = this._find(".counterOrderDialog");
        if (!surface) {
            return true;
        }

        const focusable: HTMLElement[] = findFocusable(surface);
        if (focusable.length === 0) {
            surface.focus();
            return false;
        }

        const first: HTMLElement = focusable[0];
        const last: HTMLElement = focusable[focusable.length - 1];
        const active: Element | null = document.activeElement;
        if (active === surface || !surface.contains(active)) {
            (event.shiftKey ? last : first).focus();
            return false;
        }

        if (event.shiftKey && active === first) {
            last.focus();
            return false;
        }

        if (!event.shiftKey && active === last) {
            first.focus();
            return false;
        }

        return true;
    }

    private _find(selector: string): HTMLElement | null {
        return this._element ? this._element.querySelector(selector) as HTMLElement : null;
    }
}

/**
 * Describes a cart line for the grid.
 * @param line The cart line.
 * @param index The line's position, used when it has no line ID yet.
 * @param codes The store's delivery mode codes, when they could be read.
 * @returns The line as the grid shows it.
 */
function describeCartLine(line: ProxyEntities.CartLine, index: number, codes: IDeliveryModeCodes | null): ICounterOrderLine {
    const quantity: number = toNumber(line.Quantity);
    const netPrice: number = quantity !== 0
        ? (toNumber(line.ExtendedPrice) - toNumber(line.DiscountAmount)) / quantity
        : toNumber(line.Price);
    const itemId: string = line.ItemId || StringExtensions.EMPTY;
    return {
        key: line.LineId || String(index),
        name: line.Description || itemId,
        itemId: itemId,
        quantity: formatQuantity(quantity),
        unit: line.UnitOfMeasureSymbol || StringExtensions.EMPTY,
        netPrice: CurrencyFormatter.toCurrency(netPrice),
        fulfillment: describeFulfillment(line.DeliveryMode, codes)
    };
}

/**
 * Names how a line is fulfilled, as the POS cart does: a line without a delivery mode is carried out.
 * @param deliveryMode The line's delivery mode code.
 * @param codes The store's delivery mode codes, when they could be read.
 * @returns The name.
 */
function describeFulfillment(deliveryMode: string | undefined, codes: IDeliveryModeCodes | null): string {
    const mode: string = (deliveryMode || StringExtensions.EMPTY).trim();
    if (mode.length === 0 || (codes && isSameCode(mode, codes.carryout))) {
        return "Carry out";
    }

    if (codes && isSameCode(mode, codes.pickup)) {
        return "Pick up";
    }

    if (codes && isSameCode(mode, codes.email)) {
        return "Email";
    }

    return "Ship";
}

function isSameCode(mode: string, code: string): boolean {
    return code.length > 0 && mode.toLowerCase() === code.trim().toLowerCase();
}

/**
 * Describes a product found in the list, for the associate to check.
 * @param line The line and its product.
 * @param index The line's position in the list found.
 * @returns The product as the dialog lists it.
 */
function describeFoundItem(line: IIdentifiedLine, index: number): ICounterOrderFoundItem {
    const product: ProxyEntities.SimpleProduct = line.product;
    const itemId: string = product.ItemId || line.parseLine.sku;
    const options: string[] = (product.Dimensions || [])
        .map((dimension: ProxyEntities.ProductDimension): string =>
            dimension && dimension.DimensionValue && dimension.DimensionValue.Value ? dimension.DimensionValue.Value : StringExtensions.EMPTY)
        .filter((value: string): boolean => value.length > 0);

    return {
        key: `${line.parseLine.lineNumber}-${index}`,
        name: product.Name || itemId,
        detail: [itemId].concat(options).join(" \u00B7 "),
        quantity: `Qty ${formatQuantity(line.parseLine.quantity)}`,
        needsOptions: requiresVariantSelection(product),
        readAs: line.readAs ? `On the list: "${line.readAs}"` : StringExtensions.EMPTY
    };
}

/**
 * Says how many products were found, and out of how many lines when some weren't.
 * @param result What finding the products came to.
 * @returns The text.
 */
function describeFound(result: IFindItemsResult): string {
    const found: number = result.identified.length;
    if (result.errors.length > 0) {
        return `${found} of ${result.totalLines} items found`;
    }

    return found === 1 ? "1 item found" : `${found} items found`;
}

/**
 * Says why Copilot couldn't read the list in a photo. A request that never reached the gateway says so, rather
 * than passing on the browser's words for it.
 * @param error What the gateway client threw.
 * @returns The message to show.
 */
function describeReadFailure(error: unknown): string {
    const detail: string = describeError(error);
    if (/failed to fetch|networkerror|load failed|network request failed/i.test(detail)) {
        return COPILOT_UNREACHABLE;
    }

    return detail.length > 0 ? `${READ_FAILED} ${detail}` : `${READ_FAILED} Try again.`;
}

/**
 * Gets the browser's own event. When POS has loaded jQuery, Knockout passes handlers jQuery's copy of the event,
 * which leaves out what was pasted or dragged.
 * @param event The event as the handler got it.
 * @returns The browser's event.
 */
function browserEventOf(event: Event): Event {
    const original: Event | undefined = event ? (event as Event & { originalEvent?: Event }).originalEvent : undefined;
    return original || event;
}

function readClipboardData(event: Event): DataTransfer | null {
    const browserEvent: Event = browserEventOf(event);
    return browserEvent ? (browserEvent as ClipboardEvent).clipboardData || null : null;
}

function readDataTransfer(event: Event): DataTransfer | null {
    const browserEvent: Event = browserEventOf(event);
    return browserEvent ? (browserEvent as DragEvent).dataTransfer || null : null;
}

function readClipboardText(event: Event): string {
    const clipboardData: DataTransfer | null = readClipboardData(event);
    if (!clipboardData) {
        return StringExtensions.EMPTY;
    }

    return clipboardData.getData("text/plain") || clipboardData.getData("text") || StringExtensions.EMPTY;
}

/** Says whether a drag carries files, as opposed to text or a link. */
function isDraggingFiles(dataTransfer: DataTransfer | null): boolean {
    return hasType(dataTransfer, "Files");
}

/**
 * Gets the photo pasted, as the side panel does: the first file, unless text came with it. Copying cells from a
 * spreadsheet puts a picture of them on the clipboard as well as their text.
 * @param clipboardData What was pasted.
 * @returns The file, or undefined when no file was pasted on its own.
 */
function readPastedFile(clipboardData: DataTransfer | null): File | undefined {
    const files: FileList | null = clipboardData ? clipboardData.files : null;
    if (!files || files.length === 0 || hasType(clipboardData, "text/plain")) {
        return undefined;
    }

    return files[0];
}

function hasType(dataTransfer: DataTransfer | null, type: string): boolean {
    const types: ReadonlyArray<string> | null = dataTransfer ? dataTransfer.types : null;
    if (!types) {
        return false;
    }

    for (let i: number = 0; i < types.length; i++) {
        if (types[i] === type) {
            return true;
        }
    }

    return false;
}

function findFocusable(root: HTMLElement): HTMLElement[] {
    const candidates: NodeListOf<HTMLElement> = root.querySelectorAll(FOCUSABLE_SELECTOR) as NodeListOf<HTMLElement>;
    const focusable: HTMLElement[] = [];
    for (let i: number = 0; i < candidates.length; i++) {
        const candidate: HTMLElement = candidates[i];
        if (candidate.tabIndex >= 0 && !(candidate as HTMLButtonElement).disabled && candidate.getClientRects().length > 0) {
            focusable.push(candidate);
        }
    }

    return focusable;
}

function toToastMessageType(kind: IBulkAddToast["kind"]): ClientEntities.ToastMessageType {
    switch (kind) {
        case "success":
            return ClientEntities.ToastMessageType.SUCCESS;
        case "error":
            return ClientEntities.ToastMessageType.ERROR;
        default:
            return ClientEntities.ToastMessageType.INFO;
    }
}

function formatLines(count: number): string {
    return count === 1 ? "1 line" : `${count} lines`;
}

function formatErrorCount(count: number): string {
    return count === 1 ? "1 error" : `${count} errors`;
}

function formatQuantity(quantity: number): string {
    return String(Math.round(quantity * 1000) / 1000);
}

function formatAmount(amount: number | undefined): string {
    return CurrencyFormatter.toCurrency(toNumber(amount));
}

function toNumber(value: number | undefined): number {
    return typeof value === "number" && isFinite(value) ? value : 0;
}
