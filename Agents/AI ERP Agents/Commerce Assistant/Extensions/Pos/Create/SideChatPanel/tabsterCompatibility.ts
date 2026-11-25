/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Lets the panel's Fluent UI share the Tabster instance that Store Commerce creates.
 *
 * Tabster, the keyboard and focus library under Fluent UI, keeps one instance per window in
 * `window.__tabsterInstance`, created by whichever bundle needs it first. Store Commerce ships an
 * older Tabster, so it usually creates the instance. Tabster 8.8 and later, which this panel bundles,
 * register how each focus feature handles its `data-tabster` attribute in the instance's
 * `attrHandlers` map, which older instances do not have. Without the map, the first tag group, menu,
 * dialog or focus group the panel shows throws "Cannot read properties of undefined (reading 'set')"
 * (https://github.com/microsoft/tabster/issues/557).
 *
 * Tabster deletes the instance when its last user unmounts, and the next user, POS or the panel,
 * creates a new one. Patching the current instance once is therefore not enough, so every instance
 * assigned later gets the map too.
 */

const INSTANCE_PROPERTY: string = "__tabsterInstance";

interface ITabsterInstance {
    attrHandlers?: Map<string, unknown>;
}

/**
 * Gives an instance created by Tabster 8.7 or earlier the empty `attrHandlers` map that Tabster 8.8
 * fills as it adds each focus feature. Older Tabster code never reads the map.
 * @param instance The value stored in `window.__tabsterInstance`.
 */
function addAttributeHandlers(instance: unknown): void {
    if (instance && typeof instance === "object" && !(instance as ITabsterInstance).attrHandlers) {
        (instance as ITabsterInstance).attrHandlers = new Map<string, unknown>();
    }
}

/**
 * Makes the window's current and future Tabster instances usable by the panel's Fluent UI.
 * Safe to call more than once.
 * @param win The window the panel renders into.
 */
export function ensureTabsterCompatibility(win: Window | null): void {
    if (!win) {
        return;
    }

    addAttributeHandlers((win as unknown as Record<string, unknown>)[INSTANCE_PROPERTY]);

    const windowPrototype: object | null = Object.getPrototypeOf(win);
    if (!windowPrototype || Object.prototype.hasOwnProperty.call(windowPrototype, INSTANCE_PROPERTY)) {
        return;
    }

    // Tabster stores its instance with a plain assignment and removes it with `delete`. While no
    // instance exists, that assignment reaches this setter, which stores the instance on the window
    // itself, so reading and deleting it behave exactly as before.
    Object.defineProperty(windowPrototype, INSTANCE_PROPERTY, {
        configurable: true,
        get(): undefined {
            return undefined;
        },
        set(this: object, instance: unknown): void {
            addAttributeHandlers(instance);
            Object.defineProperty(this, INSTANCE_PROPERTY, {
                configurable: true,
                enumerable: true,
                writable: true,
                value: instance
            });
        }
    });
}
