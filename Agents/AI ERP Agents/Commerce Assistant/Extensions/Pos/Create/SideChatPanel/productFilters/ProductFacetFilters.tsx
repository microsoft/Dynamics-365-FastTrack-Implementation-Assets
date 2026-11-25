/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The filter tags on recommended products: one row per filter POS built, such as Color, Size, Price,
 * Rating or Category, named, with its tags.
 *
 * Shared by the chat's product preview and the full results view. A selected tag is filled and
 * checked, and is cleared when tapped again; in a row that takes one tag at a time, tapping another
 * tag replaces it. A row every product already matches, such as the size the associate asked for,
 * shows one filled tag with a lock, which cannot be cleared.
 */

import * as React from "react";
import {
    InteractionTag,
    InteractionTagPrimary,
    Tag,
    TagGroup,
    makeStyles,
    mergeClasses,
    shorthands,
    tokens,
    useId
} from "@fluentui/react-components";
import { CheckmarkRegular, LockClosedRegular } from "@fluentui/react-icons";
import {
    IAgentProductFacet,
    IAgentProductFacetValue,
    IAgentProductFilterSelection
} from "../agentContracts";
import { getLockedValue, getSelectedKeys } from "./productFilterMatching";

/** What the tags need to render. */
export interface IProductFacetFiltersProps {
    /** The rows to show. Nothing renders when there are none. */
    facets: ReadonlyArray<IAgentProductFacet>;
    selection: IAgentProductFilterSelection;
    /** Called with the row's key and the tag's key when the associate taps a tag that is not locked. */
    onToggle: (facetKey: string, key: string) => void;
    /** "small" for the chat's compact preview, "medium" for the full results view. */
    size?: "small" | "medium";
    /** True to keep each row on one line that scrolls sideways, as the narrow chat needs. */
    scrollRows?: boolean;
    className?: string;
}

const useStyles = makeStyles({
    root: {
        display: "flex",
        flexDirection: "column",
        rowGap: "8px",
        minWidth: 0
    },

    row: {
        display: "flex",
        alignItems: "flex-start",
        columnGap: "8px",
        minWidth: 0
    },

    /* As tall as a tag, so the name lines up with the first line of tags. A long name is cut short,
       and reads in full when hovered and to assistive technology. */
    rowLabel: {
        flexShrink: 0,
        display: "flex",
        alignItems: "center",
        minWidth: "40px",
        maxWidth: "96px",
        minHeight: "24px",
        color: tokens.colorNeutralForeground3,
        fontSize: tokens.fontSizeBase200,
        lineHeight: tokens.lineHeightBase200
    },

    rowLabelMedium: {
        minWidth: "48px",
        maxWidth: "140px",
        minHeight: "32px",
        fontSize: tokens.fontSizeBase300,
        lineHeight: tokens.lineHeightBase300
    },

    rowLabelText: {
        minWidth: 0,
        ...shorthands.overflow("hidden"),
        textOverflow: "ellipsis",
        whiteSpace: "nowrap"
    },

    tags: {
        display: "flex",
        flexWrap: "wrap",
        alignItems: "center",
        columnGap: "6px",
        rowGap: "6px",
        flexGrow: 1,
        minWidth: 0
    },

    /* One line that scrolls sideways. The padding keeps the focus outline of the end tags in view,
       and the margin takes it back out of the layout. */
    tagsScrolled: {
        flexWrap: "nowrap",
        overflowX: "auto",
        ...shorthands.padding("3px"),
        ...shorthands.margin("-3px"),
        scrollbarWidth: "thin",
        "> *": {
            flexShrink: 0
        }
    },

    /* Fluent drops a tag's own left padding when it has media, so the media brings its own. */
    media: {
        display: "inline-flex",
        alignItems: "center",
        columnGap: "3px",
        paddingLeft: "5px"
    },

    mediaMedium: {
        paddingLeft: "7px"
    },

    icon: {
        fontSize: "12px"
    },

    iconMedium: {
        fontSize: "16px"
    },

    /* Shows the colour itself, even in high contrast, where it is the point of the tag. */
    swatch: {
        flexShrink: 0,
        width: "12px",
        height: "12px",
        boxSizing: "border-box",
        ...shorthands.borderRadius(tokens.borderRadiusCircular),
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke1),
        forcedColorAdjust: "none"
    },

    /* Looks like a selected tag. */
    locked: {
        backgroundColor: tokens.colorBrandBackground,
        color: tokens.colorNeutralForegroundOnBrand,
        "@media (forced-colors: active)": {
            forcedColorAdjust: "none",
            backgroundColor: "Highlight",
            color: "HighlightText"
        }
    },

    visuallyHidden: {
        position: "absolute",
        width: "1px",
        height: "1px",
        ...shorthands.margin("-1px"),
        ...shorthands.padding("0"),
        ...shorthands.overflow("hidden"),
        ...shorthands.borderStyle("none"),
        clipPath: "inset(50%)",
        whiteSpace: "nowrap"
    }
});

