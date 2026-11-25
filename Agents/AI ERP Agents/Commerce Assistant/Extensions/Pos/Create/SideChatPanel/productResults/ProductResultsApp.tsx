/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The product cards the agent's curated results are rendered as.
 *
 * Pure presentation. Every product shown here was read from the channel by the POS view controller;
 * this component never talks to POS and never receives anything the agent authored except the
 * recommendation text and the stock it reported, which is labelled as the agent's report. That split
 * is what stops a model being able to put a made-up price on screen.
 */

import * as React from "react";
import {
    Badge,
    Body1,
    Body1Strong,
    Button,
    Caption1,
    Checkbox,
    FluentProvider,
    IdPrefixProvider,
    Spinner,
    Text,
    makeStyles,
    mergeClasses,
    shorthands,
    tokens,
    webLightTheme
} from "@fluentui/react-components";
import {
    CartRegular,
    CheckmarkCircleFilled,
    ImageOffRegular,
    SparkleFilled
} from "@fluentui/react-icons";
import {
    IAgentProductCard,
    IAgentProductFacet,
    IAgentProductFilterRequest,
    IAgentProductFilterSelection,
    IAgentProductInventory
} from "../agentContracts";
import { PANEL_WIDTH, getIsOpen, subscribe } from "../panelState";
import { ProductStock } from "../ProductStock";
import { ProductFacetFilters, focusFirstTag } from "../productFilters/ProductFacetFilters";
import { IProductFilters, useProductFilters } from "../productFilters/useProductFilters";

/** What the product results app needs to render. */
export interface IProductResultsProps {
    products: ReadonlyArray<IAgentProductCard>;
    /** The recommended product, shown first with a badge. */
    bestMatchProductId?: number;
    /** Why it was recommended. Shown on its card only. */
    bestMatchReason?: string;
    headline?: string;
    /** The stock the agent reported, at most one entry per product. Shown on each product's card. */
    inventory?: ReadonlyArray<IAgentProductInventory>;
    /** The associate's store's name, which labels its stock. */
    currentStoreName?: string;
    /** Filter tags for the products: Color, Size and Price, then the other refiners Commerce returns. */
    filterFacets?: ReadonlyArray<IAgentProductFacet>;
    /** The tags selected when the results open, such as those selected in the chat. */
    initialFilterSelection?: IAgentProductFilterSelection;
    isLoading?: boolean;
    /** Set when POS could not read the products. */
    errorMessage?: string;
    /** Opens the product's details page. */
    onProductActivated?: (recordId: number) => void;
    /** Adds the product to the current transaction. Rejects to leave the card in its previous state. */
    onAddToCart?: (recordId: number) => Promise<void>;
    /** Opens the comparison view for the selected products. */
    onCompareRequested?: (recordIds: ReadonlyArray<number>) => void;
    /**
     * Finds which of the products have the selected tags other than prices. Without it, only the tags
     * POS can match from the products shown filter.
     */
    onFilterProducts?: (request: IAgentProductFilterRequest) => Promise<ReadonlyArray<number>>;
}

/**
 * POS sets `body { font-size: 4px }`, which every descendant inherits, so the root resets it before
 * Fluent's em-based sizing lands.
 */
const BASE_FONT_SIZE: string = "14px";

