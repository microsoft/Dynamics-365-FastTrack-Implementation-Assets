/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Ambient type declarations for the bundled AMD module `ContosoSideChat`.
 *
 * The implementation lives in Libraries/ContosoSideChat.js — a self-contained bundle produced from
 * the React/Fluent UI sources in this folder by webpack (see webpack.config.js). It is registered as
 * an AMD dependency in the POS manifest, which is how POS extension code (compiled to SystemJS)
 * resolves it at runtime. These declarations let the POS TypeScript build type-check the import.
 */
declare module "ContosoSideChat" {
    /** A file the operator attached to a message, ready to send. */
    export interface ISideChatAttachment {
        /** The file's name, as the operator's device named it. */
        name: string;
        /**
         * The media type of `data`: "image/jpeg", "image/png", "image/webp", "image/gif" or
         * "application/pdf". The panel sends every photo as JPEG, shrunk on the device.
         */
        type: string;
        /** The content, base64 encoded, without a `data:` prefix. */
        data: string;
        /** The size of the content before encoding, in bytes. */
        size: number;
    }

    /** What the conversation shows of a file sent with a message. */
    export interface ISideChatAttachmentPreview {
        name: string;
        type: string;
        /** A small copy of a photo, as a data URL. Absent for a PDF. */
        thumbnailUrl?: string;
    }

    /** A single message in the side panel conversation. */
    export interface SideChatMessage {
        id: string;
        role: "user" | "assistant";
        /** Empty on an operator's message that only sent files. */
        text: string;
        toolActivities?: ReadonlyArray<IAgentToolActivity>;
        /** Set on an assistant message that POS asked for on its own, rather than one answering the operator. */
        origin?: "cartSuggestion";
        /** The files the operator sent with the message. Only on the operator's messages. */
        attachments?: ReadonlyArray<ISideChatAttachmentPreview>;
    }

    /** One dimension that identifies a selected product variant. */
    export interface IAgentProductDimensionSelection {
        name: string;
        value: string;
    }

    /** Associates a displayed master product with the exact variant selected for sale. */
    export interface IAgentProductSelection {
        productId: number;
        variantProductId: number;
        dimensions: IAgentProductDimensionSelection[];
    }

    /** Grounded Commerce identifiers required to create one shipped customer order. */
    export interface IAgentCustomerOrderRequest {
        customerAccountNumber: string;
        productId: number;
        variantProductId: number;
        dimensions: IAgentProductDimensionSelection[];
        quantity: number;
        shippingAddressRecordId: number;
        fulfillmentStoreId: string;
        warehouseId?: string;
        deliveryModeCode: string;
        requestedShipDate: string;
        sourceStoreName?: string;
        deliveryModeName?: string;
        /** Display only: the variant's available quantity at the source store, from the inventory tool. */
        sourceStoreAvailableQuantity?: number;
        /** Display only: the distance to the source store as the inventory tool reports it, for example "1.8 mi". */
        sourceStoreDistance?: string;
        /** Display only: the variant's available quantity at the current store, from the inventory tool. */
        currentStoreAvailableQuantity?: number;
    }

    /** Which of a customer's saved addresses an order ships to. "Work" and "Business" are the same type. */
    export type AgentShippingAddressType = "Primary" | "Home" | "Work" | "Business" | "Delivery" | "Invoice" | "Other";

    /** One product on the sale that ships, and the store that ships it. */
    export interface IAgentShippingItem {
        /** A product on the sale: the identifier `sale` lists for it, or its master product's. */
        productId: number;
        /** The store that ships it, as the inventory tool's store number. Defaults to the request's. */
        shipFromStoreNumber?: string;
        /** Display only: how far away that store is, as the inventory tool reported it, for example "195.3 mi". */
        distance?: string;
        /** Display only: the product's available quantity at that store, from the inventory tool. */
        availableQuantity?: number;
    }

    /** Ships products already on the sale to one of a customer's saved addresses, in the associate's words. */
    export interface IAgentShippingRequest {
        /** The customer's name as the associate said it. Not needed when the sale already has the customer. */
        customerName?: string;
        /** Which saved address to ship to. The customer's primary address when omitted. */
        addressType?: AgentShippingAddressType;
        /** The delivery mode as the associate said it, for example "Standard shipping". */
        deliveryMode: string;
        /** For "in 2 days": how many days from today the order is delivered. Wins over `deliveryDate`. */
        deliveryInDays?: number;
        /** The delivery date the associate gave, as YYYY-MM-DD. */
        deliveryDate?: string;
        /** The store that ships the products, unless an item names its own. The associate's store when omitted. */
        shipFromStoreNumber?: string;
        /** The products that ship, each with its store. Every product on the sale ships when omitted. */
        items?: IAgentShippingItem[];
    }