/**
 * Moves focus to the first tag the associate can tap, such as before clearing the tags removes the
 * control that had it.
 * @param root The tags' root.
 * @returns True when a tag took focus.
 */
export function focusFirstTag(root: HTMLElement | null): boolean {
    const tag: HTMLButtonElement | null = root ? root.querySelector("button") : null;
    if (!tag) {
        return false;
    }

    tag.focus();
    return true;
}

/**
 * Renders the rows of tags.
 * @param props The rows, the tags selected and what to do when one is tapped.
 * @returns The rows, or nothing when there are none.
 */
export const ProductFacetFilters = React.forwardRef<HTMLDivElement, IProductFacetFiltersProps>((props, ref) => {
    const styles = useStyles();
    const idPrefix: string = useId("product-filters-");
    const size: "small" | "medium" = props.size ?? "small";
    const isMedium: boolean = size === "medium";
    const { onToggle } = props;

    if (props.facets.length === 0) {
        return null;
    }

    const mediaClassName: string = mergeClasses(styles.media, isMedium && styles.mediaMedium);
    const iconClassName: string = mergeClasses(styles.icon, isMedium && styles.iconMedium);
    const renderSwatch = (value: IAgentProductFacetValue): React.ReactElement | null => value.swatchColor
        ? <span className={styles.swatch} style={{ backgroundColor: value.swatchColor }} aria-hidden="true" />
        : null;

    return (
        <div ref={ref} className={mergeClasses(styles.root, props.className)} role="group" aria-label="Filters">
            {props.facets.map((facet: IAgentProductFacet, index: number) => {
                // Keys may hold any character Commerce uses in a name, so the label's id uses the row's position.
                const labelId: string = `${idPrefix}-row-${index}`;
                const locked: IAgentProductFacetValue | undefined = getLockedValue(facet);
                const selected: ReadonlyArray<string> = getSelectedKeys(props.selection, facet.key);

                return (
                    <div key={facet.key} className={styles.row}>
                        <span
                            id={labelId}
                            className={mergeClasses(styles.rowLabel, isMedium && styles.rowLabelMedium)}
                            title={facet.label}
                        >
                            <span className={styles.rowLabelText}>{facet.label}</span>
                        </span>

                        {locked ? (
                            <div className={styles.tags}>
                                <Tag
                                    className={styles.locked}
                                    size={size}
                                    shape="circular"
                                    appearance="filled"
                                    media={{
                                        className: mediaClassName,
                                        children: (
                                            <>
                                                <LockClosedRegular className={iconClassName} aria-hidden="true" />
                                                {renderSwatch(locked)}
                                            </>
                                        )
                                    }}
                                >
                                    {locked.label}
                                    <span className={styles.visuallyHidden}>, applied to every product</span>
                                </Tag>
                            </div>
                        ) : (
                            <TagGroup
                                className={mergeClasses(styles.tags, props.scrollRows && styles.tagsScrolled)}
                                size={size}
                                aria-labelledby={labelId}
                                selectedValues={selected.slice()}
                                onTagSelect={(_event: unknown, data: { value: string }) => onToggle(facet.key, data.value)}
                            >
                                {facet.values.map((value: IAgentProductFacetValue) => {
                                    const isSelected: boolean = selected.indexOf(value.key) >= 0;
                                    const swatch: React.ReactElement | null = renderSwatch(value);

                                    return (
                                        <InteractionTag key={value.key} value={value.key} shape="circular" appearance="outline">
                                            <InteractionTagPrimary
                                                media={isSelected || swatch ? {
                                                    className: mediaClassName,
                                                    children: (
                                                        <>
                                                            {isSelected && <CheckmarkRegular className={iconClassName} aria-hidden="true" />}
                                                            {swatch}
                                                        </>
                                                    )
                                                } : undefined}
                                            >
                                                {value.label}
                                            </InteractionTagPrimary>
                                        </InteractionTag>
                                    );
                                })}
                            </TagGroup>
                        )}
                    </div>
                );
            })}
        </div>
    );
});

ProductFacetFilters.displayName = "ProductFacetFilters";