const useStyles = makeStyles({
    root: {
        height: "100%",
        overflowY: "auto",
        fontSize: BASE_FONT_SIZE,
        backgroundColor: tokens.colorNeutralBackground2,
        ...shorthands.padding("12px", "20px", "24px", "20px")
    },

    /* Applied while the chat panel is open. The panel sits over this view rather than reflowing it,
       so without this the last column of cards would be permanently hidden underneath it. */
    rootWithPanel: {
        paddingRight: `calc(${PANEL_WIDTH} + 20px)`
    },

    /* The view title is already in the POS header, so this is only the result count, or how many
       products the tags leave. */
    summary: {
        display: "flex",
        alignItems: "center",
        columnGap: "6px",
        color: tokens.colorNeutralForeground2,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200,
        ...shorthands.margin("0", "0", "12px", "0")
    },

    /* No taller than the count, so the line does not grow when it appears. */
    summaryClear: {
        minWidth: 0,
        ...shorthands.margin("-4px", "0")
    },

    grid: {
        display: "grid",
        gridTemplateColumns: "repeat(auto-fill, minmax(190px, 1fr))",
        gridGap: "12px",
        // Cards in a row match the tallest, so the recommendation strip cannot stagger the grid.
        alignItems: "stretch"
    },

    card: {
        display: "flex",
        flexDirection: "column",
        backgroundColor: tokens.colorNeutralBackground1,
        ...shorthands.borderRadius(tokens.borderRadiusMedium),
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.overflow("hidden"),
        transitionProperty: "box-shadow, border-color",
        transitionDuration: tokens.durationNormal,
        ":hover": {
            ...shorthands.borderColor(tokens.colorNeutralStroke1Hover),
            boxShadow: tokens.shadow8
        },
        ":focus-within": {
            ...shorthands.borderColor(tokens.colorBrandStroke1)
        }
    },

    cardBestMatch: {
        ...shorthands.borderColor(tokens.colorBrandStroke1),
        boxShadow: tokens.shadow4
    },

    /* The whole upper area is one activation target that opens the product. */
    cardMain: {
        display: "flex",
        flexDirection: "column",
        flexGrow: 1,
        ...shorthands.padding("0"),
        ...shorthands.border("none"),
        backgroundColor: "transparent",
        cursor: "pointer",
        textAlign: "left",
        fontFamily: "inherit",
        ":focus-visible": {
            ...shorthands.outline("2px", "solid", tokens.colorStrokeFocus2),
            outlineOffset: "-2px"
        }
    },

    imageWrap: {
        position: "relative",
        width: "100%",
        height: "112px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: tokens.colorNeutralBackground3,
        color: tokens.colorNeutralForeground4,
        ...shorthands.overflow("hidden")
    },

    image: {
        maxWidth: "100%",
        maxHeight: "100%",
        objectFit: "contain"
    },

    badge: {
        position: "absolute",
        top: "6px",
        left: "6px"
    },

    body: {
        display: "flex",
        flexDirection: "column",
        rowGap: "1px",
        flexGrow: 1,
        ...shorthands.padding("8px", "10px", "6px", "10px")
    },

    name: {
        color: tokens.colorNeutralForeground1,
        lineHeight: tokens.lineHeightBase300,
        // Two lines then ellipsis, so a long name cannot push the price out of alignment.
        display: "-webkit-box",
        WebkitLineClamp: 2,
        WebkitBoxOrient: "vertical",
        ...shorthands.overflow("hidden")
    },

    price: {
        color: tokens.colorNeutralForeground1,
        ...shorthands.margin("2px", "0", "0", "0")
    },

    itemId: {
        color: tokens.colorNeutralForeground3
    },

    /* Pushed to the bottom of the card so the button line stays level across the row. */
    reason: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "5px",
        ...shorthands.margin("6px", "0", "0", "0"),
        ...shorthands.padding("5px", "7px"),
        ...shorthands.borderRadius(tokens.borderRadiusSmall),
        backgroundColor: tokens.colorBrandBackground2,
        color: tokens.colorNeutralForeground1,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    reasonIcon: {
        flexShrink: 0,
        color: tokens.colorBrandForeground1,
        marginTop: "1px"
    },

    footer: {
        ...shorthands.padding("0", "10px", "10px", "10px")
    },

    /* Outside the card's button, so it is read on its own, and just above the add button. */
    stock: {
        ...shorthands.padding("0", "10px", "8px", "10px")
    },

    compareChoice: {
        ...shorthands.padding("6px", "8px", "0", "8px")
    },

    addButton: {
        width: "100%"
    },

    added: {
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        columnGap: "6px",
        height: "32px",
        color: tokens.colorPaletteGreenForeground1,
        fontSize: tokens.fontSizeBase200
    },

    message: {
        color: tokens.colorNeutralForeground2
    },

    loading: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px",
        ...shorthands.padding("24px", "0")
    },

    /* Under the result count, above the cards. */
    filters: {
        ...shorthands.margin("0", "0", "12px", "0")
    },

    compareBar: {
        position: "sticky",
        bottom: "0",
        zIndex: 1,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        columnGap: "12px",
        rowGap: "8px",
        flexWrap: "wrap",
        backgroundColor: tokens.colorNeutralBackground1,
        boxShadow: tokens.shadow8,
        ...shorthands.margin("16px", "-8px", "-12px", "-8px"),
        ...shorthands.padding("10px", "12px"),
        ...shorthands.borderRadius(tokens.borderRadiusMedium)
    },

    compareActions: {
        display: "flex",
        alignItems: "center",
        columnGap: "8px"
    }
});

