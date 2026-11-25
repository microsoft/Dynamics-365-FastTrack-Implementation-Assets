/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import * as Views from "PosApi/Create/Views";
import * as SideChat from "ContosoSideChat";
import { ClientEntities } from "PosApi/Entities";

export interface IAgentProductCompareViewOptions {
    products?: SideChat.IAgentProductCard[];
    bestMatchProductId?: number;
    bestMatchReason?: string;
}

export default class AgentProductCompareView extends Views.CustomViewControllerBase {
    private readonly _options: IAgentProductCompareViewOptions;
    private _hostElement: HTMLElement | null;

    constructor(context: Views.ICustomViewControllerContext, options?: IAgentProductCompareViewOptions) {
        super(context, {
            title: "Compare products",
            commandBar: { commands: [] }
        });

        this._options = options ?? {};
        this._hostElement = null;
    }

    public onReady(element: HTMLElement): void {
        this._hostElement = element;

        SideChat.mountProductCompare(element, {
            products: this._options.products ?? [],
            bestMatchProductId: this._options.bestMatchProductId,
            bestMatchReason: this._options.bestMatchReason,
            onProductActivated: (recordId: number): void => {
                this.context.navigator.navigateToPOSView(
                    "SimpleProductDetailsView",
                    new ClientEntities.SimpleProductDetailsNavigationParameters(recordId));
            }
        });
    }

    public dispose(): void {
        if (this._hostElement) {
            SideChat.unmountProductCompare(this._hostElement);
            this._hostElement = null;
        }
    }
}
