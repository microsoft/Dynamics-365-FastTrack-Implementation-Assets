/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * AgentProductResultsView — shows the products the agent curated, as product cards.
 *
 * The side panel shows recommendations as cards in the conversation; this view opens when the
 * associate chooses View all there. It exists because the out-of-box search view cannot be given a
 * curated list of products by an extension: `ClientEntities.SearchNavigationParameters` carries a
 * search term and nothing else, so the search view always runs its own text query. When the agent
 * has already decided *which* products matter, a text term cannot express that.
 *
 * The important part is what crosses the wire. The agent sends record identifiers only. This
 * controller reads every product from the channel itself — name, price, image — so nothing the agent
 * might invent about a product can reach the screen. The agent chooses; POS remains the source of
 * truth for what those products actually are. The agent also reports the stock it read with the
 * Commerce inventory tools, which the cards show as its report.
 *
 * Filter tags narrow the products shown, in POS: Price from the prices read for the cards, and Color,
 * Size, Rating, Category and the other refiners Commerce returns through the same Commerce product
 * search the POS search view's Filter command uses. The agent is not asked again.
 */

import * as Views from "PosApi/Create/Views";
import * as SideChat from "ContosoSideChat";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import { ArrayExtensions, StringExtensions } from "PosApi/TypeExtensions";
import {
    IResolvedProductCards,
    resolveProductCardsAsync
} from "../../../Extend/Agent/ProductCardResolver";
import { addProductToSaleAsync } from "../../../Extend/Agent/ProductSaleHelper";
import { getShownInventory } from "../../../Extend/Agent/ProductInventory";
import { filterProductsAsync, getProductFacetsAsync } from "../../../Extend/Agent/ProductFacetResolver";
import { IProductFacets, matchCardsToFacets } from "../../../Extend/Agent/ProductFilters";
import { getCurrentStoreAsync } from "../../../Extend/Agent/CurrentStoreHelper";

/** The view's title when the agent gave no headline. */
const DEFAULT_TITLE: string = "Recommended products";

/**
 * The options the side panel passes in when the associate chooses View all.
 */
export interface IAgentProductResultsViewOptions {
    productIds?: number[];
    productSelections?: SideChat.IAgentProductSelection[];
    bestMatchProductId?: number;
    bestMatchReason?: string;
    headline?: string;
    /** The stock the agent reported for the products. Display only. */
    inventory?: ReadonlyArray<SideChat.IAgentProductInventory>;
    /** The filter tags POS built for the products in the chat. Built again when not given. */
    filterFacets?: ReadonlyArray<SideChat.IAgentProductFacet>;
    /** The tags the associate selected in the chat, which start selected here. */
    filterSelection?: SideChat.IAgentProductFilterSelection;
}

/** What the load read from the channel. */
interface ILoadedProducts {
    resolved: IResolvedProductCards;
    cards: SideChat.IAgentProductCard[];
    filterFacets: ReadonlyArray<SideChat.IAgentProductFacet>;
    inventory: SideChat.IAgentProductInventory[];
    currentStoreName: string | undefined;
}

/**
 * The controller for AgentProductResultsView.
 */
export default class AgentProductResultsView extends Views.CustomViewControllerBase {
    /** What is shown. */
    private readonly _options: IAgentProductResultsViewOptions;

    /** Held so the React root can be torn down in dispose. */
    private _hostElement: HTMLElement | null;

    /**
     * The products as the channel returned them, by record identifier.
     *
     * Kept because adding to the cart passes the whole product, not just its identifier: POS hands
     * `productSaleDetails` to pre-product-sale triggers untouched (see ItemSaleOperationHandler), so a
     * trigger that reads `product` gets nothing if only an identifier was supplied.
     */
    private _productsByRecordId: { [recordId: number]: ProxyEntities.SimpleProduct };
    private _saleProductsByRecordId: { [recordId: number]: ProxyEntities.SimpleProduct };

    /** The stock to show, one entry per product on screen, and the name of the store it is labelled with. */
    private _inventory: SideChat.IAgentProductInventory[];
    private _currentStoreName: string | undefined;

    /** The products on screen, whether they are still loading, and the message shown instead of them. */
    private _products: SideChat.IAgentProductCard[];
    private _isLoading: boolean;
    private _errorMessage: string | undefined;

    /** The filter tags shown above the products. */
    private _filterFacets: ReadonlyArray<SideChat.IAgentProductFacet>;

    /** Async work outlives navigation, so results are dropped once the view is gone. */
    private _isDisposed: boolean;

