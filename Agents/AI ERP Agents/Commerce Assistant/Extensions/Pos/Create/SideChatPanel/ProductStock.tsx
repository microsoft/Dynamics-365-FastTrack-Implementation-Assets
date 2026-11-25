/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * A recommended product's stock at the associate's store and at the closest other store that has it.
 *
 * Shared by the chat's product preview, which shows it as badges, and the full results view, which
 * shows it as rows. The figures are what the agent read with the Commerce inventory tools when it
 * answered.
 */

import * as React from "react";
import { makeStyles, mergeClasses, shorthands, tokens } from "@fluentui/react-components";
import { BuildingShopRegular, LocationRegular } from "@fluentui/react-icons";
import { IAgentProductInventory, IAgentStoreStock } from "./agentContracts";

/** Shown on hover, because stock moves and these figures are not refreshed. */
export const STOCK_TOOLTIP: string = "Stock as Copilot checked it when it answered; it may have changed since.";

/** What the stock rows need to render. */
export interface IProductStockProps {
    /** The stock the agent reported for this product. Nothing renders without it. */
    inventory?: IAgentProductInventory;
    /** The associate's store's name. "This store" when POS could not read it. */
    currentStoreName?: string;
    /**
     * "rows" (the default) gives each store a labelled row with an icon. "badges" gives each store a
     * short badge, such as "Houston has 4", for the chat's compact product rows.
     */
    variant?: "rows" | "badges";
    className?: string;
}

const useStyles = makeStyles({
    list: {
        display: "flex",
        flexDirection: "column",
        rowGap: "2px",
        listStyleType: "none",
        ...shorthands.margin("0"),
        ...shorthands.padding("0"),
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    row: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "4px",
        minWidth: 0
    },

    icon: {
        flexShrink: 0,
        marginTop: "1px",
        fontSize: "14px",
        color: tokens.colorNeutralForeground3
    },

    text: {
        minWidth: 0,
        overflowWrap: "anywhere"
    },

    store: {
        color: tokens.colorNeutralForeground1,
        fontWeight: tokens.fontWeightSemibold
    },

    /* A figure such as "12 available" or "1,889 mi" never splits across lines. */
    value: {
        whiteSpace: "nowrap"
    },

    outOfStock: {
        color: tokens.colorPaletteRedForeground1,
        fontWeight: tokens.fontWeightSemibold
    },

    badges: {
        display: "flex",
        flexWrap: "wrap",
        columnGap: "4px",
        rowGap: "4px",
        minWidth: 0,
        listStyleType: "none",
        ...shorthands.margin("0"),
        ...shorthands.padding("0")
    },

    /* A small tint badge. It grows to a second line rather than overflow when a store's name is long. */
    badge: {
        boxSizing: "border-box",
        maxWidth: "100%",
        minHeight: "16px",
        ...shorthands.padding("0", "4px"),
        ...shorthands.border("1px", "solid", tokens.colorBrandStroke2),
        ...shorthands.borderRadius("8px"),
        backgroundColor: tokens.colorBrandBackground2,
        color: tokens.colorBrandForeground2,
        fontSize: tokens.fontSizeBase100,
        fontWeight: tokens.fontWeightSemibold,
        lineHeight: tokens.lineHeightBase100,
        overflowWrap: "anywhere"
    },

    /* Another store's stock is secondary to this store's, so it is neutral. */
    badgeOtherStore: {
        ...shorthands.borderColor(tokens.colorNeutralStroke2),
        backgroundColor: tokens.colorNeutralBackground3,
        color: tokens.colorNeutralForeground2
    },

    badgeOutOfStock: {
        ...shorthands.borderColor(tokens.colorPaletteRedBorder1),
        backgroundColor: tokens.colorPaletteRedBackground1,
        color: tokens.colorPaletteRedForeground1
    }
});

/**
 * Says how much of the product a store has.
 * @param stock The store's stock.
 * @returns The text, for example "4 available", and whether the store has none.
 */
function describeStock(stock: IAgentStoreStock): { text: string; isOutOfStock: boolean } {
    if (typeof stock.quantity === "number") {
        if (stock.quantity <= 0) {
            return { text: "Out of stock", isOutOfStock: true };
        }

        return { text: `${Math.round(stock.quantity * 100) / 100} available`, isOutOfStock: false };
    }

    return { text: stock.status ?? "", isOutOfStock: false };
}

