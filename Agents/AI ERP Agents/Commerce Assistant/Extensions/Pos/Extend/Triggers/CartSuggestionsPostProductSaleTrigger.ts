/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import { ClientEntities } from "PosApi/Entities";
import { IPostProductSaleTriggerOptions, PostProductSaleTrigger } from "PosApi/Extend/Triggers/ProductTriggers";
import { suggestProductsForCart } from "./SideChatPanelHost";

/**
 * Asks the Copilot agent which products would go well with the cart whenever the operator adds to it.
 *
 * The sale is never held up: the trigger only notes what was added and returns. The panel asks the
 * agent once the cart settles and shows any suggestions as product cards the operator can add.
 */
export default class CartSuggestionsPostProductSaleTrigger extends PostProductSaleTrigger {
    /**
     * Executes the trigger functionality.
     * @param {IPostProductSaleTriggerOptions} options The options provided to the trigger.
     * @returns {Promise<void>} A promise resolved straight away.
     */
    public execute(options: IPostProductSaleTriggerOptions): Promise<void> {
        try {
            const addedProductIds: number[] = (options.productSaleDetails || [])
                .map((details: ClientEntities.IProductSaleReturnDetails): number | undefined =>
                    details.productId ?? details.product?.RecordId)
                .filter((productId: number | undefined): boolean =>
                    typeof productId === "number" && isFinite(productId) && productId > 0);

            suggestProductsForCart(addedProductIds, this.context);
        } catch (error) {
            // Suggestions are optional, so a failure here must never interrupt the sale.
            this.context.logger.logError("Failed to request cart suggestions: " + JSON.stringify(error));
        }

        return Promise.resolve();
    }
}
