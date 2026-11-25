/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The catalogue of actions POS advertises, and the code that carries each one out.
 *
 * Both come from the same table on purpose. `supportedActions` is what the agent is told POS can do,
 * and the executor is what POS actually does; declaring them separately is how the two drift apart
 * and the agent starts asking for things that silently never happen.
 *
 * Only the action names travel with each request, which keeps the request inside the assistant
 * gateway's message limit. The agent instructions carry each entry's description, view name and
 * parameter schema verbatim, so update the instructions whenever an entry is added or changed.
 *
 * Actions are named for the intent, not for the screen. `navigateToProductDetails` rather than
 * `navigate` + `viewName: "SimpleProductDetailsView"`: view names are a POS implementation detail, and
 * asking the agent to pick one turns the catalogue into a sitemap instead of a list of capabilities.
 * It also keeps every advertised action's parameter schema unambiguous, which a single polymorphic
 * `navigate` action cannot do.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities } from "PosApi/Entities";
import {
    IAgentCartPlanReceipt,
    IAgentCustomerOrderReceipt,
    IAgentCustomerOrderRequest,
    IAgentPosAction,
    IAgentShippingReceipt
} from "ContosoSideChat";
import { createCustomerOrderAsync, ICustomerOrderExecutionResult } from "./CustomerOrderHelper";
import { IShipCartExecutionResult, shipCartAsync } from "./ShipCartHelper";
import { buildCartPlanAsync, ICartPlanExecutionResult } from "./CartPlanHelper";
import { retryCustomerOrderLookupAsync } from "./CustomerOrderLookup";

/** Opens the POS product details page for one product. */
export const PRODUCT_DETAILS_ACTION: string = "navigateToProductDetails";

/** Shows the products the agent curated, as product cards in the side panel. */
export const PRODUCT_RECOMMENDATIONS_ACTION: string = "showProductRecommendations";

/** Shows products that go with the current cart, as product cards in the side panel. */
export const CART_SUGGESTIONS_ACTION: string = "showCartSuggestions";

/** Opens the POS cart so the operator can see the current transaction. */
export const SHOW_CART_ACTION: string = "showCart";

/** Creates one shipped customer order from Commerce-grounded identifiers. */
export const CREATE_CUSTOMER_ORDER_ACTION: string = "createCustomerOrder";

/** Sets the products already on the sale to ship to one of a customer's saved addresses. */
export const SHIP_CART_ACTION: string = "shipCart";

/** Shows a cart the agent planned from what the customer is shopping for, as a checklist in the side panel. */
export const BUILD_CART_FROM_INTENT_ACTION: string = "buildCartFromIntent";

/** Retries the customer order lookup that just failed, once, as the IT support guide allows. */
export const RETRY_ORDER_LOOKUP_ACTION: string = "retryOrderLookup";

/**
 * Returns the item list read from a photo, for the Counter order view. Not in the catalogue: see
 * READ_ITEM_LIST_CONTRACT.
 */
export const READ_ITEM_LIST_ACTION: string = "readItemList";

/**
 * The out-of-box views these actions reach. Declared as literals rather than `string` because
 * `navigateToPOSView` is typed on the view name.
 */
const PRODUCT_DETAILS_VIEW = "SimpleProductDetailsView" as const;
const CART_VIEW = "CartView" as const;

/**
 * One entry in the catalogue: what POS tells the agent it can do, and how POS does it.
 */
export interface IPosActionDefinition {
    /** The action name, unique across the catalogue. */
    readonly name: string;

    /** What the agent is told this action does. */
    readonly description: string;

    /** The POS views this action reaches. Advisory only; the name is the contract. */
    readonly viewNames?: string[];

    /**
     * JSON Schema for the arguments the agent may supply.
     *
     * Real JSON Schema rather than a hand-rolled parameter list: `required` and `enum` are what stop
     * a model inventing arguments, and this is the shape every tool-calling API already accepts. The
     * agent instructions contain this schema verbatim.
     */
    readonly parametersSchema: Record<string, unknown>;

    /**
     * Answers whether this entry handles the action the agent chose.
     * @param action The action the agent returned.
     * @returns True when this entry can carry it out.
     */
    matches(action: IAgentPosAction): boolean;

    /**
     * Carries the action out.
     * @param action The action the agent returned.
     * @param context The POS extension context.
     * @returns A short human readable summary of what was done, for the panel.
     */
    run(action: IAgentPosAction, context: IExtensionContext): Promise<string | IPosActionRunResult>;
}

/** Additional structured result data returned by an executed POS action. */
export interface IPosActionRunResult {
    summary: string;
    customerOrderReceipt?: IAgentCustomerOrderReceipt;
    shippingReceipt?: IAgentShippingReceipt;
    cartPlan?: IAgentCartPlanReceipt;
}