    /** Why one suggested product goes with the current cart. */
    export interface IAgentProductReason {
        productId: number;
        reason: string;
    }

    /** Stock at one store, as the agent read it with the Commerce inventory tools. Display only. */
    export interface IAgentStoreStock {
        /** The store's name as the inventory tool reported it. Only for another store; POS names its own. */
        name?: string;
        /** The available quantity. 0 when the store has none. */
        quantity?: number;
        /** The stock status as the inventory tool reported it, when it gave no quantity. */
        status?: string;
        /** How far away the store is, with its unit, for example "12.4 mi". */
        distance?: string;
    }

    /** The stock the agent reported for one recommended product. */
    export interface IAgentProductInventory {
        /** A product record identifier from `productIds`, or the variant selected for it. */
        productId: number;
        /** Stock at the associate's own store. */
        currentStore?: IAgentStoreStock;
        /** Stock at the closest other store that has the product. */
        nearestStore?: IAgentStoreStock;
    }

    /**
     * One filter the agent reports for a set of recommendations, such as the size the associate asked
     * for. A hint only: POS builds the filter tags itself and filters the products in POS.
     */
    export interface IAgentProductFilter {
        /** What the filter is on, for example "Size", "Color", "Price" or "Feature". */
        name: string;
        /** The value, for example "M", "Black" or "Under $300". */
        value: string;
        /** The text the agent would show for it, for example "Size M". */
        label?: string;
        /** True when every product shown already meets this filter. */
        applied?: boolean;
    }

    /** The associate's store, as POS sends it with each request the associate types. */
    export interface IAgentStoreContext {
        /** The store's organization unit number, for example "HOUSTON". */
        number: string;
        /** The store's name. Its number when POS has no name for it. */
        name: string;
        /** The store's channel record identifier. */
        channelId?: number;
        /** Where the store is, when Commerce has its location. */
        latitude?: number;
        longitude?: number;
    }

    /** The values the agent chose for an action. */
    export interface IAgentActionDetails {
        /** A product record identifier. Exceeds 32 bits but stays inside Number.MAX_SAFE_INTEGER. */
        productId?: number;
        /** The products the agent curated, as record identifiers only. */
        productIds?: number[];
        /** Exact variants selected for products whose requested dimensions were fully resolved. */
        productSelections?: IAgentProductSelection[];
        /** A fully resolved request to create and ship a customer order. */
        customerOrder?: IAgentCustomerOrderRequest;
        /** Ships the products on the sale to a customer's saved address. */
        shipping?: IAgentShippingRequest;
        /** The one product the agent recommends. Shown first and badged. */
        bestMatchProductId?: number;
        /** Why that product was recommended. Shown on its card. */
        bestMatchReason?: string;
        /** A short headline for the results. */
        headline?: string;
        /** One short reason per suggested product, saying why it goes with the current cart. */
        reasons?: IAgentProductReason[];
        /** Each recommended product's stock here and at the closest other store. Display only. */
        inventory?: IAgentProductInventory[];
        /** The filters the recommendations already meet. POS uses them to lock its own filter tags. */
        filters?: IAgentProductFilter[];
        /** A cart planned from what the customer is shopping for, for the associate to review and add. */
        cartPlan?: IAgentCartPlan;
    }

    /** Whether a cart plan's budget limits each item or the whole cart. */
    export type AgentCartBudgetScope = "eachItem" | "total";

    /** The spending limit the associate gave for a cart plan, in the store's currency. */
    export interface IAgentCartBudget {
        /** The limit, for example 100. */
        amount: number;
        /** The ISO currency code the associate used, when they said one. Display only. */
        currency?: string;
        /** "eachItem" (the default) when every item must cost no more than the limit; "total" for the whole cart. */
        appliesTo?: AgentCartBudgetScope;
    }

    /** One product in a cart the agent planned from what the customer is shopping for. */
    export interface IAgentCartPlanItem {
        /** A product record identifier from the Commerce search tools. */
        productId: number;
        /** The need it covers, in a few words, for example "Sun protection". Each item covers a different need. */
        need: string;
        /** Why it was picked, in one short sentence. */
        reason: string;
    }

