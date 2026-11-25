/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The contract between POS and the agent.
 *
 * POS publishes the names of the actions it can perform (`supportedActions`) on every request; the
 * agent replies with what to say (`displayMessage`) and what POS should do (`posActions`). The agent
 * instructions describe each action and the arguments it accepts, and the names tell the agent which
 * of those this POS build supports.
 *
 * These types live in the bundle so that both halves share one definition: the bundle renders the
 * results, and the POS extension code (which imports them through the `ContosoSideChat` AMD module)
 * builds the request and executes the actions.
 */

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

/**
 * Which of a customer's saved addresses an order ships to. "Primary" is the customer's primary
 * address. "Work" and "Business" are the same address type.
 */
export type AgentShippingAddressType = "Primary" | "Home" | "Work" | "Business" | "Delivery" | "Invoice" | "Other";

/** One product on the sale that ships, and the store that ships it. */
export interface IAgentShippingItem {
    /** A product on the sale: the identifier `sale` lists for it, or its master product's. */
    productId: number;
    /** The store that ships it, as the store number the inventory tool reported. Defaults to the request's. */
    shipFromStoreNumber?: string;
    /** Display only: how far away that store is, as the inventory tool reported it, for example "195.3 mi". */
    distance?: string;
    /** Display only: the product's available quantity at that store, from the inventory tool. */
    availableQuantity?: number;
}

/**
 * Ships products already on the sale to one of a customer's saved addresses, described in the
 * associate's words. POS finds the customer, the address and the delivery mode itself, so nothing the
 * agent reads or invents about them reaches the order.
 */
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

/**
 * Stock at one store, as the agent read it with the Commerce inventory tools.
 *
 * Display only: POS shows it on the product's card and does not check it. It is what the tools said
 * when the agent answered, so it can be out of date by the time the associate reads it.
 */
