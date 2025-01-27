# Product integration

[[_TOC_]]


### Integration approach

An assumption for this integration mapping is that Dynamics 365 Commerce will be the source of truth for product information management.

That means that information from the product catalog should be managed primarily in Dynamics 365 Commerce, then replicated to the third-party store.

#### Working with Products

For working with products using the Headless Commerce Engine, use the Products Controller APIs.

The complete Product APIs can be found in [Commerce API Products Controller Documentation]("https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/retail-server-customer-consumer-api#products-controller")

## Base Data Mapping

When working with products and variants, the default type returned is the SimpleProduct, described below.
Use the table below to create the mapping to your third party integrated system data source.

| **Property Name**    | **Type**                                                                      | **Nullable** |
|----------------------|-------------------------------------------------------------------------------|--------------|
| RecordId             | Edm.Int64                                                                     | No           |
| ItemId               | Edm.String                                                                    | Yes          |
| Name                 | Edm.String                                                                    | Yes          |
| Description          | Edm.String                                                                    | Yes          |
| ProductTypeValue     | Edm.Int32                                                                     | No           |
| DefaultUnitOfMeasure | Edm.String                                                                    | Yes          |
| BasePrice            | Edm.Decimal                                                                   | No           |
| Price                | Edm.Decimal                                                                   | No           |
| AdjustedPrice        | Edm.Decimal                                                                   | No           |
| MasterProductId      | Edm.Int64                                                                     | Yes          |
| Components           | Collection(Microsoft.Dynamics.Commerce.Runtime.DataModel.ProductComponent)    | Yes          |
| Dimensions           | Collection(Microsoft.Dynamics.Commerce.Runtime.DataModel.Dimensions)    | Yes          |
| IsGiftCard           | Edm.Boolean                                                                   | Yes          |
| ProductNumber        | Edm.String                                                                    | Yes          |
| Dimensions           | Collection(Microsoft.Dynamics.Commerce.Runtime.DataModel.ProductDimension)    | Yes          |
| Behavior             | Microsoft.Dynamics.Commerce.Runtime.DataModel.ProductBehavior                 | Yes          |
| LinkedProducts       | Collection(Microsoft.Dynamics.Commerce.Runtime.DataModel.SimpleLinkedProduct) | Yes          |
| PrimaryImageUrl      | Edm.String                                                                    | Yes          |
| ItemTypeValue        | Edm.Int32                                                                     | Yes          |
| ItemServiceTypeValue | Edm.Int32                                                                     | Yes          |
| ExtensionProperties  | Collection(Microsoft.Dynamics.Commerce.Runtime.DataModel.CommerceProperty)    | Yes          |


## Product Publishing

The product data structure in Dynamics 365 is composed by multiple entities, represented by normalized tables that are exposed by a set of APIs that mean to simplify the results to be condensed in the Simple Product model presented above.
Also, the changes have to be tracked for when a product is either updated, added or removed.

For that, there is a set of APIs on the Headless Commerce Engine that can be called for handling those calls.

To make it easier and provide a kickstart, there is a product publisher example that leverages the Retail Proxy to make those calls and it is described below.

As part of this documentation, we provide a sample publisher code for your reference.

Please check [Sample Product Publisher](./assets/samplecommerceproductpublisher) for the source code and further documentation.

### What does the publisher do, and why do I need one?

#### Overview

Let's begin with a common scenario:  Your organization has chosen Dynamics 365 Commerce to be your system of record for orders.  

You need to ensure that your product data between F&O is synchronized with external platforms like Amazon, your ecommerce platform, and/or your 3PL.

What we think of as **Product data** is much easier to describe than it is to define.  Within Dynamics 365 Commerce, there are over 100 different tables that contribute to the data model for **Product**.  It contains several different concepts like
* **Core data**: name, description, translations, SKU, barcode(s)
* **Physical**: length, width, height, weight, unit of measure
* **Characteristics**:  Size, style, color, configuration
* **Attributes**:  Brand, country of origin, rating
* **Category**: Navigation, reporting, procurement hiearchies
* **Price**: Active price, discounts, affiliation-specific prices
* **Logistics**: Inventory on-hand, lead-time, modes of delivery
* **Marketing**: Images/media (links) 