/**
 * Orders the products so the recommended one is first, leaving the rest in the order the agent chose.
 * @param products The products.
 * @param bestMatchProductId The recommended product.
 * @returns The ordered products.
 */
function orderProducts(
    products: ReadonlyArray<IAgentProductCard>,
    bestMatchProductId?: number
): ReadonlyArray<IAgentProductCard> {
    if (bestMatchProductId === undefined) {
        return products;
    }

    const best = products.filter((p) => p.recordId === bestMatchProductId);
    const rest = products.filter((p) => p.recordId !== bestMatchProductId);

    return [...best, ...rest];
}

/** How the add-to-cart button on one card is currently behaving. */
type AddState = "idle" | "adding" | "added";

/**
 * One product card.
 * @param props The card properties.
 * @returns The rendered card.
 */
const ProductCard: React.FC<{
    product: IAgentProductCard;
    isBestMatch: boolean;
    bestMatchReason?: string;
    inventory?: IAgentProductInventory;
    currentStoreName?: string;
    isSelected: boolean;
    compareDisabled: boolean;
    onSelectionChanged?: (recordId: number, selected: boolean) => void;
    onActivated?: (recordId: number) => void;
    onAddToCart?: (recordId: number) => Promise<void>;
}> = (props) => {
    const styles = useStyles();
    const [imageFailed, setImageFailed] = React.useState<boolean>(false);
    const [addState, setAddState] = React.useState<AddState>("idle");
    const isMountedRef = React.useRef<boolean>(true);

    React.useEffect(() => {
        return () => {
            isMountedRef.current = false;
        };
    }, []);

    const activate = React.useCallback((): void => {
        if (props.onActivated) {
            props.onActivated(props.product.recordId);
        }
    }, [props]);

    const addToCart = React.useCallback((): void => {
        if (!props.onAddToCart || addState !== "idle") {
            return;
        }

        setAddState("adding");
        props.onAddToCart(props.product.recordId)
            .then(() => {
                if (isMountedRef.current) {
                    setAddState("added");
                }
            })
            .catch(() => {
                // POS surfaces its own error; the card just returns to a state the operator can retry from.
                if (isMountedRef.current) {
                    setAddState("idle");
                }
            });
    }, [props, addState]);

    const dimensionLabel: string = props.product.dimensionValues?.join(" / ") ?? "";
    const addLabel: string = dimensionLabel.length > 0 ? `Add ${dimensionLabel} to sale` : "Add to sale";

    return (
        <div className={mergeClasses(styles.card, props.isBestMatch && styles.cardBestMatch)}>
            {props.onSelectionChanged && (
                <div className={styles.compareChoice}>
                    <Checkbox
                        checked={props.isSelected}
                        disabled={props.compareDisabled && !props.isSelected}
                        label="Compare"
                        aria-label={`Compare ${props.product.name}`}
                        onChange={(_event, data) => {
                            props.onSelectionChanged?.(props.product.recordId, data.checked === true);
                        }}
                    />
                </div>
            )}

            {/* A button rather than a div: opening the product is a real activation, so it should be
                reachable by keyboard and announced as actionable without extra ARIA. */}
            <button
                type="button"
                className={styles.cardMain}
                onClick={activate}
                aria-label={`${props.product.name}, ${props.product.priceText ?? "price unavailable"}. Open product details.`}
            >
                <div className={styles.imageWrap}>
                    {props.product.imageUrl && !imageFailed ? (
                        <img
                            className={styles.image}
                            src={props.product.imageUrl}
                            alt=""
                            onError={() => setImageFailed(true)}
                        />
                    ) : (
                        <ImageOffRegular fontSize={28} aria-hidden="true" />
                    )}

                    {props.isBestMatch && (
                        <Badge className={styles.badge} appearance="filled" color="brand" icon={<SparkleFilled />}>
                            Best match
                        </Badge>
                    )}
                </div>

                <div className={styles.body}>
                    <Body1Strong className={styles.name} title={props.product.name}>
                        {props.product.name}
                    </Body1Strong>

                    {props.product.priceText && (
                        <Body1Strong className={styles.price}>{props.product.priceText}</Body1Strong>
                    )}

                    {props.product.itemId && <Caption1 className={styles.itemId}>{props.product.itemId}</Caption1>}

                    {props.isBestMatch && props.bestMatchReason && (
                        <div className={styles.reason}>
                            <SparkleFilled className={styles.reasonIcon} />
                            <span>{props.bestMatchReason}</span>
                        </div>
                    )}
                </div>
            </button>

            <ProductStock
                className={styles.stock}
                inventory={props.inventory}
                currentStoreName={props.currentStoreName}
            />

            {props.onAddToCart && (
                <div className={styles.footer}>
                    {addState === "added" ? (
                        <div className={styles.added} role="status">
                            <CheckmarkCircleFilled />
                            <span>Added</span>
                        </div>
                    ) : (
                        <Button
                            className={styles.addButton}
                            appearance={props.isBestMatch ? "primary" : "secondary"}
                            icon={addState === "adding" ? <Spinner size="tiny" /> : <CartRegular />}
                            disabled={addState === "adding"}
                            onClick={addToCart}
                        >
                            {addState === "adding" ? "Adding\u2026" : addLabel}
                        </Button>
                    )}
                </div>
            )}
        </div>
    );
};

