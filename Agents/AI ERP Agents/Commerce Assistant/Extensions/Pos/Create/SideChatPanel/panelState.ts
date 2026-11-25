/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * A tiny observable holding whether the panel is open.
 *
 * The panel is opened from the POS header icon, which lives outside React (it is a Knockout header
 * packing item), so the open state cannot be React component state. Keeping it in the module lets
 * the header toggle it imperatively while the panel subscribes and re-renders.
 *
 * The panel's width lives here too, because the views the agent opens need to leave room for it.
 */

type Listener = (isOpen: boolean) => void;

/**
 * Width of the open panel: 30% of the screen, but no narrower than 400px, so product cards keep a
 * usable text column, and no wider than 480px, so the view behind keeps most of a wide screen.
 *
 * The panel is `position: fixed` over the right edge rather than reflowing POS, so a view that
 * opens next to it pads its right side by this much to keep its content visible.
 */
export const PANEL_WIDTH: string = "clamp(400px, 30vw, 480px)";

let isOpen: boolean = false;
const listeners = new Set<Listener>();

/**
 * Reads the current open state.
 * @returns True when the panel is open.
 */
export function getIsOpen(): boolean {
    return isOpen;
}

/**
 * Sets the open state, notifying subscribers when it actually changes.
 * @param value The new open state.
 */
export function setIsOpen(value: boolean): void {
    if (value === isOpen) {
        return;
    }

    isOpen = value;
    listeners.forEach((listener) => listener(isOpen));
}

/**
 * Flips the open state.
 * @returns The new open state.
 */
export function toggleIsOpen(): boolean {
    setIsOpen(!isOpen);
    return isOpen;
}

/**
 * Subscribes to open state changes.
 * @param listener Called with the new state whenever it changes.
 * @returns A function that removes the subscription.
 */
export function subscribe(listener: Listener): () => void {
    listeners.add(listener);
    return () => {
        listeners.delete(listener);
    };
}
