/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import {
    CustomPackingItem, CustomPackingItemPosition, ICustomPackingItemContext, ICustomPackingItemState
} from "PosApi/Extend/Header";
import ko from "knockout";
import { isSideChatPanelOpen, subscribeToSideChatOpenState, toggleSideChatPanel } from "../Triggers/SideChatPanelHost";

/**
 * Header icon that opens and closes the docked Copilot side panel.
 *
 * The header is a supported extension point (components.extend.header.customPackingItems), and it
 * is rendered once for the application rather than per view, so the icon is available from every
 * view without any per-view registration.
 */
export default class SideChatPackingItem extends CustomPackingItem {
    /**
     * The position of the custom packing item relative to the out-of-the-box items.
     */
    public readonly position: CustomPackingItemPosition = CustomPackingItemPosition.Before;

    /**
     * The label shown next to the icon when the header collapses items into the overflow menu.
     */
    public label: string;

    /**
     * True while the panel is open, so the icon can show it. The panel also opens and closes itself,
     * for example to show cart suggestions, so this follows the panel rather than the icon's clicks.
     */
    public readonly isOpen: ko.Observable<boolean>;

    /** Stops following the panel. Set once the icon is on screen. */
    private _unsubscribeFromOpenState: (() => void) | null;

    /**
     * Initializes a new instance of the SideChatPackingItem class.
     * @param {string} id The item identifier.
     * @param {ICustomPackingItemContext} context The custom packing item context.
     */
    constructor(id: string, context: ICustomPackingItemContext) {
        super(id, context);

        this.visible = true;
        this.label = "Copilot";
        this.isOpen = ko.observable<boolean>(false);
        this._unsubscribeFromOpenState = null;
    }

    /**
     * Called when the control element is ready.
     * @param {HTMLElement} packedElement The DOM element of the packed element.
     * @param {HTMLElement} unpackedElement The DOM element of the unpacked element.
     */
    public onReady(packedElement: HTMLElement, unpackedElement: HTMLElement): void {
        if (!this._unsubscribeFromOpenState) {
            this._unsubscribeFromOpenState = subscribeToSideChatOpenState((isOpen: boolean): void => {
                this.isOpen(isOpen);
            });
            this.isOpen(isSideChatPanelOpen());
        }

        ko.applyBindingsToNode(unpackedElement, {
            template: {
                name: "UnpackedSideChatItem",
                data: this
            }
        });

        ko.applyBindingsToNode(packedElement, {
            template: {
                name: "PackedSideChatItem",
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
        if (this._unsubscribeFromOpenState) {
            this._unsubscribeFromOpenState();
            this._unsubscribeFromOpenState = null;
        }

        super.dispose();
    }

    /**
     * Opens or closes the side panel.
     */
    public onItemClickedHandler(): void {
        toggleSideChatPanel(this.context);
    }
}
