/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Tells the agent which products are on the sale, so that it can act on them: for example, check
 * which store has them in stock before it asks POS to ship them. Sent with the requests the associate
 * types. Customers and addresses are never sent; POS reads those itself.
 *
 * The assistant gateway rejects a message over 4,000 characters, so a large sale is described in less
 * detail until it fits: fewer lines, then shorter names, then no names. When not even that fits, the
 * request goes without the sale, as it did before.
 */

import { ProxyEntities } from "PosApi/Entities";
import { IAgentRequestEnvelope, IAgentSaleLine, IAgentSaleSnapshot } from "ContosoSideChat";
import { CART_SUGGESTION_MESSAGE_BUDGET, measure } from "./cartSuggestionEnvelope";
import { getSoldLines } from "./shippingRules";

/** How much of the sale to describe: the most lines, and the longest name, where 0 sends no names. */
interface ISaleDetailLevel {
    maxLines: number;
    maxNameLength: number;
}

const DETAIL_LEVELS: ISaleDetailLevel[] = [
    { maxLines: 30, maxNameLength: 60 },
    { maxLines: 15, maxNameLength: 30 },
    { maxLines: 8, maxNameLength: 0 },
    { maxLines: 4, maxNameLength: 0 }
];

/**
 * Lists the products sold on the sale, newest first.
 * @param cart The current cart.
 * @returns One entry per line that sells a product: voided, returned, gift card and deposit lines are left out.
 */
export function describeSale(cart: ProxyEntities.Cart | undefined): IAgentSaleLine[] {
    return getSoldLines(cart).reverse().map((line: ProxyEntities.CartLine): IAgentSaleLine => {
        const saleLine: IAgentSaleLine = { productId: line.ProductId, quantity: line.Quantity };
        if (typeof line.Description === "string" && line.Description.trim().length > 0) {
            saleLine.name = line.Description.trim();
        }

        return saleLine;
    });
}

/**
 * Adds the sale to a request, in as much detail as fits the gateway's limit.
 * @param envelope The request.
 * @param lines The products on the sale, newest first.
 * @returns A copy of the request with the sale, or the request itself when the sale is empty or doesn't fit.
 */
export function addSale(envelope: IAgentRequestEnvelope, lines: IAgentSaleLine[]): IAgentRequestEnvelope {
    if (!Array.isArray(lines) || lines.length === 0) {
        return envelope;
    }

    for (const level of DETAIL_LEVELS) {
        const shown: IAgentSaleLine[] = lines.slice(0, level.maxLines).map(
            (line: IAgentSaleLine) => shorten(line, level.maxNameLength));
        const sale: IAgentSaleSnapshot = { lines: shown };
        if (shown.length < lines.length) {
            sale.omittedLines = lines.length - shown.length;
        }

        const candidate: IAgentRequestEnvelope = { ...envelope, sale: sale };
        if (measure(candidate) <= CART_SUGGESTION_MESSAGE_BUDGET) {
            return candidate;
        }
    }

    return envelope;
}

function shorten(line: IAgentSaleLine, maxNameLength: number): IAgentSaleLine {
    const shortened: IAgentSaleLine = { productId: line.productId, quantity: line.quantity };
    if (maxNameLength > 0 && typeof line.name === "string" && line.name.length > 0) {
        shortened.name = line.name.length > maxNameLength
            ? `${line.name.slice(0, maxNameLength - 1).trim()}\u2026`
            : line.name;
    }

    return shortened;
}