/**
 * Opens the POS product details page for one product the agent picked.
 *
 * This is where a curated recommendation actually lands: the agent resolves a real product, and POS
 * opens the out-of-box details page for that record identifier. POS re-reads the product from the
 * channel, so nothing the agent says about price or availability can reach the screen — only the
 * identifier crosses the wire.
 */
const navigateToProductDetails: IPosActionDefinition = {
    name: PRODUCT_DETAILS_ACTION,
    description: "Open the POS product details page for one specific product. Use this when a single "
        + "product is the answer, for example a recommendation. Supply the product's record "
        + "identifier; POS reads the product from the channel itself.",
    viewNames: [PRODUCT_DETAILS_VIEW],

    parametersSchema: {
        type: "object",
        properties: {
            productId: {
                type: "integer",
                exclusiveMinimum: 0,
                description: "The product record identifier, for example 68719492943. Must be a real "
                    + "record identifier from the product catalog; never invent one."
            }
        },
        required: ["productId"],
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, PRODUCT_DETAILS_ACTION);
    },

    run(action: IAgentPosAction, context: IExtensionContext): Promise<string> {
        const productId: number | undefined = action.details?.productId;

        // The product details view model rejects a null, NaN or zero identifier by throwing, so the
        // value is checked here where the failure can be turned into a readable receipt instead.
        if (typeof productId !== "number" || !isFinite(productId) || productId <= 0) {
            return Promise.reject(new Error("The product details action did not include a valid product identifier."));
        }

        const parameters: ClientEntities.SimpleProductDetailsNavigationParameters =
            new ClientEntities.SimpleProductDetailsNavigationParameters(productId);

        context.navigator.navigateToPOSView(PRODUCT_DETAILS_VIEW, parameters);

        // Navigation is synchronous and does not wait for the product to load, so this reports the
        // request rather than claiming the product was found.
        return Promise.resolve(`Opened product details for product ${productId}.`);
    }
};

/**
 * Exact variants the agent resolved, shared by every action that shows product cards.
 */
const PRODUCT_SELECTIONS_SCHEMA: Record<string, unknown> = {
    type: "array",
    description: "Exact variants selected when the operator specified every required "
        + "dimension, such as color and size. Include an entry only after resolving the "
        + "variant through product details. POS validates it before enabling direct sale.",
    items: {
        type: "object",
        properties: {
            productId: {
                type: "integer",
                exclusiveMinimum: 0,
                description: "The master product record identifier from productIds."
            },
            variantProductId: {
                type: "integer",
                exclusiveMinimum: 0,
                description: "The exact variant record identifier returned by the product tool."
            },
            dimensions: {
                type: "array",
                minItems: 1,
                items: {
                    type: "object",
                    properties: {
                        name: { type: "string" },
                        value: { type: "string" }
                    },
                    required: ["name", "value"],
                    additionalProperties: false
                }
            }
        },
        required: ["productId", "variantProductId", "dimensions"],
        additionalProperties: false
    }
};

/**
 * Stock the agent read with the Commerce inventory tools, shown on the recommended products' cards.
 *
 * Display only. POS does not check these figures, which is why they are labelled on screen as what
 * the agent found when it answered. POS names the associate's own store itself.
 */
const STOCK_QUANTITY_SCHEMA: Record<string, unknown> = {
    type: "number",
    minimum: 0,
    description: "The available quantity the inventory tool reported. 0 when the store has none."
};

const STOCK_STATUS_SCHEMA: Record<string, unknown> = {
    type: "string",
    minLength: 1,
    maxLength: 40,
    description: "The stock status the inventory tool reported, only when it reported no quantity."
};

const PRODUCT_INVENTORY_SCHEMA: Record<string, unknown> = {
    type: "array",
    maxItems: 20,
    description: "Display only: stock for the products shown, at the associate's store and at the "
        + "closest other store that has them, exactly as check_product_availability and "
        + "check_product_availability_in_area reported it. At most one entry per product, and only "
        + "for products whose stock was checked. POS names its own store and does not check these "
        + "figures.",
    items: {
        type: "object",
        properties: {
            productId: {
                type: "integer",
                exclusiveMinimum: 0,
                description: "The product this stock is for, from productIds."
            },
            currentStore: {
                type: "object",
                description: "Stock at the associate's store, the store in the request.",
                properties: {
                    quantity: STOCK_QUANTITY_SCHEMA,
                    status: STOCK_STATUS_SCHEMA
                },
                additionalProperties: false
            },
            nearestStore: {
                type: "object",
                description: "The closest store, other than the associate's, that has the product in stock.",
                properties: {
                    name: {
                        type: "string",
                        minLength: 1,
                        maxLength: 60,
                        description: "The store's name as the inventory tool reported it, or its number."
                    },
                    quantity: STOCK_QUANTITY_SCHEMA,
                    status: STOCK_STATUS_SCHEMA,
                    distance: {
                        type: "string",
                        minLength: 1,
                        maxLength: 20,
                        description: "How far away the store is, with the unit the tool used, for example \"12.4 mi\"."
                    }
                },
                required: ["name"],
                additionalProperties: false
            }
        },
        required: ["productId"],
        additionalProperties: false
    }
};

