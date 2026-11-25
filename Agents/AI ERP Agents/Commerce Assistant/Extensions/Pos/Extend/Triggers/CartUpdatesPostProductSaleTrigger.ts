/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import { IPostProductSaleTriggerOptions, PostProductSaleTrigger } from "PosApi/Extend/Triggers/ProductTriggers";
import { publishCartUpdate } from "./CartUpdates";

/**
 * Passes the cart to the custom views that show it, such as Counter order, after products are added to it.
 */
export default class CartUpdatesPostProductSaleTrigger extends PostProductSaleTrigger {
    /**
     * Executes the trigger functionality.
     * @param {IPostProductSaleTriggerOptions} options The options provided to the trigger.
     * @returns {Promise<void>} A promise resolved straight away.
     */
    public execute(options: IPostProductSaleTriggerOptions): Promise<void> {
        try {
            publishCartUpdate(options.cart);
        } catch (error) {
            // The views refresh the cart when they're shown again, so a failure here must never interrupt the sale.
            this.context.logger.logError("Failed to pass the cart to the views that show it: " + JSON.stringify(error));
        }

        return Promise.resolve();
    }
}