    /** A cart the agent planned from what the customer is shopping for, such as a beach vacation. */
    export interface IAgentCartPlan {
        /** What the customer is shopping for, for example "Beach vacation". */
        intent: string;
        /** A short headline, for example "Beach vacation essentials under $100". */
        headline?: string;
        /** One or two sentences on how the items were chosen. Shown as the plan's insights. */
        summary: string;
        budget?: IAgentCartBudget;
        /** Three to eight products, each covering a different need. */
        items: IAgentCartPlanItem[];
    }

    /** One action the agent wants POS to run. */
    export interface IAgentPosAction {
        action: string;
        details?: IAgentActionDetails;
    }

    /** How POS runs a batch of the agent's actions. */
    export interface IAgentActionExecutionOptions {
        /**
         * True for a turn POS started on its own, such as an automatic cart check. POS then only shows
         * suggested products in the panel. It never navigates or changes the transaction, and it
         * ignores every other action.
         */
        automatic?: boolean;
        /**
         * Products already in the cart, including the masters of variants in it. POS leaves them out
         * of suggestions, whatever the agent returned.
         */
        excludedProductIds?: ReadonlyArray<number>;
    }

    /** What an inline product preview shows. */
    export type AgentProductPreviewKind = "recommendations" | "cartSuggestions";

    /** Commerce-resolved products shown inline beneath an assistant reply. */
    export interface IAgentProductPreview {
        products: ReadonlyArray<IAgentProductCard>;
        productIds: ReadonlyArray<number>;
        productSelections?: ReadonlyArray<IAgentProductSelection>;
        bestMatchProductId?: number;
        bestMatchReason?: string;
        headline?: string;
        /** Defaults to "recommendations". */
        kind?: AgentProductPreviewKind;
        /** One short reason per product, shown on its card. */
        productReasons?: ReadonlyArray<IAgentProductReason>;
        /** The stock the agent reported, at most one entry per product, keyed by displayed product. */
        inventory?: ReadonlyArray<IAgentProductInventory>;
        /** The associate's store's name, which labels its stock. */
        currentStoreName?: string;
        /**
         * Filter tags POS built for recommendations: Color, Size and Price, then the other refiners
         * Commerce returns, such as Rating and Category. Never set for cart suggestions.
         */
        filterFacets?: ReadonlyArray<IAgentProductFacet>;
    }

    /** What a filter tag row filters on: a variant's colour or size, the price, the rating, the category or another refiner. */
    export type AgentProductFacetKind = "color" | "size" | "price" | "rating" | "category" | "attribute";

    /** One filter tag, such as a colour, a size, a price range, a rating or a category. */
    export interface IAgentProductFacetValue {
        /** Identifies the value within its facet. */
        key: string;
        /** The text on the tag. */
        label: string;
        /** The colour of a colour tag's swatch, as a CSS colour. */
        swatchColor?: string;
        /** The lowest price a price tag includes. */
        minPrice?: number;
        /** The price a price tag stops below. */
        maxPrice?: number;
        /** The Commerce refiner value behind any tag but a price range. Opaque to the panel. */
        refinerValue?: unknown;
    }

    /** One row of filter tags POS built from Commerce's refiners, or the prices, for the products shown. */
    export interface IAgentProductFacet {
        /** Identifies the row: "color", "size", "price", or one per other refiner. The selection is keyed by it. */
        key: string;
        kind: AgentProductFacetKind;
        /** The row's label, for example "Color" or "Rating". */
        label: string;
        /** The tags. Only the locked tag when `lockedKey` is set. */
        values: ReadonlyArray<IAgentProductFacetValue>;
        /** The value every product shown already has. Shown as selected and cannot be cleared. */
        lockedKey?: string;
        /** True when one tag at a time can be selected in the row. */
        singleSelect?: boolean;
        /** True for a product dimension other than Color and Size, whose locked tag is sent with the tags selected. */
        isDimension?: boolean;
    }

    /** The tags the associate selected, as value keys by row key. */
    export interface IAgentProductFilterSelection {
        readonly [facetKey: string]: ReadonlyArray<string> | undefined;
    }

    /** Asks POS which of the products shown have the selected tags other than prices. */
    export interface IAgentProductFilterRequest {
        /** The products shown, as the agent listed them. */
        productIds: ReadonlyArray<number>;
        /** The selected tags other than prices, and the locked tags of the variants' rows. */
        values: ReadonlyArray<IAgentProductFacetValue>;
    }

