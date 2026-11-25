/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Out-of-box Retail Server operations that the POS API has no request for, called through the public
 * `DataServiceRequest`.
 *
 * Each request names an operation Retail Server already exposes, with the entity set, key and
 * parameters POS's own Commerce context uses for it, so nothing here adds a Commerce Scale Unit
 * endpoint. They run as the signed-in worker, like the POS screens that call the same operations.
 */

import { ProxyEntities } from "PosApi/Entities";
import { DataServiceRequest, DataServiceResponse } from "PosApi/Consume/DataService";

/** The customers Customers/Search found. */
export class SearchCustomersResponse extends DataServiceResponse {
    public result: ProxyEntities.GlobalCustomer[];
}

/**
 * Customers/Search: finds the customers in this company whose name, phone, email or account number
 * matches a keyword, with the criteria the POS customer search sends for a search of this store.
 */
export class SearchCustomersRequest<TResponse extends SearchCustomersResponse> extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     * @param keyword What to search for, for example a customer's name.
     * @param top The most customers to return.
     */
    public constructor(correlationId: string, keyword: string, top: number) {
        super(correlationId);

        this._entitySet = "Customers";
        this._entityType = "Customer";
        this._keys = null;
        this._method = "Search";
        this._parameters = {
            customerSearchCriteria: {
                Keyword: keyword,
                SearchOnlyCurrentCompany: true,
                SearchLocationValue: ProxyEntities.SearchLocation.Local,
                DataLevelValue: ProxyEntities.CommerceEntityDataLevel.Identity
            }
        };
        this._isAction = true;
        this._returnType = ProxyEntities.GlobalCustomerClass;
        this._isReturnTypeCollection = true;
        this.top = top;
    }
}

/** The stores OrgUnits/Search found. */
export class SearchOrgUnitsResponse extends DataServiceResponse {
    public result: ProxyEntities.OrgUnit[];
}

/** OrgUnits/Search: finds a store by its organization unit number, as the POS shipping screen does. */
export class SearchOrgUnitsRequest<TResponse extends SearchOrgUnitsResponse> extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     * @param storeNumber The store's organization unit number, for example "SANANTO".
     */
    public constructor(correlationId: string, storeNumber: string) {
        super(correlationId);

        this._entitySet = "OrgUnits";
        this._entityType = "OrgUnit";
        this._keys = null;
        this._method = "Search";
        this._parameters = { storeSearchCriteria: { StoreNumber: storeNumber } };
        this._isAction = true;
        this._returnType = ProxyEntities.OrgUnitClass;
        this._isReturnTypeCollection = true;
        this.top = 5;
    }
}

/** The delivery modes each cart line can use. */
export class GetLineDeliveryOptionsByChannelIdResponse extends DataServiceResponse {
    public result: ProxyEntities.SalesLineDeliveryOption[];
}

/**
 * Carts('id')/GetLineDeliveryOptionsByChannelId: the delivery modes that can ship each cart line from
 * a store to an address, as the POS shipping screen lists them.
 */
export class GetLineDeliveryOptionsByChannelIdRequest<TResponse extends GetLineDeliveryOptionsByChannelIdResponse>
    extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     * @param cartId The cart.
     * @param lineShippingAddresses Each line to ship, with the address it ships to.
     * @param channelId The record identifier of the store that ships the lines.
     */
    public constructor(
        correlationId: string,
        cartId: string,
        lineShippingAddresses: ProxyEntities.LineShippingAddress[],
        channelId: number) {
        super(correlationId);

        this._entitySet = "Carts";
        this._entityType = "Cart";
        this._keys = { Id: cartId };
        this._method = "GetLineDeliveryOptionsByChannelId";
        this._parameters = {
            lineShippingAddresses: lineShippingAddresses,
            channelId: channelId,
            filterOption: ProxyEntities.FilterDeliveryModeOption.None
        };
        this._isAction = true;
        this._returnType = ProxyEntities.SalesLineDeliveryOptionClass;
        this._isReturnTypeCollection = true;
    }
}

/** The cart after its lines were updated. */
export class UpdateCartLinesResponse extends DataServiceResponse {
    public result: ProxyEntities.Cart;
}

/** Carts('id')/UpdateCartLines: saves changed cart lines, as the POS Ship selected operation does. */
export class UpdateCartLinesRequest<TResponse extends UpdateCartLinesResponse> extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     * @param cartId The cart.
     * @param cartLines The changed lines.
     * @param cartVersion The version of the cart the lines were read from, so a cart changed since is not overwritten.
     */
    public constructor(correlationId: string, cartId: string, cartLines: ProxyEntities.CartLine[], cartVersion: number) {
        super(correlationId);

        this._entitySet = "Carts";
        this._entityType = "Cart";
        this._keys = { Id: cartId };
        this._method = "UpdateCartLines";
        this._parameters = { cartLines: cartLines, cartVersion: cartVersion };
        this._isAction = true;
        this._returnType = ProxyEntities.CartClass;
        this._isReturnTypeCollection = false;
    }
}

