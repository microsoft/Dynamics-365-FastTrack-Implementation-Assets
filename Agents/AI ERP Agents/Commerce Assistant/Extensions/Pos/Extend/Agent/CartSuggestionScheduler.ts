/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Decides when an item added to the cart should start an automatic cart check, and what the check
 * is about.
 *
 * Every addition is not worth a request to the agent. Adding waits for the cart to settle, so a burst
 * of scans is asked about once. A cart whose products have not changed since the last check, such as
 * after a quantity change, is not asked about again. Returns, payments in progress and carts that are
 * not sales are left alone, and so are items the agent's own actions add, such as the lines of a
 * customer order it is creating.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { GetCurrentCartClientRequest, GetCurrentCartClientResponse } from "PosApi/Consume/Cart";
import { GetProductsByIdsClientRequest, GetProductsByIdsClientResponse } from "PosApi/Consume/Products";
import { ObjectExtensions, StringExtensions } from "PosApi/TypeExtensions";
import { IAgentCartLine, IAgentCartSnapshot, ICartSuggestionRequest } from "ContosoSideChat";

/** How long the cart must go without another addition before it is checked. */
const SETTLE_DELAY_MILLISECONDS: number = 1500;

/** Receives each cart that should be checked. */
export type CartSuggestionPublisher = (request: ICartSuggestionRequest) => void;

/** Waits for the cart to settle. */
let settleTimer: number | undefined;

/** The products added since the last check started. */
let pendingAddedProductIds: number[] = [];

/** Identifies the cart and products last asked about. */
let lastCheckedSignature: string = StringExtensions.EMPTY;

/** How many batches of the agent's actions are running. Items added meanwhile are theirs. */
let agentActionsRunning: number = 0;

/** Changes on every reset, so a check started before a sign-out never publishes after it. */
let generation: number = 0;

/**
 * Notes that products were added to the cart, and checks the cart once it settles.
 * @param {ReadonlyArray<number>} addedProductIds The products just added.
 * @param {IExtensionContext} context The POS extension context.
 * @param {CartSuggestionPublisher} publish Receives the cart to check, if it should be checked.
 */
export function scheduleCartSuggestions(
    addedProductIds: ReadonlyArray<number>,
    context: IExtensionContext,
    publish: CartSuggestionPublisher
): void {
    if (agentActionsRunning > 0) {
        return;
    }

    addedProductIds.forEach((productId: number): void => {
        if (isProductId(productId) && pendingAddedProductIds.indexOf(productId) < 0) {
            pendingAddedProductIds.push(productId);
        }
    });

    if (settleTimer !== undefined) {
        window.clearTimeout(settleTimer);
    }

    const scheduledGeneration: number = generation;
    settleTimer = window.setTimeout((): void => {
        settleTimer = undefined;
        const added: number[] = pendingAddedProductIds;
        pendingAddedProductIds = [];

        checkCartAsync(added, context, publish, scheduledGeneration).catch((error: unknown): void => {
            context.logger.logInformational(
                `CartSuggestionScheduler: the cart could not be checked. ${JSON.stringify(error)}`);
        });
    }, SETTLE_DELAY_MILLISECONDS);
}

/**
 * Runs the agent's actions so that anything they add to the cart does not start a cart check.
 * @param {() => Promise<T>} work Runs the actions.
 * @returns {Promise<T>} What the work returned.
 */
export function runWhileAgentActionsRun<T>(work: () => Promise<T>): Promise<T> {
    agentActionsRunning += 1;
    let isFinished: boolean = false;
    const finish = (): void => {
        if (!isFinished) {
            isFinished = true;
            agentActionsRunning -= 1;
        }
    };

    try {
        return work().then(
            (result: T): T => {
                finish();
                return result;
            },
            (error: unknown): Promise<T> => {
                finish();
                return Promise.reject(error);
            });
    } catch (error) {
        finish();
        return Promise.reject(error);
    }
}