    /** One line of the current cart, as POS sends it with an automatic cart check. */
    export interface IAgentCartLine {
        /** The record identifier of the product sold on the line. For a variant, the variant's identifier. */
        productId: number;
        /** The master product's record identifier, when the line sells a variant. */
        masterProductId?: number;
        itemId?: string;
        name?: string;
        quantity: number;
        /** Unit price. */
        price?: number;
        /** Line total after discounts. */
        total?: number;
        /** Discount already applied to the line. */
        discount?: number;
        /** Names of the discounts already applied to the line. */
        offers?: string[];
        /** Promotions Commerce lists for the line. */
        promotions?: string[];
    }

    /** The current cart, as POS sends it with an automatic cart check. */
    export interface IAgentCartSnapshot {
        /** Every distinct product record identifier sold in the cart. */
        productIds: number[];
        /** The products whose addition started this check. */
        addedProductIds: number[];
        /** The active sale lines, newest first. */
        lines: IAgentCartLine[];
        /** How many lines were left out to keep the request inside the gateway's size limit. */
        omittedLines?: number;
        /** How many product identifiers were left out for the same reason. */
        omittedProductIds?: number;
        subtotal?: number;
        discount?: number;
        total?: number;
    }

    /** What POS sends up on every request. */
    export interface IAgentRequestEnvelope {
        text: string;
        conversationId: string;
        cartId: string;
        currentView: string;
        /** Names of the actions this POS build can perform. The agent instructions define each one. */
        supportedActions: string[];
        /** Present only on turns POS started on its own. The operator did not type anything. */
        trigger?: "cartItemAdded";
        /** Present only on automatic cart checks: the cart the agent is asked about. */
        cart?: IAgentCartSnapshot;
        /** The associate's store. Sent with the requests the associate types, when POS can read it. */
        store?: IAgentStoreContext;
        /**
         * Present only when the associate attached files to the message: their names and types, in
         * the order attached. The files themselves travel beside the envelope.
         */
        attachments?: IAgentAttachmentInfo[];
        /** The products on the current sale. Sent with the requests the associate types, when the sale has any. */
        sale?: IAgentSaleSnapshot;
        /**
         * A POS operation that failed on the associate's screen in the last few minutes. Sent with the
         * requests the associate types, so the agent can help with it.
         */
        posError?: IAgentPosErrorContext;
    }

    /** Whether POS could reach Commerce when an operation failed. */
    export type AgentPosConnectivity = "Online" | "Offline";

    /**
     * A POS operation that failed on the associate's screen. Diagnostic fields only: never payment
     * data, tokens or customer contact details.
     */
    export interface IAgentPosErrorContext {
        /** The error code the IT support guide is keyed on, for example "CUSTOMER_ORDER_LOOKUP_FAILED". */
        code: string;
        /** The message POS showed. */
        message: string;
        /** The operation that failed, for example "Customer order lookup". */
        operation: string;
        /** The correlation identifier of the failed call, which IT support uses to find its logs. */
        correlationId: string;
        /** When it failed, as an ISO 8601 date and time with the register's UTC offset. */
        occurredAt: string;
        /** The store's number, for example "HOUSTON". */
        storeId?: string;
        /** The register's identifier, for example "HOUSTON-2". */
        registerId?: string;
        /** The POS application version. */
        posVersion?: string;
        connectivity?: AgentPosConnectivity;
        /** How many times the associate already retried the operation. */
        retryCount: number;
        /** The order number the associate looked up. */
        orderNumber?: string;
    }

    /** One product on the current sale, as POS sends it with the requests the associate types. */
    export interface IAgentSaleLine {
        /** The record identifier of the product sold. For a variant, the variant's identifier. */
        productId: number;
        /** The product's name on the sale. Left out when the request would otherwise be too large. */
        name?: string;
        quantity: number;
    }

    /** The products on the current sale, newest first. */
    export interface IAgentSaleSnapshot {
        lines: IAgentSaleLine[];
        /** How many lines were left out to keep the request inside the gateway's size limit. */
        omittedLines?: number;
    }

    /** A file the associate sent with a message, as the request envelope names it. */
    export interface IAgentAttachmentInfo {
        /** The file's name, as the associate's device named it. */
        name: string;
        /** Its media type, such as "image/jpeg" or "application/pdf". */
        type: string;
    }

