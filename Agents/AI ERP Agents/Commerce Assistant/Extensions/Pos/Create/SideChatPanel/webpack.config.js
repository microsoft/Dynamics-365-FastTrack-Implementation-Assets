/*
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

// Bundles the React + Fluent UI v9 docked chat side panel (including React, ReactDOM, and all
// Fluent dependencies) into a single, self-contained AMD module.
//
// This is a separate bundle from Libraries/ContosoChatAgent.js on purpose: the full-page chat view
// and this side panel are independent samples, so neither can break the other's build or its
// Fluent instance.

"use strict";

const path = require("path");
const TerserPlugin = require("terser-webpack-plugin");

module.exports = (env, argv) => {
    const mode = (argv && argv.mode) || "production";
    const isProduction = mode === "production";

    return {
        mode,
        entry: path.resolve(__dirname, "index.tsx"),

        // Emit next to the other packaged libraries so the manifest alias resolves it.
        output: {
            path: path.resolve(__dirname, "..", "..", "Libraries"),
            filename: "ContosoSideChat.js",
            // Anonymous AMD define so SystemJS resolves it to the manifest dependency alias.
            library: { type: "amd" },
            clean: false
        },

        resolve: {
            extensions: [".tsx", ".ts", ".jsx", ".js"]
        },

        module: {
            rules: [
                {
                    test: /\.[jt]sx?$/,
                    exclude: /node_modules/,
                    use: {
                        loader: "esbuild-loader",
                        options: {
                            // Pin the app tsconfig so esbuild-loader does not walk up and pick up
                            // the POS extension's tsconfig.json (which targets SystemJS/ES5 and
                            // extends a base that only exists after the Commerce SDK InitDev step).
                            tsconfig: path.resolve(__dirname, "app.tsconfig.json"),
                            loader: "tsx",
                            target: "es2019",
                            jsx: "automatic"
                        }
                    }
                }
            ]
        },

        optimization: {
            minimize: isProduction,
            // Keep everything in one self-contained .js so the AMD module is a single packaged file.
            minimizer: [new TerserPlugin({ extractComments: false })]
        },

        devtool: isProduction ? false : "inline-source-map",

        // The bundle is intentionally large (React + Fluent UI); suppress size warnings.
        performance: { hints: false },

        stats: "minimal"
    };
};