/**
 * Forgets everything about earlier checks. Called when the operator signs out or locks the terminal,
 * so nothing about one operator's cart reaches the next.
 */
export function resetCartSuggestions(): void {
    if (settleTimer !== undefined) {
        window.clearTimeout(settleTimer);
        settleTimer = undefined;
    }

    pendingAddedProductIds = [];
    lastCheckedSignature = StringExtensions.EMPTY;
    generation += 1;
}

async function checkCartAsync(
    addedProductIds: number[],
    context: IExtensionContext,
    publish: CartSuggestionPublisher,
    scheduledGeneration: number
): Promise<void> {
    if (agentActionsRunning > 0) {
        return;
    }

    const correlationId: string = context.logger.getNewCorrelationId();
    const cartResult: ClientEntities.ICancelableDataResult<GetCurrentCartClientResponse> =
        await context.runtime.executeAsync(new GetCurrentCartClientRequest<GetCurrentCartClientResponse>(correlationId));
    if (scheduledGeneration !== generation
        || cartResult.canceled
        || ObjectExtensions.isNullOrUndefined(cartResult.data)
        || ObjectExtensions.isNullOrUndefined(cartResult.data.result)) {
        return;
    }

    const cart: ProxyEntities.Cart = cartResult.data.result;
    if (!isSaleInProgress(cart)) {
        return;
    }

    const lines: ProxyEntities.CartLine[] = getSoldLines(cart);
    const productIds: number[] = distinct(lines.map((line: ProxyEntities.CartLine) => line.ProductId));
    if (productIds.length === 0) {
        return;
    }

    // Quantities are left out on purpose: selling more of the same products asks nothing new.
    const signature: string = `${cart.Id}|${productIds.slice().sort((left: number, right: number) => left - right).join(",")}`;
    if (signature === lastCheckedSignature) {
        return;
    }

    const masterProductIds: { [productId: number]: number } =
        await getMasterProductIdsAsync(productIds, context, correlationId);
    if (scheduledGeneration !== generation) {
        return;
    }

    lastCheckedSignature = signature;
    publish({
        cartId: cart.Id,
        cart: createSnapshot(cart, lines, addedProductIds, masterProductIds)
    });
}

/**
 * Answers whether the cart is a sale the operator is still building.
 * @param {ProxyEntities.Cart} cart The current cart.
 * @returns {boolean} False for returns, payments in progress, and carts that are not sales.
 */
function isSaleInProgress(cart: ProxyEntities.Cart): boolean {
    if (StringExtensions.isNullOrWhitespace(cart.Id) || cart.IsReturnByReceipt) {
        return false;
    }

    const cartType: number = cart.CartTypeValue ?? ProxyEntities.CartType.None;
    if (cartType !== ProxyEntities.CartType.None
        && cartType !== ProxyEntities.CartType.Shopping
        && cartType !== ProxyEntities.CartType.CustomerOrder) {
        return false;
    }

    const orderMode: number = cart.CustomerOrderModeValue ?? ProxyEntities.CustomerOrderMode.None;
    if (orderMode !== ProxyEntities.CustomerOrderMode.None
        && orderMode !== ProxyEntities.CustomerOrderMode.CustomerOrderCreateOrEdit
        && orderMode !== ProxyEntities.CustomerOrderMode.QuoteCreateOrEdit) {
        return false;
    }

    // Once payment has started, the operator is closing the sale rather than adding to it.
    return !(cart.TenderLines ?? []).some((tenderLine: ProxyEntities.TenderLine) =>
        tenderLine.StatusValue !== ProxyEntities.TenderLineStatus.Voided);
}

/**
 * Picks the lines that sell a product.
 * @param {ProxyEntities.Cart} cart The current cart.
 * @returns {ProxyEntities.CartLine[]} The lines, oldest first, without voided, returned, gift card and
 * deposit lines.
 */
function getSoldLines(cart: ProxyEntities.Cart): ProxyEntities.CartLine[] {
    return (cart.CartLines ?? []).filter((line: ProxyEntities.CartLine) =>
        !line.IsVoided
        && !line.IsGiftCardLine
        && !line.IsCustomerAccountDeposit
        && isProductId(line.ProductId)
        && line.Quantity > 0);
}