    /**
     * Initializes a new instance of the AgentProductResultsView class.
     * @param {Views.ICustomViewControllerContext} context The view controller context.
     * @param {IAgentProductResultsViewOptions} options The products the agent curated.
     */
    constructor(context: Views.ICustomViewControllerContext, options?: IAgentProductResultsViewOptions) {
        const config: Views.ICustomViewControllerConfiguration = {
            title: DEFAULT_TITLE,
            commandBar: { commands: [] }
        };

        super(context, config);

        this._options = options ?? {};
        this._hostElement = null;
        this._productsByRecordId = {};
        this._saleProductsByRecordId = {};
        this._inventory = [];
        this._currentStoreName = undefined;
        this._products = [];
        this._isLoading = true;
        this._errorMessage = undefined;
        this._filterFacets = [];
        this._isDisposed = false;

        this.state.title = getTitle(this._options.headline);
    }

    /**
     * Renders the results once the view element is available.
     * @param {HTMLElement} element The DOM element for the view.
     */
    public onReady(element: HTMLElement): void {
        // No ko.applyBindings: the whole view is React, and applying Knockout over a React-owned
        // subtree would give two libraries write access to the same DOM.
        this._hostElement = element;

        // Render immediately so the operator sees the headline and a loading line rather than a blank
        // screen while the channel reads happen.
        this._render();
        this._load();
    }

    /**
     * Tears down the React root so it does not outlive the view.
     */
    public dispose(): void {
        this._isDisposed = true;

        if (this._hostElement) {
            SideChat.unmountProductResults(this._hostElement);
            this._hostElement = null;
        }
    }

    /**
     * Reads the products in the options from the channel and shows them.
     */
    private _load(): void {
        const options: IAgentProductResultsViewOptions = this._options;
        const productIds: number[] = options.productIds ?? [];

        if (!ArrayExtensions.hasElements(productIds)) {
            this._showProducts([], "The assistant did not include any products to show.");
            return;
        }

        this.state.isProcessing = true;

        this._loadProductsAsync(productIds, options)
            .then((loaded: ILoadedProducts) => {
                if (this._isDisposed) {
                    return;
                }

                this.state.isProcessing = false;
                this._productsByRecordId = loaded.resolved.productsByRecordId;
                this._saleProductsByRecordId = loaded.resolved.saleProductsByRecordId;
                this._inventory = loaded.inventory;
                this._currentStoreName = loaded.currentStoreName;
                this._filterFacets = loaded.filterFacets;
                this._showProducts(loaded.cards, undefined);
            })
            .catch((error: unknown) => {
                if (this._isDisposed) {
                    return;
                }

                this.state.isProcessing = false;
                this.context.logger.logError(
                    `AgentProductResultsView could not load the curated products: ${JSON.stringify(error)}`);
                this._inventory = [];
                this._currentStoreName = undefined;
                this._filterFacets = [];
                this._showProducts([], "The recommended products could not be loaded.");
            });
    }

    /**
     * Shows a finished load: the products, or the message shown instead of them.
     * @param {SideChat.IAgentProductCard[]} products The products to show.
     * @param {string | undefined} errorMessage The message to show instead of products, when set.
     */
    private _showProducts(products: SideChat.IAgentProductCard[], errorMessage: string | undefined): void {
        this._products = products;
        this._errorMessage = errorMessage;
        this._isLoading = false;
        this._render();
    }

    /**
     * Renders the React app into the view element.
     */
    private _render(): void {
        if (!this._hostElement) {
            return;
        }

        const products: SideChat.IAgentProductCard[] = this._products;
        const requestedBestMatchProductId: number | undefined = this._options.bestMatchProductId;
        const bestMatchProductId: number | undefined = products.some(
            (product: SideChat.IAgentProductCard) => product.recordId === requestedBestMatchProductId)
            ? requestedBestMatchProductId
            : products[0]?.recordId;
        const bestMatchReason: string | undefined = this._options.bestMatchReason;

        SideChat.mountProductResults(this._hostElement, {
            products: products,
            bestMatchProductId: bestMatchProductId,
            bestMatchReason: bestMatchReason,
            headline: this._options.headline,
            inventory: this._inventory,
            currentStoreName: this._currentStoreName,
            filterFacets: this._filterFacets,
            initialFilterSelection: this._options.filterSelection,
            isLoading: this._isLoading,
            errorMessage: this._errorMessage,
            onCompareRequested: (recordIds: ReadonlyArray<number>): void => {
                const selectedProducts: SideChat.IAgentProductCard[] = products.filter(
                    (product: SideChat.IAgentProductCard) => recordIds.indexOf(product.recordId) >= 0);

                this.context.navigator.navigate("AgentProductCompareView", {
                    products: selectedProducts,
                    bestMatchProductId: bestMatchProductId,
                    bestMatchReason: bestMatchReason
                });
            },
            onProductActivated: (recordId: number): void => {
                // The out-of-box product details page is reachable by record identifier, so a card
                // hands off to the real product page rather than reimplementing it.
                this.context.navigator.navigateToPOSView(
                    "SimpleProductDetailsView",
                    new ClientEntities.SimpleProductDetailsNavigationParameters(recordId));
            },
            onAddToCart: (recordId: number): Promise<void> => {
                return this._addToCartAsync(recordId);
            },
            onFilterProducts: (request: SideChat.IAgentProductFilterRequest): Promise<ReadonlyArray<number>> => {
                return filterProductsAsync(request, this.context);
            }
        });
    }