/**
 * The filters a set of recommendations already meets, such as the size the associate asked for.
 *
 * Hints only. POS builds the filter tags itself, from the refiners Commerce returns for the products
 * shown and from their prices, and narrows those products in POS without asking the agent again. An
 * applied value the products all have, such as a Color, Size, Category or Brand, shows as a tag that
 * is selected and cannot be cleared; anything else is ignored. The limits match what ProductFilters reads.
 */
const PRODUCT_FILTERS_SCHEMA: Record<string, unknown> = {
    type: "array",
    maxItems: 8,
    description: "The filters every product shown already meets, from the associate's request, for "
        + "example Size M when they asked for medium shirts. POS builds the filter tags itself from the "
        + "products' data and filters the products without asking you, so report only filters that are "
        + "applied, with applied set to true; others are ignored. Take values only from search_products "
        + "refiners, get_product_by_id variants, or what the associate asked for.",
    items: {
        type: "object",
        properties: {
            name: {
                type: "string",
                minLength: 1,
                maxLength: 40,
                description: "What the filter is on, for example \"Size\", \"Color\" or \"Price\"."
            },
            value: {
                type: "string",
                minLength: 1,
                maxLength: 40,
                description: "The value, for example \"M\", \"Black\" or \"Under $300\"."
            },
            label: {
                type: "string",
                minLength: 1,
                maxLength: 40,
                description: "How the filter reads, only when it differs from value, for example "
                    + "\"Size M\"."
            },
            applied: {
                type: "boolean",
                description: "True when every product shown already meets this filter. POS ignores "
                    + "filters without it."
            }
        },
        required: ["name", "value"],
        additionalProperties: false
    }
};

/**
 * Shows the products the agent curated, as product cards in the side panel.
 *
 * This is the action that lets the agent's actual choice reach the screen. The out-of-box search view
 * cannot be given a list of products by an extension — its navigation contract carries a search term
 * and nothing else — so a curated set is rendered as cards in the conversation instead, and in an
 * extension view when the associate chooses View all.
 *
 * Only record identifiers are accepted. POS reads every product from the channel itself, so the agent
 * decides *which* products to show and POS decides what they are. The agent also reports the
 * products' stock, which the cards show as the agent's report, and the filters the products already
 * meet. POS builds the filter tags and filters the products itself.
 */
const showProductRecommendations: IPosActionDefinition = {
    name: PRODUCT_RECOMMENDATIONS_ACTION,
    description: "Show a curated set of products as product cards in the side panel, optionally "
        + "highlighting one as the best match with a short reason, optionally with each product's stock "
        + "at this store and at the closest other store, and optionally with the filters every product "
        + "already meets, such as the size the associate asked for. POS adds filter tags itself, from "
        + "Commerce's refiners and the products' prices, and filters the products without asking you again. The current screen stays "
        + "open; the associate can open the products in a full view from the cards. Use this when "
        + "specific products have been identified and the operator should see them side by side. Supply "
        + "real product record identifiers; POS reads the products from the channel itself.",

    parametersSchema: {
        type: "object",
        properties: {
            productIds: {
                type: "array",
                items: { type: "integer", exclusiveMinimum: 0 },
                minItems: 1,
                maxItems: 20,
                description: "The product record identifiers to show, in the order they should appear. "
                    + "Use master product identifiers for display. Must be real identifiers from the "
                    + "product catalog; never invent one."
            },
            productSelections: PRODUCT_SELECTIONS_SCHEMA,
            bestMatchProductId: {
                type: "integer",
                exclusiveMinimum: 0,
                description: "The one product to recommend. Must also appear in productIds. It is "
                    + "shown first and badged."
            },
            bestMatchReason: {
                type: "string",
                description: "One short sentence explaining the recommendation, for example "
                    + "\"Warmest of the three and the only one rated for technical use\"."
            },
            headline: {
                type: "string",
                description: "A short headline for the results, for example \"Ski gear for a cold trip\"."
            },
            inventory: PRODUCT_INVENTORY_SCHEMA,
            filters: PRODUCT_FILTERS_SCHEMA
        },
        required: ["productIds"],
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, PRODUCT_RECOMMENDATIONS_ACTION);
    },

    run(action: IAgentPosAction, context: IExtensionContext): Promise<string> {
        void context;

        const productIds: number[] = (action.details?.productIds ?? []).filter(
            (id: number) => typeof id === "number" && isFinite(id) && id > 0);

        if (productIds.length === 0) {
            return Promise.reject(new Error("The product recommendations action did not include any product identifiers."));
        }

        // The cards are the whole effect, and the executor renders them from the same identifiers.
        // The results view opens only when the associate chooses View all, so the screen they are
        // working on stays put.
        return Promise.resolve(`Showed ${describeProductCount(productIds.length)} chosen for you.`);
    }
};

