/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import * as React from "react";
import {
    Badge,
    Button,
    FluentProvider,
    IdPrefixProvider,
    Switch,
    Text,
    makeStyles,
    mergeClasses,
    shorthands,
    tokens,
    webLightTheme
} from "@fluentui/react-components";
import { DismissRegular, ImageOffRegular, SparkleFilled } from "@fluentui/react-icons";
import { IAgentProductCard } from "../agentContracts";
import { PANEL_WIDTH, getIsOpen, subscribe } from "../panelState";

export interface IProductCompareProps {
    products: ReadonlyArray<IAgentProductCard>;
    bestMatchProductId?: number;
    bestMatchReason?: string;
    onProductActivated?: (recordId: number) => void;
}

interface IComparisonRow {
    label: string;
    value: (product: IAgentProductCard) => string;
}

const useStyles = makeStyles({
    root: {
        height: "100%",
        overflow: "auto",
        fontSize: "14px",
        backgroundColor: tokens.colorNeutralBackground2,
        ...shorthands.padding("12px", "20px", "24px", "20px")
    },

    rootWithPanel: {
        paddingRight: `calc(${PANEL_WIDTH} + 20px)`
    },

    toolbar: {
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        columnGap: "12px",
        rowGap: "8px",
        flexWrap: "wrap",
        ...shorthands.margin("0", "0", "12px", "0")
    },

    tableWrap: {
        overflowX: "auto",
        backgroundColor: tokens.colorNeutralBackground1,
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderRadius(tokens.borderRadiusMedium)
    },

    table: {
        width: "100%",
        minWidth: "640px",
        borderCollapse: "collapse"
    },

    attributeHeader: {
        width: "150px",
        minWidth: "150px",
        textAlign: "left",
        verticalAlign: "top",
        color: tokens.colorNeutralForeground2,
        backgroundColor: tokens.colorNeutralBackground3,
        ...shorthands.padding("10px"),
        ...shorthands.borderBottom("1px", "solid", tokens.colorNeutralStroke2)
    },

    productHeader: {
        minWidth: "190px",
        textAlign: "left",
        verticalAlign: "top",
        ...shorthands.padding("10px"),
        ...shorthands.borderLeft("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderBottom("1px", "solid", tokens.colorNeutralStroke2)
    },

    productHeaderTop: {
        display: "flex",
        justifyContent: "space-between",
        alignItems: "flex-start",
        columnGap: "8px"
    },

    productButton: {
        display: "flex",
        flexDirection: "column",
        alignItems: "flex-start",
        rowGap: "6px",
        minWidth: "0",
        color: tokens.colorNeutralForeground1,
        backgroundColor: "transparent",
        ...shorthands.padding("0"),
        ...shorthands.border("none"),
        cursor: "pointer",
        textAlign: "left",
        fontFamily: "inherit",
        ":focus-visible": {
            ...shorthands.outline("2px", "solid", tokens.colorStrokeFocus2),
            outlineOffset: "2px"
        }
    },

    imageWrap: {
        width: "96px",
        height: "72px",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: tokens.colorNeutralBackground3,
        color: tokens.colorNeutralForeground4,
        ...shorthands.overflow("hidden"),
        ...shorthands.borderRadius(tokens.borderRadiusSmall)
    },

    image: {
        maxWidth: "100%",
        maxHeight: "100%",
        objectFit: "contain"
    },

    name: {
        fontWeight: tokens.fontWeightSemibold,
        lineHeight: tokens.lineHeightBase300
    },

    bestMatch: {
        ...shorthands.margin("4px", "0", "0", "0")
    },

    valueCell: {
        verticalAlign: "top",
        whiteSpace: "pre-wrap",
        ...shorthands.padding("10px"),
        ...shorthands.borderLeft("1px", "solid", tokens.colorNeutralStroke2),
        ...shorthands.borderBottom("1px", "solid", tokens.colorNeutralStroke2)
    },

    message: {
        color: tokens.colorNeutralForeground2
    }
});

const comparisonRows: ReadonlyArray<IComparisonRow> = [
    { label: "Price", value: (product: IAgentProductCard): string => product.priceText ?? "Unavailable" },
    { label: "Item ID", value: (product: IAgentProductCard): string => product.itemId ?? "Unavailable" },
    { label: "Product number", value: (product: IAgentProductCard): string => product.productNumber ?? "Unavailable" },
    { label: "Unit", value: (product: IAgentProductCard): string => product.unitOfMeasure ?? "Unavailable" },
    {
        label: "Variant",
        value: (product: IAgentProductCard): string =>
            product.dimensionValues && product.dimensionValues.length > 0
                ? product.dimensionValues.join(", ")
                : "Not specified"
    },
    { label: "Description", value: (product: IAgentProductCard): string => product.description ?? "Unavailable" }
];

function hasDifferentValues(row: IComparisonRow, products: ReadonlyArray<IAgentProductCard>): boolean {
    const values = new Set(products.map((product: IAgentProductCard) => row.value(product)));
    return values.size > 1;
}

function orderProducts(
    products: ReadonlyArray<IAgentProductCard>,
    bestMatchProductId?: number
): ReadonlyArray<IAgentProductCard> {
    if (bestMatchProductId === undefined) {
        return products;
    }

    return [
        ...products.filter((product: IAgentProductCard) => product.recordId === bestMatchProductId),
        ...products.filter((product: IAgentProductCard) => product.recordId !== bestMatchProductId)
    ];
}

const ProductCompareApp: React.FC<IProductCompareProps> = (props) => {
    const styles = useStyles();
    const [products, setProducts] = React.useState<ReadonlyArray<IAgentProductCard>>(
        orderProducts(props.products, props.bestMatchProductId));
    const [differencesOnly, setDifferencesOnly] = React.useState<boolean>(true);
    const [failedImages, setFailedImages] = React.useState<ReadonlySet<number>>(new Set<number>());
    const [isPanelOpen, setIsPanelOpen] = React.useState<boolean>(getIsOpen());

    React.useEffect(() => subscribe(setIsPanelOpen), []);
    React.useEffect(
        () => setProducts(orderProducts(props.products, props.bestMatchProductId)),
        [props.products, props.bestMatchProductId]);

    const rows = differencesOnly
        ? comparisonRows.filter((row: IComparisonRow) => hasDifferentValues(row, products))
        : comparisonRows;

    const removeProduct = React.useCallback((recordId: number): void => {
        setProducts((current: ReadonlyArray<IAgentProductCard>) => {
            return current.length > 2
                ? current.filter((product: IAgentProductCard) => product.recordId !== recordId)
                : current;
        });
    }, []);

    return (
        <div className={mergeClasses(styles.root, isPanelOpen && styles.rootWithPanel)}>
            {products.length < 2 ? (
                <Text className={styles.message}>Select at least two products to compare.</Text>
            ) : (
                <>
                    <div className={styles.toolbar}>
                        <Text>{products.length} products</Text>
                        <Switch
                            checked={differencesOnly}
                            label="Show differences only"
                            onChange={(_event, data) => setDifferencesOnly(data.checked)}
                        />
                    </div>

                    <div className={styles.tableWrap}>
                        <table className={styles.table}>
                            <thead>
                                <tr>
                                    <th className={styles.attributeHeader} scope="col">Attribute</th>
                                    {products.map((product: IAgentProductCard) => (
                                        <th className={styles.productHeader} scope="col" key={product.recordId}>
                                            <div className={styles.productHeaderTop}>
                                                <button
                                                    type="button"
                                                    className={styles.productButton}
                                                    onClick={() => props.onProductActivated?.(product.recordId)}
                                                    aria-label={`Open details for ${product.name}`}
                                                >
                                                    <div className={styles.imageWrap}>
                                                        {product.imageUrl && !failedImages.has(product.recordId) ? (
                                                            <img
                                                                className={styles.image}
                                                                src={product.imageUrl}
                                                                alt=""
                                                                onError={() => {
                                                                    setFailedImages((current: ReadonlySet<number>) => {
                                                                        const next = new Set(current);
                                                                        next.add(product.recordId);
                                                                        return next;
                                                                    });
                                                                }}
                                                            />
                                                        ) : (
                                                            <ImageOffRegular fontSize={28} aria-hidden="true" />
                                                        )}
                                                    </div>
                                                    <span className={styles.name}>{product.name}</span>
                                                </button>

                                                <Button
                                                    appearance="subtle"
                                                    icon={<DismissRegular />}
                                                    disabled={products.length <= 2}
                                                    aria-label={`Remove ${product.name} from comparison`}
                                                    onClick={() => removeProduct(product.recordId)}
                                                />
                                            </div>

                                            {product.recordId === props.bestMatchProductId && (
                                                <Badge
                                                    className={styles.bestMatch}
                                                    appearance="filled"
                                                    color="brand"
                                                    icon={<SparkleFilled />}
                                                >
                                                    Best match
                                                </Badge>
                                            )}
                                        </th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody>
                                {rows.map((row: IComparisonRow) => (
                                    <tr key={row.label}>
                                        <th className={styles.attributeHeader} scope="row">{row.label}</th>
                                        {products.map((product: IAgentProductCard) => (
                                            <td className={styles.valueCell} key={product.recordId}>
                                                {row.value(product)}
                                            </td>
                                        ))}
                                    </tr>
                                ))}
                                {props.bestMatchReason && props.bestMatchProductId && (
                                    <tr>
                                        <th className={styles.attributeHeader} scope="row">Recommendation</th>
                                        {products.map((product: IAgentProductCard) => (
                                            <td className={styles.valueCell} key={product.recordId}>
                                                {product.recordId === props.bestMatchProductId
                                                    ? props.bestMatchReason
                                                    : "\u2014"}
                                            </td>
                                        ))}
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                </>
            )}
        </div>
    );
};

export const PRODUCT_COMPARE_ID_PREFIX: string = "contoso-agent-product-compare-";

export const ProductCompareRoot: React.FC<IProductCompareProps> = (props) => {
    return (
        <IdPrefixProvider value={PRODUCT_COMPARE_ID_PREFIX}>
            <FluentProvider theme={webLightTheme} style={{ height: "100%" }}>
                <ProductCompareApp {...props} />
            </FluentProvider>
        </IdPrefixProvider>
    );
};