    /** What the agent sends back. */
    export interface IAgentResponseEnvelope {
        conversationId?: string;
        displayMessage: string;
        posActions: IAgentPosAction[];
    }

    /** How an action POS attempted to run turned out. */
    export type ActionOutcome = "ran" | "failed" | "unsupported";

    /** A record of one action POS attempted, shown under the reply in the panel. */
    export interface IActionReceipt {
        action: string;
        summary: string;
        outcome: ActionOutcome;
        productPreview?: IAgentProductPreview;
        /** Present when POS successfully concluded a customer order. */
        customerOrderReceipt?: IAgentCustomerOrderReceipt;
        /** Present when POS set the sale to ship. */
        shippingReceipt?: IAgentShippingReceipt;
        /** Present when POS resolved a cart plan the associate can review and add to the sale. */
        cartPlan?: IAgentCartPlanReceipt;
    }

    /** One product in a cart plan, read from the Commerce channel by POS. */
    export interface IAgentCartPlanReceiptItem {
        card: IAgentProductCard;
        /** The need it covers, as the agent named it. */
        need: string;
        /** Why the agent picked it. */
        reason: string;
        /** True when its price is over a per-item budget. Such items start unselected. */
        overBudget?: boolean;
    }

    /** A cart plan ready for the associate to review, shown as a checklist under the reply. */
    export interface IAgentCartPlanReceipt {
        intent: string;
        headline?: string;
        /** How the items were chosen. */
        summary: string;
        budget?: IAgentCartBudget;
        /** The products, one per need, in the agent's order. */
        items: ReadonlyArray<IAgentCartPlanReceiptItem>;
        /** How many products the agent named that POS left out, as repeats or because the channel does not sell them. */
        omittedCount?: number;
    }

    /** Commerce-confirmed result of creating a customer order. */
    export interface IAgentCustomerOrderReceipt {
        orderNumber: string;
        customerName: string;
        itemName: string;
        sourceStore: string;
        /** For example "2 available". Omitted when the agent did not report it. */
        sourceStoreAvailability?: string;
        /** For example "1.8 mi". Omitted when the agent did not report it. */
        sourceStoreDistance?: string;
        /** For example "Out of stock". Omitted when the agent did not report it. */
        currentStoreAvailability?: string;
        shippingAddress: string;
        deliveryMethod: string;
        status: "Created";
    }

    /** One product on a shipping receipt. */
    export interface IAgentShippingReceiptLine {
        name: string;
        quantity: number;
        /** The store that ships it. */
        shipFrom: string;
        /** What the agent reported about that store, for example "195.3 mi · 4 available". Display only. */
        shipFromDetail?: string;
    }

    /** What POS set on the sale when it set it to ship. Read back from Commerce, except `shipFromDetail`. */
    export interface IAgentShippingReceipt {
        customerName: string;
        customerAccount?: string;
        /** The kind of address, for example "Home". */
        addressType?: string;
        shippingAddress: string;
        deliveryMethod: string;
        /** Formatted for display by POS. */
        deliveryDate: string;
        lines: IAgentShippingReceiptLine[];
        /** The sale's total, formatted for display by POS. */
        total?: string;
        /** The sale's shipping charges, formatted for display by POS. */
        shippingCharges?: string;
        /** What remains to pay, formatted for display by POS. */
        amountDue?: string;
        status: "Ready for checkout";
    }

    /** What a backend answers with. */
    export interface ISideChatReply {
        displayMessage: string;
        posActions?: IAgentPosAction[];
        toolActivities?: ReadonlyArray<IAgentToolActivity>;
    }

    /** What POS asks about when it checks the cart on its own, without the operator typing anything. */
    export interface ICartSuggestionRequest {
        /** The transaction the snapshot was taken from. */
        cartId: string;
        /** The cart when the check started. */
        cart: IAgentCartSnapshot;
    }

    /** The agent's answer to an automatic cart check. */
    export interface ICartSuggestionReply extends ISideChatReply {
        /**
         * Makes this reply part of the agent conversation, so a follow-up question can refer to it.
         * Called once the reply is shown. Does nothing when the operator has sent a message since the
         * check started.
         */
        acceptIntoConversation?: () => void;
    }