/**
 * Shows products that go with what is already in the cart, as product cards in the side panel.
 *
 * The answer to an automatic cart check: POS asks after an item is added to the cart, without the
 * operator typing anything. So this action only puts cards in the conversation. It never navigates,
 * because the operator is in the middle of a sale, and it never changes the transaction: each card
 * has its own Add to sale button, and adding is the operator's call.
 */
const showCartSuggestions: IPosActionDefinition = {
    name: CART_SUGGESTIONS_ACTION,
    description: "Show products that go well with what is already in the cart, as product cards in the "
        + "side panel, each with a short reason. Use this to answer an automatic cart check (trigger "
        + "\"cartItemAdded\"). The current screen stays open and the cart is not changed; the operator "
        + "decides whether to add a product. Supply real product record identifiers; POS reads the "
        + "products from the channel itself.",

    parametersSchema: {
        type: "object",
        properties: {
            productIds: {
                type: "array",
                items: { type: "integer", exclusiveMinimum: 0 },
                minItems: 1,
                maxItems: 3,
                description: "Up to three product record identifiers, best first. Use master product "
                    + "identifiers for display. Never a product that is already in the cart. Must be real "
                    + "identifiers returned by a Commerce tool; never invent one."
            },
            productSelections: PRODUCT_SELECTIONS_SCHEMA,
            reasons: {
                type: "array",
                maxItems: 3,
                description: "One short reason for each product, saying why it goes with the cart.",
                items: {
                    type: "object",
                    properties: {
                        productId: {
                            type: "integer",
                            exclusiveMinimum: 0,
                            description: "A product record identifier from productIds."
                        },
                        reason: {
                            type: "string",
                            minLength: 1,
                            maxLength: 160,
                            description: "One short sentence, for example \"Completes the look with the "
                                + "jacket in the cart\" or \"20% off when bought with the helmet in the cart\"."
                        }
                    },
                    required: ["productId", "reason"],
                    additionalProperties: false
                }
            },
            headline: {
                type: "string",
                description: "A short headline for the suggestions, for example \"Goes well with your helmet\"."
            }
        },
        required: ["productIds"],
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, CART_SUGGESTIONS_ACTION);
    },

    run(action: IAgentPosAction, context: IExtensionContext): Promise<string> {
        void context;

        const productIds: number[] = (action.details?.productIds ?? []).filter(
            (id: number) => typeof id === "number" && isFinite(id) && id > 0);

        if (productIds.length === 0) {
            return Promise.reject(new Error("The cart suggestions action did not include any product identifiers."));
        }

        // The cards are the whole effect, and the executor renders them from the same identifiers.
        return Promise.resolve(`Suggested ${describeProductCount(productIds.length)} to go with the cart.`);
    }
};

/**
 * Opens the POS cart so the operator can see the current transaction.
 *
 * The agent uses this after it has changed the transaction elsewhere -- through commerce tools on the
 * server -- so that POS shows the operator the result. POS is only being told to look, not what to
 * believe: the cart view reads the transaction itself, so whatever the agent says it did is measured
 * against what the cart actually holds by the time the operator sees it.
 */
const showCart: IPosActionDefinition = {
    name: SHOW_CART_ACTION,
    description: "Open the POS cart to show the current transaction. Use this after changing the cart "
        + "so the operator can see the result, or when the operator asks what is in the cart.",
    viewNames: [CART_VIEW],

    parametersSchema: {
        type: "object",
        properties: {},
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, SHOW_CART_ACTION);
    },

    run(action: IAgentPosAction, context: IExtensionContext): Promise<string> {
        void action;

        context.navigator.navigateToPOSView(CART_VIEW, new ClientEntities.CartViewNavigationParameters());

        // Deliberately reports only what POS did. The agent may say it added items; POS did not add
        // them and cannot vouch for them, so the receipt does not repeat the claim.
        return Promise.resolve("Opened the cart.");
    }
};

/**
 * Creates and, when no payment remains due, submits a shipped customer order.
 */
