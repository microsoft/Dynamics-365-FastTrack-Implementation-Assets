/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Builds the request for an automatic cart check: the turn POS starts on its own after an item is
 * added to the cart, asking the agent which products go best with the cart.
 *
 * The instruction travels in the request itself, so the check works with agent instructions that
 * predate it. The whole request must fit in the assistant gateway's message limit, so a large cart is
 * sent in progressively less detail rather than failing the request.
 *
 * Pure on purpose: no POS APIs, so the size rules can be tested outside POS.
 */

import { IAgentCartLine, IAgentCartSnapshot, IAgentRequestEnvelope } from "ContosoSideChat";

/**
 * The most characters the request may take up. The assistant gateway rejects a message over 4,000
 * characters; the difference is headroom for the gateway's own escaping.
 */
export const CART_SUGGESTION_MESSAGE_BUDGET: number = 3800;

/** Identifies a turn POS started because an item was added to the cart. */
export const CART_ITEM_ADDED_TRIGGER: "cartItemAdded" = "cartItemAdded";

/**
 * What POS asks the agent. Sent as `text`, because that is the one field every version of the agent
 * instructions reads.
 *
 * The check only looks products up; adding one is the associate's call. It never checks stock: the
 * stock tools take only an exact variant, which a suggestion rarely has, and one failed tool call
 * fails the agent's whole answer. Product search matches any of the words it is given, so a search
 * built from the cart item's own name ("BMX helmet accessories") returns more of that item first; the
 * agent is told to search for the kinds of item used with it instead, and never to offer a
 * replacement. Tools that recommend products or list discounts are welcome as well, once Commerce
 * offers them. Product names stay out of the reply's text because each card already shows its
 * product's name, and because some catalogue names, such as an accessory set labelled for adults, can
 * set off Azure's content filter, which then blocks the whole reply.
 */
export const CART_SUGGESTION_INSTRUCTION: string =
    "Automatic cart check. POS sent this because an item was just added to the cart; the associate typed "
    + "nothing. Find up to 3 products that complement the items in `cart`: used with them, often bought "
    + "with them, or earning a discount with them. Never suggest a replacement: nothing of the same kind "
    + "as a cart item, in any brand, model, size, colour or tier (no second helmet or tire). First pick "
    + "two kinds of item used with what was just added (helmet: gloves, pads; bike tire: inner tube, "
    + "pump), then call search_products once per kind, with only that kind or the activity as "
    + "searchTerm. Never put a cart item's own kind in searchTerm: search matches any word, so it returns "
    + "more of the same. Keep picks suited to the item (a bike pump, not a ball pump). If a tool returns "
    + "recommended or related products, or available discounts or promotions, use it too. Only use tools "
    + "that read, such as search_products, get_product_by_id and get_cart. Do not check stock: never call "
    + "check_product_availability or check_product_availability_in_area on this check. "
    + "Never call add_product_to_cart or any other tool that changes the cart: the associate decides what "
    + "to add. Use only ProductIds a tool returned, never a product, or the master of a variant, already "
    + "in the cart, and recheck your picks for replacements. Return exactly one action: "
    + "showCartSuggestions with details {productIds, reasons: [{productId, reason}], headline}. If you do "
    + "not know that action, use showProductRecommendations with productIds and headline instead. Never "
    + "navigate or return any other action. Each card shows its product's name, so leave product names out "
    + "of displayMessage, headline and reasons, and say what each product adds to this cart instead. In "
    + "displayMessage, say in one or two sentences why these go with the current cart; mention a discount "
    + "only if a tool result or the cart's offers or promotions confirm it. If nothing fits, return "
    + "posActions: [] and one short sentence.";

/** What the request is built from. */
export interface ICartSuggestionEnvelopeInput {
    conversationId: string;
    cartId: string;
    currentView: string;
    supportedActions: string[];
    /** The full cart; it is trimmed here if it does not fit. */
    cart: IAgentCartSnapshot;
}

/** How much of the cart one attempt sends. */
interface ICartDetailLevel {
    /** How many lines to send, newest first. */
    maxLines: number;
    /** The longest product name to send. Zero leaves names out. */
    maxNameLength: number;
    /** How many discount and promotion names to send per line. */
    maxLabels: number;
    /** Whether to send each line's item number and amounts. */
    includeAmounts: boolean;
}

/** From the whole cart down to a handful of lines, tried in order until the request fits. */
const DETAIL_LEVELS: ReadonlyArray<ICartDetailLevel> = [
    { maxLines: 40, maxNameLength: 60, maxLabels: 3, includeAmounts: true },
    { maxLines: 25, maxNameLength: 40, maxLabels: 2, includeAmounts: true },
    { maxLines: 15, maxNameLength: 30, maxLabels: 1, includeAmounts: true },
    { maxLines: 10, maxNameLength: 24, maxLabels: 0, includeAmounts: false },
    { maxLines: 5, maxNameLength: 0, maxLabels: 0, includeAmounts: false }
];