/**
 * The curated product results.
 * @param props The results.
 * @returns The rendered results.
 */
export const ProductResultsApp: React.FC<IProductResultsProps> = (props) => {
    const styles = useStyles();
    // The tags narrow the products here, in POS. The agent is not asked again.
    const filters: IProductFilters = useProductFilters(
        props.products,
        props.filterFacets,
        props.onFilterProducts,
        props.initialFilterSelection);
    const ordered: ReadonlyArray<IAgentProductCard> = React.useMemo(
        () => orderProducts(filters.products, props.bestMatchProductId),
        [filters.products, props.bestMatchProductId]);
    const filtersRef = React.useRef<HTMLDivElement>(null);
    const [selectedIds, setSelectedIds] = React.useState<ReadonlyArray<number>>([]);
    const maximumComparedProducts = 4;

    // The chat panel is fixed to the right edge and overlays this view, so the layout has to reserve
    // its width while it is open. Both live in this bundle, so the state is read directly rather than
    // routed through the POS host.
    const [isPanelOpen, setIsPanelOpen] = React.useState<boolean>(getIsOpen());
    React.useEffect(() => {
        return subscribe(setIsPanelOpen);
    }, []);

    // A product the tags take off screen leaves the selection, rather than being compared unseen.
    React.useEffect(() => {
        const availableIds = new Set(ordered.map((product: IAgentProductCard) => product.recordId));
        setSelectedIds((current: ReadonlyArray<number>) => current.every((id: number) => availableIds.has(id))
            ? current
            : current.filter((id: number) => availableIds.has(id)));
    }, [ordered]);

    const updateSelection = React.useCallback((recordId: number, selected: boolean): void => {
        setSelectedIds((current: ReadonlyArray<number>) => {
            if (!selected) {
                return current.filter((id: number) => id !== recordId);
            }

            if (current.indexOf(recordId) >= 0 || current.length >= maximumComparedProducts) {
                return current;
            }

            return [...current, recordId];
        });
    }, []);

    const compareSelected = React.useCallback((): void => {
        if (selectedIds.length >= 2 && props.onCompareRequested) {
            props.onCompareRequested(selectedIds);
        }
    }, [props, selectedIds]);

    const compareAll = React.useCallback((): void => {
        if (ordered.length >= 2 && ordered.length <= maximumComparedProducts && props.onCompareRequested) {
            props.onCompareRequested(ordered.map((product: IAgentProductCard) => product.recordId));
        }
    }, [ordered, props]);

    const inventoryByProductId: Map<number, IAgentProductInventory> = new Map<number, IAgentProductInventory>();
    (props.inventory ?? []).forEach((entry: IAgentProductInventory) => {
        if (!inventoryByProductId.has(entry.productId)) {
            inventoryByProductId.set(entry.productId, entry);
        }
    });

    const totalCount: number = props.products.length;
    const totalText: string = `${totalCount} ${totalCount === 1 ? "product" : "products"} selected for you`;
    const countText: string = filters.hasSelection ? `Showing ${ordered.length} of ${totalText}` : totalText;
    const summaryText: string = filters.isFiltering
        ? "Filtering products\u2026"
        : filters.note
            ? `${countText}. ${filters.note}`
            : countText;

    // Clear filters goes away with the tags it clears, so focus moves to the first tag before it does.
    const clearFilters = (): void => {
        focusFirstTag(filtersRef.current);
        filters.clear();
    };

    return (
        <div className={mergeClasses(styles.root, isPanelOpen && styles.rootWithPanel)}>
            {props.isLoading ? (
                <div className={styles.loading}>
                    <Spinner size="tiny" />
                    <Text className={styles.message}>Loading products{"\u2026"}</Text>
                </div>
            ) : props.errorMessage ? (
                <Text className={styles.message}>{props.errorMessage}</Text>
            ) : props.products.length === 0 ? (
                <Text className={styles.message}>No products were available to show.</Text>
            ) : (
                <>
                    <div className={styles.summary}>
                        {filters.isFiltering ? <Spinner size="extra-tiny" aria-hidden="true" /> : <SparkleFilled />}
                        <Caption1 role="status">{summaryText}</Caption1>
                        {filters.hasSelection && (
                            <Button
                                className={styles.summaryClear}
                                appearance="transparent"
                                size="small"
                                onClick={clearFilters}
                            >
                                Clear filters
                            </Button>
                        )}
                    </div>

                    <ProductFacetFilters
                        ref={filtersRef}
                        className={styles.filters}
                        facets={filters.facets}
                        selection={filters.selection}
                        onToggle={filters.toggle}
                        size="medium"
                    />

                    {ordered.length === 0 ? (
                        <Text className={styles.message}>No products match these filters.</Text>
                    ) : (
                        <div className={styles.grid}>
                            {ordered.map((product: IAgentProductCard) => (
                                <ProductCard
                                    key={product.recordId}
                                    product={product}
                                    isBestMatch={product.recordId === props.bestMatchProductId}
                                    bestMatchReason={props.bestMatchReason}
                                    inventory={inventoryByProductId.get(product.recordId)}
                                    currentStoreName={props.currentStoreName}
                                    isSelected={selectedIds.indexOf(product.recordId) >= 0}
                                    compareDisabled={selectedIds.length >= maximumComparedProducts}
                                    onSelectionChanged={props.onCompareRequested ? updateSelection : undefined}
                                    onActivated={props.onProductActivated}
                                    onAddToCart={props.onAddToCart}
                                />
                            ))}
                        </div>
                    )}

                    {props.onCompareRequested && ordered.length >= 2 && (
                        <div className={styles.compareBar}>
                            <Text aria-live="polite">
                                {selectedIds.length === 0
                                    ? "Select 2 to 4 products to compare."
                                    : `${selectedIds.length} of ${maximumComparedProducts} products selected.`}
                            </Text>

                            <div className={styles.compareActions}>
                                {ordered.length <= maximumComparedProducts && (
                                    <Button appearance="subtle" onClick={compareAll}>
                                        Compare all {ordered.length}
                                    </Button>
                                )}

                                <Button
                                    appearance="primary"
                                    disabled={selectedIds.length < 2}
                                    onClick={compareSelected}
                                >
                                    Compare ({selectedIds.length})
                                </Button>
                            </div>
                        </div>
                    )}
                </>
            )}
        </div>
    );
};

/**
 * Prefix for every id Fluent generates for this app.
 *
 * Deliberately different from the side panel's prefix. Both apps ship in the same bundle and can be
 * on screen at once, and Fluent derives the id of the `<style>` element it publishes its theme into
 * from this value — sharing it would make one FluentProvider adopt the other's element and lose every
 * design token.
 * @see https://aka.ms/fluentui-conflicting-ids
 */
export const PRODUCT_RESULTS_ID_PREFIX: string = "contoso-agent-products-";

/**
 * The themed root, so the host only has to render one element.
 * @param props The results.
 * @returns The rendered app.
 */
export const ProductResultsRoot: React.FC<IProductResultsProps> = (props) => {
    return (
        <IdPrefixProvider value={PRODUCT_RESULTS_ID_PREFIX}>
            <FluentProvider theme={webLightTheme} style={{ height: "100%" }}>
                <ProductResultsApp {...props} />
            </FluentProvider>
        </IdPrefixProvider>
    );
};