const createCustomerOrder: IPosActionDefinition = {
    name: CREATE_CUSTOMER_ORDER_ACTION,
    description: "Create one shipped customer order for a resolved customer and exact product variant. "
        + "Use only after Commerce tools resolve the customer account, saved address, variant, source "
        + "store, delivery mode, and requested ship date. POS validates the identifiers and returns "
        + "the real order number after checkout.",
    viewNames: [CART_VIEW],

    parametersSchema: {
        type: "object",
        properties: {
            customerOrder: {
                type: "object",
                properties: {
                    customerAccountNumber: {
                        type: "string",
                        minLength: 1,
                        description: "The exact Commerce customer account number returned by a customer tool."
                    },
                    productId: {
                        type: "integer",
                        exclusiveMinimum: 0,
                        description: "The master product record identifier."
                    },
                    variantProductId: {
                        type: "integer",
                        exclusiveMinimum: 0,
                        description: "The exact sellable variant record identifier."
                    },
                    dimensions: {
                        type: "array",
                        minItems: 1,
                        items: {
                            type: "object",
                            properties: {
                                name: { type: "string", minLength: 1 },
                                value: { type: "string", minLength: 1 }
                            },
                            required: ["name", "value"],
                            additionalProperties: false
                        }
                    },
                    quantity: {
                        type: "number",
                        exclusiveMinimum: 0
                    },
                    shippingAddressRecordId: {
                        type: "integer",
                        exclusiveMinimum: 0,
                        description: "Record identifier of an address saved on the resolved customer."
                    },
                    fulfillmentStoreId: {
                        type: "string",
                        minLength: 1,
                        description: "Organization unit number of the validated source store."
                    },
                    warehouseId: {
                        type: "string",
                        description: "Optional inventory warehouse identifier for the source store."
                    },
                    deliveryModeCode: {
                        type: "string",
                        minLength: 1,
                        description: "Validated delivery mode code, such as the code for Standard shipping."
                    },
                    requestedShipDate: {
                        type: "string",
                        minLength: 10,
                        description: "Validated requested ship date in ISO 8601 format."
                    },
                    sourceStoreName: {
                        type: "string",
                        description: "Optional source-store display name from Commerce."
                    },
                    deliveryModeName: {
                        type: "string",
                        description: "Optional delivery-mode display name from Commerce."
                    },
                    sourceStoreAvailableQuantity: {
                        type: "number",
                        minimum: 0,
                        description: "Optional, display only. The exact variant's available quantity at the source "
                            + "store, as reported by the inventory tool."
                    },
                    sourceStoreDistance: {
                        type: "string",
                        description: "Optional, display only. The distance to the source store exactly as the "
                            + "inventory tool reports it, including the unit, for example \"1.8 mi\"."
                    },
                    currentStoreAvailableQuantity: {
                        type: "number",
                        minimum: 0,
                        description: "Optional, display only. The exact variant's available quantity at the current "
                            + "store, as reported by the inventory tool; 0 when it is out of stock."
                    }
                },
                required: [
                    "customerAccountNumber",
                    "productId",
                    "variantProductId",
                    "dimensions",
                    "quantity",
                    "shippingAddressRecordId",
                    "fulfillmentStoreId",
                    "deliveryModeCode",
                    "requestedShipDate"
                ],
                additionalProperties: false
            }
        },
        required: ["customerOrder"],
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, CREATE_CUSTOMER_ORDER_ACTION);
    },

    async run(action: IAgentPosAction, context: IExtensionContext): Promise<IPosActionRunResult> {
        const request: IAgentCustomerOrderRequest | undefined = action.details?.customerOrder;
        if (!request) {
            throw new Error("The customer-order action did not include its order details.");
        }

        const result: ICustomerOrderExecutionResult = await createCustomerOrderAsync(request, context);
        return {
            summary: result.summary,
            customerOrderReceipt: result.receipt
        };
    }
};

/**
 * Sets the products already on the sale to ship, from the associate's words.
 *
 * The agent passes on who, which address, how and when as the associate said them, and which store
 * has the stock. POS finds the customer, the saved address and the delivery mode itself, with the POS
 * API and out-of-box Commerce operations, so nothing the agent reads or invents about them reaches the
 * order. The sale is left as a customer order, ready for the associate to take payment.
 */
