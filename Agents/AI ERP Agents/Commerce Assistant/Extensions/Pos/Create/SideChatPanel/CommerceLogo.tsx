/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * The Commerce app icon, three warm gradient shapes on a white rounded tile, shown above an empty
 * conversation. It is drawn as an SVG rather than shipped as an image, so it stays sharp at every size
 * and adds no file to the package.
 */

import * as React from "react";
import { makeStyles, mergeClasses, shorthands, tokens, useId } from "@fluentui/react-components";

/** The top bar, on a 32 by 32 grid. */
const TOP_SHAPE: string = "M31.6282 5.61635C31.8087 4.78534 31.1756 4 30.3252 4H0.645914L2.76861 14.9972H28.5157"
    + "C29.1431 14.9972 29.6855 14.5599 29.8187 13.9469L31.6282 5.61635Z";

/** The bottom bar, on a 32 by 32 grid. */
const BOTTOM_SHAPE: string = "M26.8021 25.9465C27.561 22.3679 24.8316 18.999 21.1734 18.999L5.03102 18.999"
    + "C4.20168 18.999 3.57355 19.7481 3.7181 20.5648L4.60867 25.5962C5.05955 28.1436 7.27345 30 9.86037 30H21.7988"
    + "C24.2146 30 26.3009 28.3097 26.8021 25.9465Z";

/** The upright, drawn over both bars, on a 32 by 32 grid. */
const UPRIGHT_SHAPE: string = "M1.34806 2C0.506436 2 -0.124675 2.77017 0.0407361 3.59538L4.47451 25.7149"
    + "C4.97399 28.2067 7.16238 30 9.70382 30L24.6667 30L21.4135 30C18.8528 30 16.6535 28.1801 16.1743 25.6646"
    + "L11.8732 3.08385C11.7534 2.45498 11.2036 2 10.5634 2L1.34806 2Z";

const useStyles = makeStyles({
    tile: {
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        flexShrink: 0,
        boxSizing: "border-box",
        backgroundColor: tokens.colorNeutralBackground1,
        ...shorthands.border("1px", "solid", tokens.colorNeutralStroke3),
        boxShadow: tokens.shadow4
    }
});

/** What the logo needs. */
export interface ICommerceLogoProps {
    /** The tile's width and height, in pixels. The icon takes two thirds of it. Defaults to 48. */
    size?: number;
    className?: string;
}

/**
 * The Commerce icon on its tile. It is decorative: the title next to it names the assistant.
 * @param props The size and class.
 * @returns The rendered tile.
 */
export const CommerceLogo: React.FC<ICommerceLogoProps> = (props) => {
    const styles = useStyles();
    // Gradient ids are document-wide, and the icon can be on screen more than once.
    const id: string = useId("commerce-logo-");
    const size: number = props.size ?? 48;
    const iconSize: number = Math.round((size * 2) / 3);

    return (
        <span
            className={mergeClasses(styles.tile, props.className)}
            style={{ width: `${size}px`, height: `${size}px`, borderRadius: `${Math.round(size / 4)}px` }}
            aria-hidden="true"
        >
            <svg width={iconSize} height={iconSize} viewBox="0 0 32 32" fill="none" focusable="false">
                <defs>
                    <linearGradient id={`${id}-top`} x1="34.6667" y1="6.5" x2="9.16675" y2="12" gradientUnits="userSpaceOnUse">
                        <stop offset="0" stopColor="#FFD638" />
                        <stop offset="0.439507" stopColor="#FFB357" />
                        <stop offset="0.727296" stopColor="#FFA43D" />
                        <stop offset="1" stopColor="#CA6407" />
                    </linearGradient>
                    <linearGradient
                        id={`${id}-bottom`}
                        x1="26.6665"
                        y1="19.5001"
                        x2="17.9999"
                        y2="28.8334"
                        gradientUnits="userSpaceOnUse"
                    >
                        <stop offset="0" stopColor="#FE8401" />
                        <stop offset="0.512635" stopColor="#CA6407" />
                        <stop offset="1" stopColor="#8E250B" />
                    </linearGradient>
                    <linearGradient id={`${id}-upright`} x1="15.6667" y1="3.16667" x2="16.0001" y2="30" gradientUnits="userSpaceOnUse">
                        <stop offset="0" stopColor="#FFE06B" />
                        <stop offset="0.626493" stopColor="#FAB500" />
                        <stop offset="1" stopColor="#E67505" />
                    </linearGradient>
                </defs>
                <path d={TOP_SHAPE} fill={`url(#${id}-top)`} />
                <path d={BOTTOM_SHAPE} fill={`url(#${id}-bottom)`} />
                <path d={UPRIGHT_SHAPE} fill={`url(#${id}-upright)`} />
            </svg>
        </span>
    );
};