/**
 * Says in a few words how much of the product a store has, for a badge that starts with the store.
 * @param stock The store's stock.
 * @param storeName The store's name. Undefined for the associate's store when POS could not read it.
 * @returns The text, for example "Houston has 4", and whether the store has none.
 */
function describeStockBriefly(stock: IAgentStoreStock, storeName: string | undefined): { text: string; isOutOfStock: boolean } {
    if (typeof stock.quantity === "number") {
        if (stock.quantity <= 0) {
            return { text: `Out of stock at ${storeName ?? "this store"}`, isOutOfStock: true };
        }

        return { text: `${storeName ?? "This store"} has ${Math.round(stock.quantity * 100) / 100}`, isOutOfStock: false };
    }

    return { text: stock.status ? `${storeName ?? "This store"}: ${stock.status}` : "", isOutOfStock: false };
}

/**
 * The product's stock, one row or badge per store. Renders nothing when there is no stock to show.
 * @param props The stock, the associate's store's name, and how to show them.
 * @returns The rendered rows or badges, or null.
 */
export const ProductStock: React.FC<IProductStockProps> = (props) => {
    const styles = useStyles();
    const currentStore: IAgentStoreStock | undefined = props.inventory?.currentStore;
    const nearestStore: IAgentStoreStock | undefined = props.inventory?.nearestStore?.name
        ? props.inventory.nearestStore
        : undefined;
    const current = currentStore ? describeStock(currentStore) : undefined;
    const nearest = nearestStore ? describeStock(nearestStore) : undefined;
    const hasCurrent: boolean = !!current && current.text.length > 0;
    const hasNearest: boolean = !!nearest && nearest.text.length > 0;
    if (!hasCurrent && !hasNearest) {
        return null;
    }

    const currentStoreName: string = props.currentStoreName?.trim() ?? "";

    if (props.variant === "badges") {
        const currentBadge = hasCurrent && currentStore
            ? describeStockBriefly(currentStore, currentStoreName.length > 0 ? currentStoreName : undefined)
            : undefined;
        const nearestBadge = hasNearest && nearestStore ? describeStockBriefly(nearestStore, nearestStore.name) : undefined;

        return (
            <ul className={mergeClasses(styles.badges, props.className)} aria-label="Stock" title={STOCK_TOOLTIP}>
                {currentBadge && (
                    <li className={mergeClasses(styles.badge, currentBadge.isOutOfStock && styles.badgeOutOfStock)}>
                        {currentBadge.text}
                    </li>
                )}

                {nearestBadge && nearestStore && (
                    <li
                        className={mergeClasses(
                            styles.badge,
                            styles.badgeOtherStore,
                            nearestBadge.isOutOfStock && styles.badgeOutOfStock
                        )}
                    >
                        {nearestBadge.text}
                        {nearestStore.distance && (
                            <>
                                {" \u00b7 "}
                                <span className={styles.value}>{nearestStore.distance}</span>
                            </>
                        )}
                    </li>
                )}
            </ul>
        );
    }

    return (
        <ul className={mergeClasses(styles.list, props.className)} aria-label="Stock" title={STOCK_TOOLTIP}>
            {hasCurrent && current && (
                <li className={styles.row}>
                    <BuildingShopRegular className={styles.icon} aria-hidden="true" />
                    <span className={styles.text}>
                        {currentStoreName.length > 0 ? (
                            <>
                                <span className={styles.store}>{currentStoreName}</span> (this store)
                            </>
                        ) : (
                            <span className={styles.store}>This store</span>
                        )}
                        {" \u00b7 "}
                        <span className={mergeClasses(styles.value, current.isOutOfStock && styles.outOfStock)}>
                            {current.text}
                        </span>
                    </span>
                </li>
            )}

            {hasNearest && nearest && nearestStore && (
                <li className={styles.row}>
                    <LocationRegular className={styles.icon} aria-hidden="true" />
                    <span className={styles.text}>
                        <span className={styles.store}>{nearestStore.name}</span> (nearest)
                        {" \u00b7 "}
                        <span className={mergeClasses(styles.value, nearest.isOutOfStock && styles.outOfStock)}>
                            {nearest.text}
                        </span>
                        {nearestStore.distance && (
                            <>
                                {" \u00b7 "}
                                <span className={styles.value}>{nearestStore.distance}</span>
                            </>
                        )}
                    </span>
                </li>
            )}
        </ul>
    );
};