const shipCart: IPosActionDefinition = {
    name: SHIP_CART_ACTION,
    description: "Set the products already on the sale to ship to one of a customer's saved addresses, for "
        + "example when the associate says \"ship to Karen Berg's home address, standard shipping, 2 day "
        + "delivery\". Pass on the associate's words: POS finds the customer, the saved address and the "
        + "delivery mode itself, makes the sale a customer order, and leaves it ready for checkout. Name "
        + "the store that ships each product when the inventory tools show the associate's store can't.",
    viewNames: [CART_VIEW],

    parametersSchema: {
        type: "object",
        properties: {
            shipping: {
                type: "object",
                properties: {
                    customerName: {
                        type: "string",
                        minLength: 1,
                        description: "The customer's name as the associate said it, for example \"Karen Berg\". "
                            + "Omit when the associate named no one; POS then uses the customer on the sale."
                    },
                    addressType: {
                        type: "string",
                        enum: ["Primary", "Home", "Work", "Business", "Delivery", "Invoice", "Other"],
                        description: "Which of the customer's saved addresses to ship to. Omit for the primary address."
                    },
                    deliveryMode: {
                        type: "string",
                        minLength: 1,
                        description: "The delivery mode in the associate's words, without the date, for example "
                            + "\"Standard shipping\". POS matches it to the store's delivery modes."
                    },
                    deliveryInDays: {
                        type: "integer",
                        minimum: 0,
                        maximum: 365,
                        description: "For a date relative to today, such as \"in 2 days\" or \"2 day delivery\": the "
                            + "number of days. POS works out the date. Give this or deliveryDate."
                    },
                    deliveryDate: {
                        type: "string",
                        pattern: "^\\d{4}-\\d{2}-\\d{2}$",
                        description: "For an exact date the associate gave: YYYY-MM-DD. Ignored when deliveryInDays is set."
                    },
                    shipFromStoreNumber: {
                        type: "string",
                        minLength: 1,
                        description: "The store number that ships every product without its own, as the inventory "
                            + "tool reported it. Omit to ship from the associate's store."
                    },
                    items: {
                        type: "array",
                        minItems: 1,
                        description: "The products that ship. Omit to ship every product on the sale.",
                        items: {
                            type: "object",
                            properties: {
                                productId: {
                                    type: "integer",
                                    exclusiveMinimum: 0,
                                    description: "A productId from sale.lines."
                                },
                                shipFromStoreNumber: {
                                    type: "string",
                                    minLength: 1,
                                    description: "The store number that ships this product, as the inventory tool reported it."
                                },
                                distance: {
                                    type: "string",
                                    description: "Optional, display only. The distance to that store exactly as the "
                                        + "inventory tool reports it, including the unit, for example \"195.3 mi\"."
                                },
                                availableQuantity: {
                                    type: "number",
                                    minimum: 0,
                                    description: "Optional, display only. The product's available quantity at that store, "
                                        + "as reported by the inventory tool."
                                }
                            },
                            required: ["productId"],
                            additionalProperties: false
                        }
                    }
                },
                required: ["deliveryMode"],
                additionalProperties: false
            }
        },
        required: ["shipping"],
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, SHIP_CART_ACTION);
    },

    async run(action: IAgentPosAction, context: IExtensionContext): Promise<IPosActionRunResult> {
        const result: IShipCartExecutionResult = await shipCartAsync(action.details?.shipping, context);
        return {
            summary: result.summary,
            shippingReceipt: result.receipt
        };
    }
};

/**
 * Shows a cart the agent planned from what the customer is shopping for, such as a beach vacation, as
 * a checklist in the side panel.
 *
 * Only record identifiers, needs and reasons cross the wire. POS reads each product from the channel,
 * keeps one product per need, and checks the channel's prices against a budget for each item. Nothing
 * is added to the sale until the associate chooses: every product starts selected, and the associate
 * can unselect any, add one at a time, or add the selection in one step.
 */
