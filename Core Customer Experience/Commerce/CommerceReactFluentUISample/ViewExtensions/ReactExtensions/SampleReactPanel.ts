/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import {
  CustomerDetailsCustomControlBase,
  ICustomerDetailsCustomControlState,
  ICustomerDetailsCustomControlContext,
} from "PosApi/Extend/Views/CustomerDetailsView";
import { renderCounter } from "reactcomponents";
import ko from "knockout";

export default class SampleReactPanel extends CustomerDetailsCustomControlBase {
  public readonly title: ko.Observable<string>;
  private _state: ICustomerDetailsCustomControlState;
  private static readonly TEMPLATE_ID: string =
    "Microsoft_Pos_Extensibility_Samples_ReactPanel";

  constructor(id: string, context: ICustomerDetailsCustomControlContext) {
    super(id, context);
    this.title = ko.observable("");
  }

  /**
   * Binds the control to the specified element.
   * @param {HTMLElement} element The element to which the control should be bound.
   */
  public onReady(element: HTMLElement): void {
    ko.applyBindingsToNode(
      element,
      {
        template: {
          name: SampleReactPanel.TEMPLATE_ID,
          data: this,
        },
      },
      this
    );
    let sampleReactComponentElem: HTMLDivElement = document.getElementById(
      "samplereactcomponent"
    ) as HTMLDivElement;
    renderCounter(sampleReactComponentElem);
  }

  /**
   * Initializes the control.
   * @param {ICustomerDetailsCustomControlState} state The initial state of the page used to initialize the control.
   */
  public init(state: ICustomerDetailsCustomControlState): void {
    this._state = state;
    this.title("React panel");
    if (!this._state.isSelectionMode) {
      this.isVisible = true;
    }
  }
}