    /**
     * Adds a product to the current transaction.
     *
     * Routed through the add-to-cart operation rather than a cart service call so that everything POS
     * normally does still happens: price and discount resolution, reason codes, dimension prompts for
     * a product with variants, and any pre/post product sale triggers a retailer has installed.
     *
     * The whole product is supplied, not just its record identifier. POS passes `productSaleDetails`
     * to pre-product-sale triggers exactly as given (see ItemSaleOperationHandler.executePreTrigger),
     * so a trigger that reads `product` — as the sample's own ForceErrorPreProductSaleTrigger does —
     * sees nothing when only an identifier was sent, and the operation fails inside the trigger.
     * @param {number} recordId The product record identifier.
     * @returns {Promise<void>} A promise resolved once the product has been added.
     */
    private async _addToCartAsync(recordId: number): Promise<void> {
        const product: ProxyEntities.SimpleProduct =
            this._saleProductsByRecordId[recordId] ?? this._productsByRecordId[recordId];
        await addProductToSaleAsync(product?.RecordId ?? recordId, this.context, product);
    }

    /**
     * Reads the curated products from the channel and shapes them for display, along with their
     * filter tags and the stock the agent reported for them. Nothing is assigned here, so the caller
     * can drop a load that finishes after the view is gone.
     * @param {number[]} productIds The record identifiers the agent chose.
     * @param {IAgentProductResultsViewOptions} options The options the products came with.
     * @returns {Promise<ILoadedProducts>} The products, in the order the agent chose them, their tags and their stock.
     */
    private async _loadProductsAsync(productIds: number[], options: IAgentProductResultsViewOptions): Promise<ILoadedProducts> {
        const resolved: IResolvedProductCards = await resolveProductCardsAsync(
            productIds,
            this.context,
            options.productSelections);

        // The chat's tags are used as they are, so the tags selected there mean the same here. They
        // are built again only when the chat had none to give, such as a conversation from before them.
        let cards: SideChat.IAgentProductCard[];
        let filterFacets: ReadonlyArray<SideChat.IAgentProductFacet>;
        if (Array.isArray(options.filterFacets)) {
            cards = matchCardsToFacets(resolved.cards, options.filterFacets);
            filterFacets = options.filterFacets;
        } else {
            const built: IProductFacets = await getProductFacetsAsync(resolved.cards, undefined, this.context);
            cards = built.cards;
            filterFacets = built.facets;
        }

        // The store is read only when there is stock to label.
        const reported: ReadonlyArray<SideChat.IAgentProductInventory> | undefined = options.inventory;
        if (!Array.isArray(reported) || reported.length === 0) {
            return { resolved: resolved, cards: cards, filterFacets: filterFacets, inventory: [], currentStoreName: undefined };
        }

        const currentStore: SideChat.IAgentStoreContext | undefined = await getCurrentStoreAsync(this.context);
        const inventory: SideChat.IAgentProductInventory[] = getShownInventory(
            reported,
            resolved.cards.map((card: SideChat.IAgentProductCard) => card.recordId),
            resolved.productSelections,
            currentStore);

        return {
            resolved: resolved,
            cards: cards,
            filterFacets: filterFacets,
            inventory: inventory,
            currentStoreName: inventory.length > 0 ? currentStore?.name : undefined
        };
    }
}

/**
 * Gets the view's title.
 * @param {string | undefined} headline The agent's headline for the products.
 * @returns {string} The headline, or the default title when there is none.
 */
function getTitle(headline: string | undefined): string {
    return StringExtensions.isNullOrWhitespace(headline) ? DEFAULT_TITLE : headline;
}
