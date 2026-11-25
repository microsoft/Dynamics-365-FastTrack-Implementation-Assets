import {
    CustomPackingItem, ICustomPackingItemContext, CustomPackingItemPosition, ICustomPackingItemState
} from "PosApi/Extend/Header";
import ko from "knockout";


/**
 * (Sample) Custom packing item that navigates to the samples view.
 */
export default class SamplesViewPackingItem extends CustomPackingItem {
    /**
     * The position of the custom packing item relative to the out-of-the-box items.
     */
    public readonly position: CustomPackingItemPosition = CustomPackingItemPosition.Before;

    /**
     * The label of the packing item.
     */
    public label: ko.Computed<string>;

    /**
     * Initializes a new instance of the SamplesViewPackingItem class.
     * @param {string} id The item identifier.
     * @param {ICustomPackingItemContext} context The custom packing item context.
     */
    constructor(id: string, context: ICustomPackingItemContext) {
        super(id, context);

        this.visible = true;
        this.label = "Navigate to Samples View";
    }

    /**
     * Called when the control element is ready.
     * @param {HTMLElement} packedElement The DOM element of the packed element.
     * @param {HTMLElement} unpackedElement The DOM element of the unpacked element.
     */
    public onReady(packedElement: HTMLElement, unpackedElement: HTMLElement): void {
        ko.applyBindingsToNode(unpackedElement, {
            template: {
                name: "UnpackedSimpleExtensionViewItem",
                data: this
            }
        });

        ko.applyBindingsToNode(packedElement, {
            template: {
                name: "PackedSimpleExtensionViewItem",
                data: this
            }
        });
    }

    /**
     * Initializes the control.
     * @param {ICustomPackingItemState} state The custom control state.
     */
    public init(state: ICustomPackingItemState): void {
        return;
    }

    /**
     * Disposes the control releasing its resources.
     */
    public dispose(): void {
        super.dispose();
    }

    /**
     * Method used to handle the onClick of the custom packing item.
     */
    public onItemClickedHandler(): void {
        this.context.navigator.navigate("SamplesView");
    }
}