const buildCartFromIntent: IPosActionDefinition = {
    name: BUILD_CART_FROM_INTENT_ACTION,
    description: "Plan a cart from what the customer is shopping for, for example \"I'm going on a beach "
        + "vacation, build me a cart with items under $100\". POS shows three to eight products in the side "
        + "panel as a checklist, each covering a different need with a short reason, under a summary of how "
        + "they were chosen. Every product starts selected; the associate can unselect any, add products one "
        + "at a time, or add the selection to the sale in one step. The current screen stays open and nothing "
        + "is added until the associate chooses. Supply real product record identifiers from the Commerce "
        + "search tools; POS reads the products from the channel itself and leaves out repeats, including "
        + "other variants of a product already in the plan.",

    parametersSchema: {
        type: "object",
        properties: {
            cartPlan: {
                type: "object",
                properties: {
                    intent: {
                        type: "string",
                        minLength: 1,
                        maxLength: 80,
                        description: "What the customer is shopping for, in a few words, for example \"Beach vacation\"."
                    },
                    headline: {
                        type: "string",
                        maxLength: 90,
                        description: "A short headline, for example \"Beach vacation essentials under $100\"."
                    },
                    summary: {
                        type: "string",
                        minLength: 1,
                        maxLength: 400,
                        description: "One or two sentences on how the products were chosen, for example \"One "
                            + "product for each beach-day need: sun, water, shade and carrying it all, each under "
                            + "$100.\" Shown as the plan's insights."
                    },
                    budget: {
                        type: "object",
                        properties: {
                            amount: {
                                type: "number",
                                exclusiveMinimum: 0,
                                description: "The spending limit the associate gave, in the store's currency."
                            },
                            currency: {
                                type: "string",
                                pattern: "^[A-Z]{3}$",
                                description: "Optional. The ISO currency code, when the associate said one."
                            },
                            appliesTo: {
                                type: "string",
                                enum: ["eachItem", "total"],
                                description: "\"eachItem\" (the default) when every product must cost no more than "
                                    + "the amount, as in \"items under $100\"; \"total\" when the whole cart must, as "
                                    + "in \"$100 in total\"."
                            }
                        },
                        required: ["amount"],
                        additionalProperties: false
                    },
                    items: {
                        type: "array",
                        minItems: 1,
                        maxItems: 8,
                        description: "Three to eight products, best first, each covering a different need. Never "
                            + "two products of the same kind, and never two variants of one product.",
                        items: {
                            type: "object",
                            properties: {
                                productId: {
                                    type: "integer",
                                    exclusiveMinimum: 0,
                                    description: "A master product record identifier returned by a Commerce tool. "
                                        + "Never invent one."
                                },
                                need: {
                                    type: "string",
                                    minLength: 1,
                                    maxLength: 40,
                                    description: "The need it covers, in a few words, for example \"Sun protection\". "
                                        + "Different for every product."
                                },
                                reason: {
                                    type: "string",
                                    minLength: 1,
                                    maxLength: 160,
                                    description: "Why it was picked, in one short sentence, for example \"SPF 50 and "
                                        + "water resistant for long days in the sea\"."
                                }
                            },
                            required: ["productId", "need", "reason"],
                            additionalProperties: false
                        }
                    }
                },
                required: ["intent", "summary", "items"],
                additionalProperties: false
            },
            productSelections: PRODUCT_SELECTIONS_SCHEMA
        },
        required: ["cartPlan"],
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, BUILD_CART_FROM_INTENT_ACTION);
    },

    async run(action: IAgentPosAction, context: IExtensionContext): Promise<IPosActionRunResult> {
        const result: ICartPlanExecutionResult =
            await buildCartPlanAsync(action.details?.cartPlan, action.details?.productSelections, context);
        return {
            summary: result.summary,
            cartPlan: result.receipt
        };
    }
};

/**
 * Retries the customer order lookup that just failed, as the IT support guide (AW-POS-IT-014) allows:
 * once, and only while POS is online. POS enforces both itself, so a second retry never reaches
 * Commerce whatever the agent asks.
 */
const retryOrderLookup: IPosActionDefinition = {
    name: RETRY_ORDER_LOOKUP_ACTION,
    description: "Retry the customer order lookup that just failed with CUSTOMER_ORDER_LOOKUP_FAILED, the "
        + "same order number again. Use only after the associate agrees to the one retry the IT support guide "
        + "allows: when posError has that code, connectivity \"Online\" and retryCount 0. POS refuses a second "
        + "retry and any retry while offline, and reports whether the retry found the order or failed again.",

    parametersSchema: {
        type: "object",
        properties: {},
        additionalProperties: false
    },

    matches(action: IAgentPosAction): boolean {
        return isSameName(action.action, RETRY_ORDER_LOOKUP_ACTION);
    },

    run(action: IAgentPosAction, context: IExtensionContext): Promise<string> {
        void action;

        return retryCustomerOrderLookupAsync(context);
    }
};

/**
 * What the agent is told about `readItemList`: the item list it reads from a photo for the Counter order
 * view's Bulk add items dialog.
 *
 * Not in POS_ACTION_CATALOGUE, so the side panel neither advertises nor runs it. The Counter order view
 * advertises it on its own requests and reads the list from the reply itself (see ItemListPhoto.ts). The
 * agent instructions carry its description and schema verbatim, like the catalogue's.
 */