export interface IAgentStoreStock {
    /** The store's name as the inventory tool reported it. Only for another store; POS names its own. */
    name?: string;
    /** The available quantity. 0 when the store has none. */
    quantity?: number;
    /** The stock status as the inventory tool reported it, for example "Low stock", when it gave no quantity. */
    status?: string;
    /** How far away the store is, as the inventory tool reported it, with its unit, for example "12.4 mi". */
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
 * One filter the agent reports for a set of recommendations, such as the size the associate asked for.
 *
 * A hint only. POS builds the filter tags itself, from the channel's data for the products shown, and
 * filters those products in POS. An applied Color or Size the products all meet shows as a tag that is
 * already selected and cannot be cleared. Anything else is ignored.
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
    /** Where the store is, when Commerce has its location, so the agent can find the stores closest to it. */
    latitude?: number;
    longitude?: number;
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

/** The values the agent chose for an action. */
export interface IAgentActionDetails {
    /**
     * A product record identifier.
     *
     * Record identifiers exceed 32 bits (for example 68719492943) but stay well inside
     * `Number.MAX_SAFE_INTEGER`, so they survive JSON round-tripping as ordinary numbers.
     */
    productId?: number;
    /**
     * The products the agent curated, as record identifiers only.
     *
     * Identifiers rather than product records on purpose: POS reads every product it displays from
     * the channel itself, so nothing the agent might invent about a name or a price can reach the
     * screen. The agent decides *which* products; POS decides what they actually are. The one thing
     * the agent reports about them is stock, in `inventory`, which POS shows as the agent's report.
     */
    productIds?: number[];
    /** Exact variants selected for products whose requested dimensions were fully resolved. */
    productSelections?: IAgentProductSelection[];
    /** A fully resolved request to create and ship a customer order. */
    customerOrder?: IAgentCustomerOrderRequest;
    /** Ships the products on the sale to a customer's saved address. */
    shipping?: IAgentShippingRequest;
    /** The one product the agent recommends out of `productIds`. Shown first and badged. */
    bestMatchProductId?: number;
    /** Why that product was recommended, in one short sentence. Shown on its card. */
    bestMatchReason?: string;
    /** A short headline for the results, for example "Ski gear for a cold-weather trip". */
    headline?: string;
    /** One short reason per suggested product, saying why it goes with the current cart. */
    reasons?: IAgentProductReason[];
    /**
     * Each recommended product's stock at the associate's store and at the closest other store that
     * has it, as the agent read it with the inventory tools. Display only; POS does not check it.
     */
    inventory?: IAgentProductInventory[];
    /**
     * The filters the recommendations already meet, such as the size the associate asked for. POS
     * uses them only to tell which of its own filter tags are already applied.
     */
    filters?: IAgentProductFilter[];
    /** A cart planned from what the customer is shopping for, for the associate to review and add. */
    cartPlan?: IAgentCartPlan;
}

/** One action the agent wants POS to run. */
export interface IAgentPosAction {
    action: string;
    details?: IAgentActionDetails;
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

/** Whether POS could reach Commerce when an operation failed. */
export type AgentPosConnectivity = "Online" | "Offline";

/**
 * A POS operation that failed on the associate's screen, sent with the requests the associate types
 * while the failure is recent so the agent can look it up in the IT support guide. Diagnostic fields
 * only: never payment data, tokens or customer contact details.
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

/** What POS sends up on every request. */
export interface IAgentRequestEnvelope {
    text: string;
    conversationId: string;
    cartId: string;
    currentView: string;
    /** Names of the actions this POS build can perform. The agent instructions define each one. */
    supportedActions: string[];
    /**
     * Present only on turns POS started on its own. Names the POS event that started the turn; the
     * operator did not type anything.
     */
    trigger?: "cartItemAdded";
    /** Present only on automatic cart checks: the cart the agent is asked about. */
    cart?: IAgentCartSnapshot;
    /**
     * The associate's store, so the agent can check stock there and find the stores closest to it.
     * Sent with the requests the associate types, when POS can read it.
     */
    store?: IAgentStoreContext;
    /**
     * Present only when the associate attached files to the message: their names and types, in the
     * order attached. The files themselves travel beside the envelope, and the gateway gives them to
     * the agent as images and documents it can read.
     */
    attachments?: IAgentAttachmentInfo[];
    /**
     * The products on the current sale, so the agent can act on them, for example to ship them. Sent
     * with the requests the associate types, when the sale has any.
     */
    sale?: IAgentSaleSnapshot;
    /**
     * A POS operation that failed on the associate's screen in the last few minutes. Sent with the
     * requests the associate types, so the agent can help with it.
     */
    posError?: IAgentPosErrorContext;
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

/** A product display model already resolved from the Commerce channel by POS. */
export interface IAgentProductCard {
    recordId: number;
    name: string;
    itemId?: string;
    /** Formatted for display by POS, which owns currency and culture. */
    priceText?: string;
    /** Fully resolved by POS against the channel's media base URL. */
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
     * The colour of the variant shown, when the card shows one. Empty for a master product. Once POS
     * has built the filter tags, the key of the Color tag it matches.
     */
    variantColor?: string;
    /**
     * The size of the variant shown, when the card shows one. Empty for a master product. Once POS
     * has built the filter tags, the key of the Size tag it matches.
     */
    variantSize?: string;
}

/**
 * What a filter tag row filters on: the colour or size of a product's variants, its price, its
 * customer rating, its category, or another attribute or dimension Commerce returned as a refiner.
 */
export type AgentProductFacetKind = "color" | "size" | "price" | "rating" | "category" | "attribute";

/** One filter tag, such as a colour, a size, a price range, a rating or a category. */
export interface IAgentProductFacetValue {
    /** Identifies the value within its facet. Stable across renders. */
    key: string;
    /** The text on the tag, for example "Black", "M", "Under $50" or "4 stars and up". */
    label: string;
    /** The colour of a colour tag's swatch, as a CSS colour, when Commerce has one. */
    swatchColor?: string;
    /** The lowest price a price tag includes. */
    minPrice?: number;
    /** The price a price tag stops below. */
    maxPrice?: number;
    /**
     * The Commerce refiner value behind any tag but a price range. POS sends it back to Commerce to
     * find the products that have the value. Opaque to the panel.
     */
    refinerValue?: unknown;
}

/**
 * One row of filter tags on a set of recommendations, built by POS from the refiners Commerce returns
 * for the products shown, and from their prices. Selecting tags narrows those products in POS; the
 * agent is not asked again.
 */
export interface IAgentProductFacet {
    /**
     * Identifies the row among the rows shown: "color", "size" and "price" for those rows, and one
     * per refiner for the others. The selection is keyed by it.
     */
    key: string;
    kind: AgentProductFacetKind;
    /** The row's label, for example "Color", "Rating" or "Category". */
    label: string;
    /** The tags, in the order Commerce lists them. Only the locked tag when `lockedKey` is set. */
    values: ReadonlyArray<IAgentProductFacetValue>;
    /**
     * The value every product shown already has, such as the size the associate asked for. Its tag
     * shows as selected and cannot be cleared.
     */
    lockedKey?: string;
    /** True when one tag at a time can be selected in the row, as Commerce marks single-select refiners and ranges. */
    singleSelect?: boolean;
    /**
     * True for a product dimension other than Color and Size, such as Style, whose value is a variant's.
     * Its locked tag is sent to Commerce with the tags selected, as Color's and Size's are.
     */
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

/** Sanitized metadata for one or more Commerce tool calls made while producing a reply. */
export interface IAgentToolActivity {
    name: string;
    detail?: string;
    count: number;
    status: "completed" | "failed";
}

/** How an action POS attempted to run turned out. */
export type ActionOutcome = "ran" | "failed" | "unsupported";

/** How POS runs a batch of the agent's actions. */
export interface IAgentActionExecutionOptions {
    /**
     * True for a turn POS started on its own, such as an automatic cart check. POS then only shows
     * suggested products in the panel. It never navigates or changes the transaction, and it ignores
     * every other action.
     */
    automatic?: boolean;
    /**
     * Products already in the cart, including the masters of variants in it. POS leaves them out of
     * suggestions, whatever the agent returned.
     */
    excludedProductIds?: ReadonlyArray<number>;
}

/**
 * What an inline product preview shows: products the agent recommended in answer to the operator,
 * or products it suggested to go with the current cart.
 */
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
     * Filter tags for recommendations, built by POS for the products shown: Color, Size and Price,
     * then the other refiners Commerce returns, such as Rating and Category. Never set for cart
     * suggestions.
     */
    filterFacets?: ReadonlyArray<IAgentProductFacet>;
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

/**
 * A record of one action POS attempted, shown under the reply in the panel.
 *
 * Surfaced rather than logged only, so that an agent asking for the wrong thing is immediately
 * visible instead of looking like the panel silently did nothing.
 */
export interface IActionReceipt {
    /** The action name the agent asked for. */
    action: string;
    /** A short human readable summary, for example: Opened Search results for "Jacket". */
    summary: string;
    outcome: ActionOutcome;
    /** Present when POS resolved recommended products that the panel can preview. */
    productPreview?: IAgentProductPreview;
    /** Present when POS successfully concluded a customer order. */
    customerOrderReceipt?: IAgentCustomerOrderReceipt;
    /** Present when POS set the sale to ship. */
    shippingReceipt?: IAgentShippingReceipt;
    /** Present when POS resolved a cart plan the associate can review and add to the sale. */
    cartPlan?: IAgentCartPlanReceipt;
}
