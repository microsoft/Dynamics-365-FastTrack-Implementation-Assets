/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import * as Views from "PosApi/Create/Views";
import { ObjectExtensions } from "PosApi/TypeExtensions";
import ko from "knockout";

export interface ISampleItem {
    label: string;
    viewName?: string;
    items?: ISampleItem[];
}

/**
 * The controller for SamplesView.
 */
export default class SamplesView extends Views.CustomViewControllerBase {
    public readonly samplesList: ISampleItem[];

    constructor(context: Views.ICustomViewControllerContext) {
        super(context);

        this.state.title = "Commerce Assistant";

        this.samplesList = [
            {
                label: "Copilot",
                items: [
                    { label: "Customer order lookup", viewName: "CustomerOrderLookupView" },
                    { label: "Counter order", viewName: "CounterOrderView" }
                ]
            }
        ];
    }

    /**
     * Bind the html element with view controller.
     * @param {HTMLElement} element DOM element.
     */
    public onReady(element: HTMLElement): void {
        ko.applyBindings(this, element);
    }

    /**
     * Called when the object is disposed.
     */
    public dispose(): void {
        ObjectExtensions.disposeAllProperties(this);
    }

    /**
     * Click handler for sample link.
     * @param sampleItem Sample item that was clicked.
     */
    public sampleClick(sampleItem: ISampleItem): void {
        this.context.navigator.navigate(sampleItem.viewName);
    }
}