export const READ_ITEM_LIST_CONTRACT: Readonly<Pick<IPosActionDefinition, "name" | "description" | "parametersSchema">> = {
    name: READ_ITEM_LIST_ACTION,
    description: "Return the item list in the attached photo, line by line, so POS can add the items to the cart. "
        + "Use only when supportedActions lists readItemList: the Counter order view sends a photo of a list of "
        + "item IDs and quantities, such as an order sheet, a parts list or a handwritten note. Copy each item ID "
        + "exactly as written; for a line that names a product without one, find the product with the Commerce "
        + "search tools. POS looks up each item ID exactly, as for a pasted list, shows the products it found for "
        + "the associate to check, and adds nothing until the associate chooses.",

    parametersSchema: {
        type: "object",
        properties: {
            itemList: {
                type: "object",
                properties: {
                    lines: {
                        type: "array",
                        minItems: 1,
                        // As many lines as one bulk add takes.
                        maxItems: 100,
                        description: "Every line of the list that names an item, in the order written. Leave out "
                            + "headings, totals, dates, names and anything else that names no item.",
                        items: {
                            type: "object",
                            properties: {
                                text: {
                                    type: "string",
                                    minLength: 1,
                                    maxLength: 120,
                                    description: "The line as written, for example \"0101 x 3\" or \"Blue widget, 2\". "
                                        + "Shown to the associate beside the product POS found for it."
                                },
                                itemId: {
                                    type: "string",
                                    minLength: 1,
                                    maxLength: 40,
                                    description: "The item ID written on the line, character for character. For a "
                                        + "line without one, the ItemId of the one product search_products or "
                                        + "get_product_by_id returned for it. Never invent one."
                                },
                                productId: {
                                    type: "integer",
                                    exclusiveMinimum: 0,
                                    description: "Optional. The record identifier of the exact product or variant a "
                                        + "Commerce tool returned for the line, for example the variant in the size "
                                        + "and colour written. POS uses it only when its item ID is itemId. Never "
                                        + "invent one."
                                },
                                quantity: {
                                    type: "integer",
                                    minimum: 1,
                                    maximum: 1000000,
                                    description: "The quantity written on the line. Never guess one."
                                },
                                problem: {
                                    type: "string",
                                    enum: ["unreadable", "noQuantity", "notFound", "ambiguous"],
                                    description: "Why the line can't be added as written: \"unreadable\" when it can't "
                                        + "be read, \"noQuantity\" when no quantity is written, \"notFound\" when a "
                                        + "line without an item ID matches no product, and \"ambiguous\" when it "
                                        + "matches more than one. Leave it out when the line has an item ID and a "
                                        + "quantity."
                                }
                            },
                            required: ["text"],
                            anyOf: [
                                { required: ["itemId", "quantity"] },
                                { required: ["problem"] }
                            ],
                            additionalProperties: false
                        }
                    }
                },
                required: ["lines"],
                additionalProperties: false
            }
        },
        required: ["itemList"],
        additionalProperties: false
    }
};

/** Every action POS can perform. Add an entry here to teach the agent a new capability. */
export const POS_ACTION_CATALOGUE: ReadonlyArray<IPosActionDefinition> = [
    createCustomerOrder,
    shipCart,
    buildCartFromIntent,
    showProductRecommendations,
    showCartSuggestions,
    navigateToProductDetails,
    showCart,
    retryOrderLookup
];

/**
 * Lists the actions POS publishes to the agent on every request.
 *
 * Names only: the agent instructions define what each action does and the arguments it accepts,
 * and the names tell the agent which of those this POS build can actually perform.
 * @returns The advertised action names.
 */
export function getSupportedActionNames(): string[] {
    return POS_ACTION_CATALOGUE.map((definition: IPosActionDefinition) => definition.name);
}

/**
 * Lists the actions POS publishes with an automatic cart check, which are the only ones it honours
 * for one.
 *
 * `showProductRecommendations` is included for agent instructions that predate `showCartSuggestions`.
 * For an automatic check POS shows its products in the panel as suggestions for the cart, without
 * stock or filter tags, so either action has the same effect.
 * @returns The action names, preferred first.
 */
export function getCartSuggestionActionNames(): string[] {
    return [CART_SUGGESTIONS_ACTION, PRODUCT_RECOMMENDATIONS_ACTION];
}

/**
 * Finds the catalogue entry that can carry out an action.
 * @param action The action the agent returned.
 * @returns The entry, or undefined when POS cannot perform it.
 */
export function findActionDefinition(action: IAgentPosAction): IPosActionDefinition | undefined {
    if (!action || !action.action) {
        return undefined;
    }

    return POS_ACTION_CATALOGUE.filter((definition: IPosActionDefinition) => definition.matches(action))[0];
}

/**
 * Compares two action or view names, tolerating case differences from the agent.
 * @param left The first name.
 * @param right The second name.
 * @returns True when they match.
 */
function isSameName(left: string | undefined, right: string): boolean {
    return !!left && left.toLowerCase() === right.toLowerCase();
}

/**
 * Describes a number of products for a receipt.
 * @param count How many products.
 * @returns For example "1 product" or "3 products".
 */
export function describeProductCount(count: number): string {
    return count === 1 ? "1 product" : `${count} products`;
}