    /** Backend used to answer prompts typed into the side panel. */
    export interface ISideChatClient {
        /** Optional. True when sendAsync can send files with a prompt; the panel offers attachments only then. */
        readonly acceptsAttachments?: boolean;

        /**
         * Answers a prompt.
         * @param prompt The text the operator typed. Empty when they only sent files.
         * @param history The conversation so far, including the prompt.
         * @param viewContext The POS view that was open when the prompt was sent, or null when unknown.
         * @param attachments The files the operator attached, when the client accepts attachments.
         */
        sendAsync(
            prompt: string,
            history: ReadonlyArray<SideChatMessage>,
            viewContext: string | null,
            attachments?: ReadonlyArray<ISideChatAttachment>
        ): Promise<ISideChatReply>;

        /** Optional. Asks which products would go well with the current cart. */
        suggestForCartAsync?(request: ICartSuggestionRequest, viewContext: string | null): Promise<ICartSuggestionReply>;

        /**
         * Optional. Forgets the conversation so far, so the next prompt starts a new one. Called when
         * the operator starts a new chat.
         */
        startNewConversation?(): void;
    }

    /** A starter prompt that needs a file, such as a photo, before it can be sent. */
    export interface ISideChatSuggestion {
        /** The prompt, as shown and as put in the message box. */
        text: string;
        /**
         * A word in the text that names the file to attach. Shown as a link; choosing the suggestion
         * puts the text in the message box and opens the file picker. Hidden when the client can't
         * take files.
         */
        attachmentWord?: string;
    }

    /** A starter prompt: plain text that is sent as it is, or one that needs a file first. */
    export type SideChatSuggestion = string | ISideChatSuggestion;

    /** Starter prompts shown in the panel's rest state. */
    export const DEFAULT_SIDE_CHAT_SUGGESTIONS: ReadonlyArray<SideChatSuggestion>;

    /** Options accepted when mounting the side panel. */
    export interface SideChatMountOptions {
        client: ISideChatClient;
        title?: string;
        suggestions?: ReadonlyArray<SideChatSuggestion>;
        getViewContext?: () => string | null;
        /** The panel passes `{ automatic: true }` for the actions of an automatic cart check. */
        executeActions?: (
            actions: ReadonlyArray<IAgentPosAction>,
            options?: IAgentActionExecutionOptions
        ) => Promise<ReadonlyArray<IActionReceipt>>;
        onPreviewProductActivated?: (recordId: number) => void;
        onPreviewAddToSale?: (recordId: number) => Promise<void>;
        /** Called with the filter tags selected in the preview, if any. */
        onPreviewViewAll?: (preview: IAgentProductPreview, selection?: IAgentProductFilterSelection) => void;
        /**
         * Finds which of the products shown have the selected tags other than prices, as the record
         * identifiers from the request. Without it, only price tags filter.
         */
        onFilterProducts?: (request: IAgentProductFilterRequest) => Promise<ReadonlyArray<number>>;
        /** Adds several Commerce-resolved products or variants to the current sale at once, from a cart plan. */
        onAddProductsToSale?: (recordIds: ReadonlyArray<number>) => Promise<void>;
        /** Formats an amount in the store's currency, for the totals the panel works out itself. */
        formatCurrency?: (amount: number) => string;
    }

    /**
     * Renders the side panel into the given host element.
     * @param element The host element appended to document.body by the POS trigger.
     * @param options The backend, and optional presentation overrides.
     */
    export function mount(element: HTMLElement, options: SideChatMountOptions): void;

    /**
     * Tears down the panel rendered into the given element.
     * @param element The host element previously passed to mount.
     */
    export function unmount(element: HTMLElement): void;

    /**
     * Asks the panel to suggest products that go with the current cart, without the operator typing
     * anything. Returns straight away; suggestions appear in the conversation when the agent answers.
     * @param request The cart to ask about.
     */
    export function requestCartSuggestions(request: ICartSuggestionRequest): void;

    /**
     * Tells the panel about a POS operation that just failed on the associate's screen. Until it is
     * cleared, or for ten minutes, the panel offers help with it and sends it with the requests the
     * associate types.
     * @param error The failure, with diagnostic fields only.
     */
    export function reportPosError(error: IAgentPosErrorContext): void;

    /** Forgets the failure reported last, for example when the operation succeeds on a retry. */
    export function clearPosError(): void;

    /**
     * Reads the failure reported last, while it is recent.
     * @returns The failure, or null when there is none or it is too old to matter.
     */
    export function getPosError(): IAgentPosErrorContext | null;