/**
 * Finds the master of every variant in the cart, so the agent can tell which products it already
 * holds in some color or size.
 * @param {number[]} productIds The products in the cart.
 * @param {IExtensionContext} context The POS extension context.
 * @param {string} correlationId The correlation identifier for logging.
 * @returns {Promise<{ [productId: number]: number }>} The master of each variant. Products that are not
 * variants, and every product when the lookup fails, are left out.
 */
async function getMasterProductIdsAsync(
    productIds: number[],
    context: IExtensionContext,
    correlationId: string
): Promise<{ [productId: number]: number }> {
    const masterProductIds: { [productId: number]: number } = {};

    try {
        const result: ClientEntities.ICancelableDataResult<GetProductsByIdsClientResponse> =
            await context.runtime.executeAsync(
                new GetProductsByIdsClientRequest<GetProductsByIdsClientResponse>(productIds, correlationId));
        const products: ProxyEntities.SimpleProduct[] =
            result.canceled || ObjectExtensions.isNullOrUndefined(result.data) ? [] : result.data.result ?? [];

        products.forEach((product: ProxyEntities.SimpleProduct): void => {
            if (isProductId(product.MasterProductId) && product.MasterProductId !== product.RecordId) {
                masterProductIds[product.RecordId] = product.MasterProductId;
            }
        });
    } catch (error) {
        // The check is still useful without masters; the agent can look variants up itself.
        context.logger.logInformational(
            `CartSuggestionScheduler: variant masters could not be read. ${JSON.stringify(error)}`, correlationId);
    }

    return masterProductIds;
}

/**
 * Describes the cart for the agent.
 * @param {ProxyEntities.Cart} cart The current cart.
 * @param {ProxyEntities.CartLine[]} lines The lines that sell a product, oldest first.
 * @param {number[]} addedProductIds The products whose addition started the check.
 * @param {{ [productId: number]: number }} masterProductIds The master of each variant.
 * @returns {IAgentCartSnapshot} The whole cart. The request is trimmed later if it is too large to send.
 */
function createSnapshot(
    cart: ProxyEntities.Cart,
    lines: ProxyEntities.CartLine[],
    addedProductIds: number[],
    masterProductIds: { [productId: number]: number }
): IAgentCartSnapshot {
    // Newest first, so that trimming a large cart drops the oldest lines rather than the new ones.
    const newestFirst: ProxyEntities.CartLine[] = lines.slice().reverse();

    return {
        productIds: distinct(newestFirst.map((line: ProxyEntities.CartLine) => line.ProductId)),
        addedProductIds: addedProductIds,
        lines: newestFirst.map((line: ProxyEntities.CartLine): IAgentCartLine => ({
            productId: line.ProductId,
            masterProductId: masterProductIds[line.ProductId],
            itemId: line.ItemId,
            name: line.Description,
            quantity: line.Quantity,
            price: line.Price,
            total: line.TotalAmount,
            discount: line.DiscountAmount,
            offers: distinctText((line.DiscountLines ?? []).map((discountLine: ProxyEntities.DiscountLine) =>
                discountLine.OfferName)),
            promotions: distinctText(line.PromotionLines ?? [])
        })),
        subtotal: cart.SubtotalAmount,
        discount: cart.DiscountAmount,
        total: cart.TotalAmount
    };
}

function isProductId(value: number | undefined): boolean {
    return typeof value === "number" && isFinite(value) && value > 0;
}

function distinct(values: number[]): number[] {
    return values.filter((value: number, index: number) => values.indexOf(value) === index);
}

function distinctText(values: string[]): string[] {
    const trimmed: string[] = values
        .filter((value: string) => !StringExtensions.isNullOrWhitespace(value))
        .map((value: string) => value.trim());

    return trimmed.filter((value: string, index: number) => trimmed.indexOf(value) === index);
}