Attempting to build an integration by hand would be time consuming and technically challenging as you would need to support full product loads as well as track incremental changes.  

Additionally, detecting changes from hundreds of tables and determining which products are impacted is a computationally expensive process.  

Dynamics 365 Commerce addresses this with a framework that detects and summarizes (publishes)  product changes.  

As mentioned earlier, this process is computationally expensive, and the workload is isolated to the Commerce Scale Unit (CSU) so that publishing does not compete against essential activities and resources in headquarters.  Second, the framework is simplified into three API endpoints that enable the workflow:

* BeginReadChangedProducts
* ReadChangedProducts
* EndReadChangedProducts

![publisher flow](../../Resources/products.publisher.diagram.png)

This is part of the [Products Controller](https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/retail-server-customer-consumer-api#products-controller) in the Commerce Scale Unit.  

Note that this is meant to be used as an integration pattern with external applications as the only security role allowed to call this API is the Application security role.  

The API documentation below assumes that you have already downloaded the Swagger JSON library using instructions from [Srinath's LinkedIn blog](https://www.linkedin.com/posts/srinath-sundaresan-8b05284b_enable-open-api-swagger-specification-for-activity-7048675741852422144-f4Jb/) and are looking to experiement with this framework.

The Retail Proxy is a C# library that wraps the Headless Commerce APIs.  The proxy handles all of the data serialization, parameter matching, and network-level complexity which enables you to realize the value of the framework faster. This allows you to focus on developing your business logic as opposed to marshaling API parameters.    

### BeginReadChangedProducts

#### Header

| Property | Description |
| --- | --- |
| Authorization | As this is an API that requires the Application role, make sure that you include the Entra bearer token.|
| OUN | Include the operating unit number (OUN).  This is required for most API requests. |


#### Body

| Property | Subproperty | Type | Description |
| --- | --- | --- | --- |
| changedProductSearchCriteria |  | ChangedProductSearchCriteria | A class conatining the following properties |
| ChangedProductSearchCriteria | Context| ProjectionDomain |
| ChangedProductSearchCriteria.**Context**| ChannelId | long int | The RecId representing the channel that you will be publishing.  This must match the OUN supplied in the header. **Note:**  This can be obtained by calling OrgUnits/GetOrgUnitConfiguration using just the OUN. |
| ChangedProductSearchCriteria.**Context**| CatalogId | long int | **Optional**:  The RecId corresponding to the catalog to be synchronized. Defaults to 0 if ommitted. |
|ChangedProductSearchCriteria | SynchronizationToken | string | A string containing the session token.  Leave empty for a full sync. |
| ChangedProductSearchCriteria | DataLevelValue | int | *Obsolete* |
| ChangedProductSearchCriteria| Session | class | *Obsolete* |
| ChangedProductSearchCriteria| AsListings | boolean | *Obsolete* |

#### Using Retail Proxy

The following preamble is common setup across any API usage.
```cs
// Preamble
IManagerFactoryConnector connector = new ManagerFactoryConnector(retailServerAuthParameters, this.publisherConfiguration);
ManagerFactory factory = connector.ConnectRetailManagerFactoryAsync(this.orgUnitNumber);
ChannelConfiguration channelConfiguration = factory.LoadChannelConfigurationAsync();

// Create an API manager for the "Product" family of API calls.
IProductManager productManager = factory.GetManager<IProductManager>();
```

The following is specific to the publisher APIs:
```cs
// Set our search criteria for changed products.
ChangedProductsSearchCriteria searchCriteria = new ChangedProductsSearchCriteria 
{
    Context = new ProjectionDomain { ChannelId = this.channelConfiguration.RecordId },
    DataLevelValue = (int)CommerceEntityDataLevel.Standard,
};

// 
ReadChangedProductsSession session = productManager.BeginReadChangedProducts(searchCriteria);
```

### ReadChangedProducts

#### Header

| Property | Description |
| --- | --- |
| Authorization | As this is an API that requires the Application role, make sure that you include the Entra bearer token.|
| OUN | Include the operating unit number (OUN).  This is required for most API requests. |

#### URL Query Parameters

| Property | Type | Description |
| --- | --- | --- |
| $top | long int | Standard query parameter rules apply.  List the number of products to return in the API call.  For performance reasons, aim to keep this number under 100. |
| $skip | long int | Standard query parameter rules apply.  Specify the 0-based offset to start this iteration of product read (e.g., 0, 100, 200). |

#### Body

Note that you should use the *ChangedProductsSearchCriteria* return value from **BeginReadChangedProducts** when calling **ReadChangedProducts**.

| Property | Subproperty | Type | Description |
| --- | --- | --- | --- |
| changedProductSearchCriteria |  | ChangedProductsSearchCriteria | A class conatining the following properties |
| ChangedProductsSearchCriteria | Context | ProjectionDomain | --- |
| ChangedProductSearchCriteria.**Context**| ChannelId | long int | The RecId representing the channel that you will be publishing.  This must match the OUN supplied in the header. **Note:**  This can be obtained by calling OrgUnits/GetOrgUnitConfiguration using just the OUN. |
| ChangedProductSearchCriteria.**Context**| CatalogId | long int | **Optional**:  The RecId corresponding to the catalog to be synchronized. Defaults to 0 if ommitted. |
| ChangedProductSearchCriteria | SynchronizationToken | string | A string containing the session token. This should come from *BeginReadChangedProducts*. |
| ChangedProductSearchCriteria | DataLevelValue | int | This should come from *BeginReadChangedProducts*. |
| ChangedProductSearchCriteria| Session | class | This should come from *BeginReadChangedProducts*. |
| ChangedProductSearchCriteria| AsListings | boolean | *Obsolete* |
| skipProductPriceCalculation |  | boolean | Defaults to **false** if ommitted. Note the negative logic, **false = "do not skip"** price calculation. |

> [!NOTE]
> When price calculation is selected, the list of products in the current read will be added to a fake shopping cart and a price calculation on the cart will be invoked using the standard pricing engine.  This populates the following properties in the SimpleProduct:
> * AdjustedPrice
> * BasePrice
> * Price (TradeAgreementPrice)
>
> A risk of using this pricing capability is that you might get some additional cart-based discounts in the results.  A more accurate alternative is to call the **GetActivePrices** API which accepts a list of product IDs.  

#### Using Retail Proxy

The following assumes the preabmle defined above.
```cs
QueryResultSettings productsQuerySettings = new QueryResultSettings
{
    Paging = new PagingInfo
    {
        Top = this.publisherConfiguration.ReadChangedProductsPageSize, // Assumed that this is a configurable constant
        Skip = 0,
    },
};

bool skipProductPriceCalculation = false; // false means "don't skip" price calculation

PagedResult<Product> productList = productManager.ReadChangedProducts(searchCriteria, skipProductPriceCalculation, productsQuerySettings);
```

### EndReadChangedProducts
The end call will perform cleanup and release session data stored on the CSU.  The return value is another session class which will have a new session ID that should be stored locally and used the next time the publisher is invoked.

#### Header

| Property | Description |
| --- | --- |
| Authorization | As this is an API that requires the Application role, make sure that you include the Entra bearer token.|
| OUN | Include the operating unit number (OUN).  This is required for most API requests. |

#### Body

Use the ReadChangedProductsSession result returned from calling **BeginReadChangedProducts**. 

| Property | Subproperty | Type | Description |
| --- | --- | --- | --- |
| session |  | ReadChangedProductsSession | A class conatining the following properties |
| ReadChangedProductsSession | Id | string/GUID | A class conatining the following properties |
| ReadChangedProductsSession | TotalNumberOfProducts | int | Optional.  Total number of products which were read in this session. |
| ReadChangedProductsSession | NextSynchronizationToken | string | The synchronization token which should be used to check for changes beyond this session. |

#### Using Retail Proxy

The following assumes the preabmle defined above.
```cs
// Use the session variable obtained when calling BeginReadChangedProducts.
ReadChangedProductsSession sessionEnd = productManager.BeginReadChangedProducts(searchCriteria);
```

## Continuity

This article and the full documentation are part of a continuous effort to provide reference libraries and models to help the community to accelerate the integration of third party systems using Headless Commerce.
We encourage you to clone this repository and check for updates constantly as we intent to improve it continuously.