/** The channel's delivery option configuration. */
export class GetChannelDeliveryOptionConfigurationResponse extends DataServiceResponse {
    public result: ProxyEntities.ChannelDeliveryOptionConfiguration;
}

/** GetChannelDeliveryOptionConfiguration(): the channel's pickup delivery modes, which POS never ships with. */
export class GetChannelDeliveryOptionConfigurationRequest<TResponse extends GetChannelDeliveryOptionConfigurationResponse>
    extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     */
    public constructor(correlationId: string) {
        super(correlationId);

        // No entity set or type: an unbound function, as POS's own Commerce context calls it.
        this._keys = null;
        this._method = "GetChannelDeliveryOptionConfiguration";
        this._parameters = {};
        this._isAction = false;
        this._returnType = ProxyEntities.ChannelDeliveryOptionConfigurationClass;
        this._isReturnTypeCollection = false;
    }
}

/** The refiners Products/GetProductSearchRefiners found, each with its values. */
export class GetProductSearchRefinersResponse extends DataServiceResponse {
    public result: ProxyEntities.ProductRefiner[];
}

/**
 * Products/GetProductSearchRefiners: the refiners, such as Color and Size, that apply to a set of
 * products, as the POS search view's Filter command reads them for the products it shows.
 */
export class GetProductSearchRefinersRequest<TResponse extends GetProductSearchRefinersResponse>
    extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     * @param productIds The products.
     * @param context The channel and catalog to read them in.
     */
    public constructor(correlationId: string, productIds: number[], context: ProxyEntities.ProjectionDomain) {
        super(correlationId);

        this._entitySet = "Products";
        this._entityType = "Product";
        this._keys = null;
        this._method = "GetProductSearchRefiners";
        this._parameters = { searchCriteria: { Ids: productIds, Context: context } };
        this._isAction = true;
        this._returnType = ProxyEntities.ProductRefinerClass;
        this._isReturnTypeCollection = true;
    }
}

/** The products Products/SearchByText found. */
export class SearchByTextResponse extends DataServiceResponse {
    public result: ProxyEntities.ProductSearchResult[];
}

/**
 * Products/SearchByText: the products in a store's catalog that match a piece of text, such as an item ID,
 * as the POS bulk item entry looks up each item ID in a pasted list.
 */
export class SearchByTextRequest<TResponse extends SearchByTextResponse> extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     * @param channelId The record identifier of the store to search.
     * @param catalogId The catalog to search, or 0 for the store's whole assortment.
     * @param searchText What to search for, for example an item ID.
     * @param top The most products to return.
     */
    public constructor(correlationId: string, channelId: number, catalogId: number, searchText: string, top: number) {
        super(correlationId);

        this._entitySet = "Products";
        this._entityType = "Product";
        this._keys = null;
        this._method = "SearchByText";
        this._parameters = { channelId: channelId, catalogId: catalogId, searchText: searchText };
        this._isAction = false;
        this._returnType = ProxyEntities.ProductSearchResultClass;
        this._isReturnTypeCollection = true;
        this.top = top;
    }
}

/** The products Products/SearchByCriteria found. */
export class SearchByCriteriaResponse extends DataServiceResponse {
    public result: ProxyEntities.ProductSearchResult[];
}

/**
 * Products/SearchByCriteria: the products, out of a given set, that have the given refiner values,
 * as the POS Similar looks view narrows its products with the Filter command.
 */
export class SearchByCriteriaRequest<TResponse extends SearchByCriteriaResponse> extends DataServiceRequest<TResponse> {
    /**
     * @param correlationId The correlation identifier for logging.
     * @param productIds The products to search.
     * @param context The channel and catalog to search them in.
     * @param refinement The refiner values the products must have.
     * @param top The most products to return.
     */
    public constructor(
        correlationId: string,
        productIds: number[],
        context: ProxyEntities.ProjectionDomain,
        refinement: ProxyEntities.ProductRefinerValue[],
        top: number) {
        super(correlationId);

        this._entitySet = "Products";
        this._entityType = "Product";
        this._keys = null;
        this._method = "SearchByCriteria";
        this._parameters = { searchCriteria: { Ids: productIds, Context: context, Refinement: refinement } };
        this._isAction = true;
        this._returnType = ProxyEntities.ProductSearchResultClass;
        this._isReturnTypeCollection = true;
        this.top = top;
    }
}
