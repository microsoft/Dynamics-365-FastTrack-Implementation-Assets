/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Prepares the stock the agent reported with its recommendations for the product cards.
 *
 * The agent reads stock with the Commerce inventory tools and reports it with the products it
 * recommends. POS shows it as the agent's report and does not check it, so this only makes it safe to
 * show: each entry belongs to a product on screen, quantities are numbers, text is short, and the
 * closest other store is not the associate's own.
 *
 * Pure on purpose: no POS APIs, so the rules can be tested outside POS.
 */

import {
    IAgentProductInventory,
    IAgentProductSelection,
    IAgentStoreContext,
    IAgentStoreStock
} from "ContosoSideChat";

/** The longest store name shown. */
const MAX_STORE_NAME_LENGTH: number = 60;

/** The longest stock status shown, for example "Low stock". */
const MAX_STATUS_LENGTH: number = 40;

/** The longest distance shown, for example "1,889 mi". */
const MAX_DISTANCE_LENGTH: number = 20;

/**
 * Picks the stock to show for the products on screen.
 * @param inventory The stock the agent reported.
 * @param shownProductIds The products on screen, as their displayed (master) record identifiers.
 * @param selections The variants selected for those products, whose identifiers the agent may have used.
 * @param currentStore The associate's store, when known.
 * @returns At most one entry per product on screen, in the agent's order. Empty when nothing is usable.
 */
export function getShownInventory(
    inventory: ReadonlyArray<IAgentProductInventory> | undefined,
    shownProductIds: ReadonlyArray<number>,
    selections: ReadonlyArray<IAgentProductSelection> | undefined,
    currentStore: IAgentStoreContext | undefined
): IAgentProductInventory[] {
    const shown: IAgentProductInventory[] = [];
    if (!Array.isArray(inventory)) {
        return shown;
    }

    inventory.forEach((entry: IAgentProductInventory) => {
        if (!entry || typeof entry.productId !== "number") {
            return;
        }

        const selection: IAgentProductSelection | undefined = (selections || []).filter(
            (candidate: IAgentProductSelection) => candidate && candidate.variantProductId === entry.productId)[0];
        const productId: number = selection ? selection.productId : entry.productId;
        const isShown: boolean = shownProductIds.indexOf(productId) >= 0;
        const isDuplicate: boolean = shown.some((existing: IAgentProductInventory) => existing.productId === productId);
        if (!isShown || isDuplicate) {
            return;
        }

        const currentStoreStock: IAgentStoreStock | undefined = readStock(entry.currentStore, false);
        const nearestStoreStock: IAgentStoreStock | undefined = readStock(entry.nearestStore, true);

        // The closest other store is where to send the customer, so the associate's own store, or a
        // store the agent says has none, is not one.
        const nearestStore: IAgentStoreStock | undefined = nearestStoreStock
            && nearestStoreStock.quantity !== 0
            && !isCurrentStore(nearestStoreStock.name, currentStore)
            ? nearestStoreStock
            : undefined;
        if (!currentStoreStock && !nearestStore) {
            return;
        }

        const shownEntry: IAgentProductInventory = { productId: productId };
        if (currentStoreStock) {
            shownEntry.currentStore = currentStoreStock;
        }

        if (nearestStore) {
            shownEntry.nearestStore = nearestStore;
        }

        shown.push(shownEntry);
    });

    return shown;
}

/**
 * Reads one store's stock. A quantity wins over a status; with neither there is nothing to show.
 * @param stock The stock the agent reported for the store.
 * @param isOtherStore True for another store, which must be named. POS names its own store itself.
 * @returns The stock to show, or undefined when there is none.
 */
function readStock(stock: IAgentStoreStock | undefined, isOtherStore: boolean): IAgentStoreStock | undefined {
    if (!stock || typeof stock !== "object") {
        return undefined;
    }

    const shown: IAgentStoreStock = {};
    if (typeof stock.quantity === "number" && isFinite(stock.quantity) && stock.quantity >= 0) {
        shown.quantity = stock.quantity;
    } else {
        const status: string | undefined = readText(stock.status, MAX_STATUS_LENGTH);
        if (!status) {
            return undefined;
        }

        shown.status = status;
    }

    if (isOtherStore) {
        const name: string | undefined = readText(stock.name, MAX_STORE_NAME_LENGTH);
        if (!name) {
            return undefined;
        }

        shown.name = name;
        const distance: string | undefined = readText(stock.distance, MAX_DISTANCE_LENGTH);
        if (distance) {
            shown.distance = distance;
        }
    }

    return shown;
}

function isCurrentStore(name: string | undefined, currentStore: IAgentStoreContext | undefined): boolean {
    if (!name || !currentStore) {
        return false;
    }

    const storeName: string = name.toLowerCase();
    return storeName === (currentStore.name || "").toLowerCase()
        || storeName === (currentStore.number || "").toLowerCase();
}

function readText(value: unknown, maxLength: number): string | undefined {
    if (typeof value !== "string") {
        return undefined;
    }

    const trimmed: string = value.trim();
    if (trimmed.length === 0) {
        return undefined;
    }

    return trimmed.length > maxLength ? `${trimmed.substring(0, maxLength - 1)}\u2026` : trimmed;
}
