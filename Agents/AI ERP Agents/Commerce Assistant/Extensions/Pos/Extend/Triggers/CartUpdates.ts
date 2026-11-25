/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Lets custom views follow the cart. POS doesn't tell a custom view when the cart changes, so the post-sale
 * trigger passes the cart on here whenever products are added, wherever they were added from: a view, the
 * side panel or the cart itself.
 */

import { ProxyEntities } from "PosApi/Entities";

/** Called with the cart after products are added to it. */
export type CartUpdateListener = (cart: ProxyEntities.Cart) => void;

const listeners: CartUpdateListener[] = [];

/**
 * Calls a listener with the cart each time products are added to it.
 * @param listener The listener.
 * @returns A function that stops calling the listener.
 */
export function subscribeToCartUpdates(listener: CartUpdateListener): () => void {
    listeners.push(listener);
    return (): void => {
        const index: number = listeners.indexOf(listener);
        if (index >= 0) {
            listeners.splice(index, 1);
        }
    };
}

/**
 * Passes the cart to the listeners.
 * @param cart The cart after products were added to it.
 */
export function publishCartUpdate(cart: ProxyEntities.Cart | undefined): void {
    if (!cart) {
        return;
    }

    listeners.slice().forEach((listener: CartUpdateListener): void => {
        try {
            listener(cart);
        } catch (error) {
            // A view that can't show the cart must not hold up the sale or the other views.
        }
    });
}