/** The most product identifiers sent when not even five lines fit. */
const MAX_FALLBACK_PRODUCT_IDS: number = 40;

/** The longest discount or promotion name sent. */
const MAX_LABEL_LENGTH: number = 40;

/**
 * Builds the request for an automatic cart check, in as much detail as fits the gateway's limit.
 * @param input The conversation, the view, and the full cart.
 * @returns The request. Its serialized form fits {@link CART_SUGGESTION_MESSAGE_BUDGET} unless even the
 * cart's product identifiers alone do not.
 */
export function buildCartSuggestionEnvelope(input: ICartSuggestionEnvelopeInput): IAgentRequestEnvelope {
    for (const level of DETAIL_LEVELS) {
        const envelope: IAgentRequestEnvelope = createEnvelope(input, compactCart(input.cart, level));
        if (measure(envelope) <= CART_SUGGESTION_MESSAGE_BUDGET) {
            return envelope;
        }
    }

    // Not even five lines fit, so send only which products are in the cart.
    const productIds: number[] = input.cart.productIds.slice(0, MAX_FALLBACK_PRODUCT_IDS);
    const fallbackCart: IAgentCartSnapshot = {
        productIds: productIds,
        addedProductIds: input.cart.addedProductIds.slice(0, MAX_FALLBACK_PRODUCT_IDS),
        lines: [],
        omittedLines: input.cart.lines.length
    };
    if (productIds.length < input.cart.productIds.length) {
        fallbackCart.omittedProductIds = input.cart.productIds.length - productIds.length;
    }

    return createEnvelope(input, fallbackCart);
}

/**
 * Measures a request the way the gateway does: as the serialized message.
 * @param envelope The request.
 * @returns Its length in characters.
 */
export function measure(envelope: IAgentRequestEnvelope): number {
    return JSON.stringify(envelope).length;
}

function createEnvelope(input: ICartSuggestionEnvelopeInput, cart: IAgentCartSnapshot): IAgentRequestEnvelope {
    return {
        text: CART_SUGGESTION_INSTRUCTION,
        conversationId: input.conversationId,
        cartId: input.cartId,
        currentView: input.currentView,
        supportedActions: input.supportedActions,
        trigger: CART_ITEM_ADDED_TRIGGER,
        cart: cart
    };
}

function compactCart(cart: IAgentCartSnapshot, level: ICartDetailLevel): IAgentCartSnapshot {
    const lines: IAgentCartLine[] = cart.lines
        .slice(0, level.maxLines)
        .map((line: IAgentCartLine) => compactLine(line, level));
    const compacted: IAgentCartSnapshot = {
        productIds: cart.productIds,
        addedProductIds: cart.addedProductIds,
        lines: lines
    };

    if (cart.lines.length > lines.length) {
        compacted.omittedLines = cart.lines.length - lines.length;
    }

    if (level.includeAmounts) {
        compacted.subtotal = roundAmount(cart.subtotal);
        compacted.discount = roundAmount(cart.discount);
        compacted.total = roundAmount(cart.total);
    }

    return compacted;
}

function compactLine(line: IAgentCartLine, level: ICartDetailLevel): IAgentCartLine {
    const compacted: IAgentCartLine = { productId: line.productId, quantity: line.quantity };

    if (typeof line.masterProductId === "number" && line.masterProductId !== line.productId) {
        compacted.masterProductId = line.masterProductId;
    }

    if (level.maxNameLength > 0 && line.name) {
        compacted.name = truncate(line.name, level.maxNameLength);
    }

    if (level.includeAmounts) {
        compacted.itemId = line.itemId || undefined;
        compacted.price = roundAmount(line.price);
        compacted.total = roundAmount(line.total);
        compacted.discount = line.discount ? roundAmount(line.discount) : undefined;
    }

    const offers: string[] = limitLabels(line.offers, level.maxLabels);
    if (offers.length > 0) {
        compacted.offers = offers;
    }

    const promotions: string[] = limitLabels(line.promotions, level.maxLabels);
    if (promotions.length > 0) {
        compacted.promotions = promotions;
    }

    return compacted;
}

/**
 * Rounds an amount to cents. JSON leaves out the undefined it returns for a missing amount.
 * @param value The amount.
 * @returns The rounded amount, or undefined when there is none.
 */
function roundAmount(value: number | undefined): number | undefined {
    return typeof value === "number" && isFinite(value) ? Math.round(value * 100) / 100 : undefined;
}

function limitLabels(labels: string[] | undefined, maxLabels: number): string[] {
    if (!labels || maxLabels <= 0) {
        return [];
    }

    return labels
        .filter((label: string) => typeof label === "string" && label.trim().length > 0)
        .slice(0, maxLabels)
        .map((label: string) => truncate(label.trim(), MAX_LABEL_LENGTH));
}

function truncate(value: string, maxLength: number): string {
    return value.length > maxLength ? `${value.substring(0, maxLength - 1)}\u2026` : value;
}