    /**
     * Opens the panel and asks the agent for help with the failure reported last. The panel must
     * already be mounted.
     * @returns True when there was a recent failure to ask about.
     */
    export function requestPosErrorHelp(): boolean;

    /**
     * Opens or closes the panel.
     * @returns True when the panel is now open.
     */
    export function toggle(): boolean;

    /**
     * Sets the panel open or closed explicitly.
     * @param isOpen True to open the panel.
     */
    export function setOpen(isOpen: boolean): void;

    /**
     * Reads whether the panel is currently open.
     * @returns True when the panel is open.
     */
    export function isOpen(): boolean;

    /**
     * Tells the caller whenever the panel opens or closes, however that happened.
     * @param listener Called with true when the panel opens and false when it closes.
     * @returns A function that stops the notifications.
     */
    export function subscribeToOpenState(listener: (isOpen: boolean) => void): () => void;

    /** A product to display, already resolved by POS. */
    export interface IAgentProductCard {
        recordId: number;
        name: string;
        itemId?: string;
        /** Formatted for display by POS, which owns currency and culture. */
        priceText?: string;
        /** Fully resolved by the view controller against the channel's media base URL. */
        imageUrl?: string;
        description?: string;
        productNumber?: string;
        unitOfMeasure?: string;
        /** Validated variant to add directly instead of prompting for dimensions. */
        selectedVariantId?: number;
        dimensionValues?: ReadonlyArray<string>;
        /** The unformatted price behind `priceText`, which the price filter compares. */
        price?: number;
        /**
         * The colour of the variant shown, when the card shows one. Once POS has built the filter
         * tags, the key of the Color tag it matches.
         */
        variantColor?: string;
        /**
         * The size of the variant shown, when the card shows one. Once POS has built the filter tags,
         * the key of the Size tag it matches.
         */
        variantSize?: string;
    }

    /** Sanitized metadata for one or more Commerce tool calls made while producing a reply. */
    export interface IAgentToolActivity {
        name: string;
        detail?: string;
        count: number;
        status: "completed" | "failed";
    }

    /** What the curated product results need to render. */
    export interface IProductResultsProps {
        products: ReadonlyArray<IAgentProductCard>;
        bestMatchProductId?: number;
        bestMatchReason?: string;
        headline?: string;
        /** The stock the agent reported, at most one entry per product. */
        inventory?: ReadonlyArray<IAgentProductInventory>;
        /** The associate's store's name, which labels its stock. */
        currentStoreName?: string;
        /** Filter tags for the products: Color, Size and Price, then the other refiners Commerce returns. */
        filterFacets?: ReadonlyArray<IAgentProductFacet>;
        /** The tags selected when the results open, such as those selected in the chat. */
        initialFilterSelection?: IAgentProductFilterSelection;
        isLoading?: boolean;
        errorMessage?: string;
        onProductActivated?: (recordId: number) => void;
        onAddToCart?: (recordId: number) => Promise<void>;
        onCompareRequested?: (recordIds: ReadonlyArray<number>) => void;
        /**
         * Finds which of the products have the selected tags other than prices. Without it, only
         * price tags filter.
         */
        onFilterProducts?: (request: IAgentProductFilterRequest) => Promise<ReadonlyArray<number>>;
    }

    /**
     * Renders the agent's curated product results into the given element.
     * @param element The element the POS view controller renders into.
     * @param props The products POS resolved, plus the agent's recommendation.
     */
    export function mountProductResults(element: HTMLElement, props: IProductResultsProps): void;

    /**
     * Tears down product results previously rendered into the given element.
     * @param element The element previously passed to mountProductResults.
     */
    export function unmountProductResults(element: HTMLElement): void;

    /** What the product comparison app needs to render. */
    export interface IProductCompareProps {
        products: ReadonlyArray<IAgentProductCard>;
        bestMatchProductId?: number;
        bestMatchReason?: string;
        onProductActivated?: (recordId: number) => void;
    }

    /**
     * Renders a product comparison into the given element.
     * @param element The element the POS view controller renders into.
     * @param props The products and recommendation to compare.
     */
    export function mountProductCompare(element: HTMLElement, props: IProductCompareProps): void;

    /**
     * Tears down a product comparison previously rendered into the given element.
     * @param element The element previously passed to mountProductCompare.
     */
    export function unmountProductCompare(element: HTMLElement): void;
}
