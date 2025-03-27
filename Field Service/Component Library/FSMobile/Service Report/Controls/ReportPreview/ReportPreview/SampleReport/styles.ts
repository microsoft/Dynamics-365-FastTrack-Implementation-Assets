import * as React from "react";

/**
 * Styles to add to your report in SampleReport.tsx
 */
export const styles: { [key: string]: React.CSSProperties } = {
    title: {
        width: "400px",
        position: "relative",
        color: "blue",
        fontFamily: "sans-serif",
        fontWeight: "bold",
        fontSize: "18px",
        opacity: 1,
        textAlign: "left",
        marginBottom: "10px"
    },
    address: {
        textAlign: "left",
        marginBottom: "30px",
        display: "grid",
        gridTemplateColumns: "1fr 1fr",
    },
    bar: {
        height: "35px",
        border: "1.5px solid rgba(225, 225, 225, 1)",
        backgroundColor: "rgba(241, 241, 241, 1)",
        display: "flex",
    },
    sectionTitle: {
        display: "flex",
        marginLeft: "12px",
        marginTop: "8px",
        fontFamily: "sans-serif",
        fontWeight: "bold",
        fontSize: "16px",
        textAlign: "left"
    },
    rel: { position: "relative" },

    fieldBox: {
        border: "1.5px solid rgba(225, 225, 225, 1)",
        overflow: "hidden",
        display: "flex",
        height: "auto",
        minHeight: "35px",
        flex: 1,
        maxWidth: "550px"
    },
    name: {
        marginLeft: "12px",
        marginTop: "8px",
        fontFamily: "sans-serif",
        fontSize: "15px",
        fontWeight: "bold",
        textAlign: "left",
        minWidth: "30%"
    },
    value: {
        marginTop: "8px",
        fontFamily: "sans-serif",
        fontSize: "15px",
        marginLeft: "15px",
        textAlign: "left",
    },
    singleColValue: {
        marginTop: "8px",
        fontFamily: "sans-serif",
        fontSize: "15px",
        textAlign: "left"
    },
    hideText: {
        textIndent: "100%",
        whiteSpace: "nowrap",
        overflow: "hidden"
    }
};
