# Introduction

In the dynamic world of retail, real-time access to inventory data is essential for meeting customer demands efficiently. Dynamics 365 Commerce provides powerful capabilities for integrating third-party applications, ensuring seamless inventory management across multiple channels. This article will explore how third-party applications can integrate with Dynamics 365 Commerce, particularly the Commerce Scale Unit (CSU), to check the availability of specific products or variants. Additionally, we will examine the out-of-the-box (OOB) APIs available for this integration.

# Assumptions

This article is written with the assumption that

1. Dynamics 365 serves as the system of record for inventory management.
2. The variant level productid [SKU] is maintained at the external marketing system and it will be used while integrating with the Dynamics 365 Commerce API.
3. The external marketing system is looking for the availability of the product and not the exact quantity available in respective location.

# Different options to access Inventory data

Accessing inventory data efficiently is critical for businesses to maintain operational agility and meet customer demands. Dynamics 365 provides multiple approaches tailored to specific use cases, from back-office integrations to high-performance retail scenarios. Each method offers unique capabilities to address varying requirements for data accessibility, speed, and scalability.

- **Dynamics 365 Finance and Operations:**
  Provides access to inventory data through data entities or OData APIs, ideal for back-office operations. It supports batch processing but may not be optimized for real-time scenarios.

- **Dynamics 365 Commerce APIs:**
  Offers real-time inventory data access via the Commerce Scale Unit (CSU), designed for retail scenarios like e-commerce or POS integrations. It ensures fast responses but focuses on transactional data.

- **Dynamics 365 Commerce APIs with IVS (Inventory Visibility Service):**
  Enhances the standard Commerce APIs by leveraging the Inventory Visibility Service for ultra-fast, scalable, and near-real-time inventory data retrieval. This is particularly useful for high-demand, multi-channel retail environments where performance and scalability are critical.
  One advantage we would like to highlight is that by using the Commerce APIs with IV, inventory updates are automatically registered as part of sales, inventory counting, or other Inventory operations built into Commerce. When Commerce APIs are enabled with IVS, it provides the flexibility to Utilize IVS to read or write from any other third app, such as integrating cross channels.

The preferred approach for accessing inventory data from the external marketing application is by using the headless commerce APIs with Inventory Visibility Service (IVS). By leveraging IVS,you can improve customer experiences, reduce stockouts, and optimize operations, ensuring they remain competitive in today’s dynamic retail landscape.

## Integrating Third-Party Applications with CSU

Third-party applications can leverage the Headless Commerce APIs to access inventory data in real-time. The integration process involves using OOB APIs provided by Dynamics 365 Commerce to query inventory availability for specific product or variants. These APIs enable third-party applications to retrieve accurate inventory information, ensuring that customers receive up-to-date stock levels when making purchase decisions.
The Inventory Visibility for Dynamics 365 now integrates with Dynamics 365 Commerce Scale Units (CSU) which offers channel-side inventory availability calculations with near-real-time and holistic inventory accuracy across channels and locations for retailers.

## Available OOB APIs for Inventory Availability

Dynamics 365 Commerce offers several OOB APIs that third-party applications can use to check inventory availability. Here are some key APIs:

1. GetEstimatedAvailability API:
   This API allows third-party applications to query the inventory availability of a product or product variant in the online channel's default warehouse or warehouses linked to the online channel's fulfillment group.

## Examples of API Requests and Responses

Here are some examples of how to use the GetEstimatedAvailability API:

1.  To check inventory availability for the associated fulfillment groups, ensure that the request parameters include "FilterByChannelFulfillmentGroup": true

Here is how the sample data would look like

## Request:

```cs
   GET /Commerce/Inventory/GetEstimatedAvailability
   Host: {CommerceScaleUnitURL}
   Authorization: Bearer {OAuthToken}
   Content-Type: application/json
{
    "searchCriteria": {
        "ProductIds": [
            68719498155
        ],
        "QuantityUnitTypeValue": 2,
        "DefaultWarehouseOnly": false,
			"FilterByChannelFulfillmentGroup" : true
    }
}
```

## Response:

```cs
   {
	"@odata.context": "https://<<RetailServerURL>>/Commerce/$metadata#Microsoft.Dynamics.Commerce.Runtime.DataModel.ProductWarehouseInventoryInformation",
	"ProductWarehouseInventoryAvailabilities": [
		{
			"ProductId": 68719498155,
			"InventLocationId": "SANFRANCIS",
			"DataAreaId": "usrt",
			"PhysicalInventory": 65,
			"PhysicalReserved": 0,
			"TotalAvailable": 65,
			"TotalAvailableInventoryLevelLabel": "In stock",
			"TotalAvailableInventoryLevelCode": "AVAIL",
			"OrderedInTotal": 0,
			"PhysicalAvailable": 65,
			"PhysicalAvailableInventoryLevelLabel": "In stock",
			"PhysicalAvailableInventoryLevelCode": "AVAIL",
			"LastInventoryTransactionId": 68720284617,
			"UnpostedOnlineOrderedQuantity": 0,
			"UnpostedFulfilledQuantity": 0,
			"IsInventoryAvailabilityQuantityReturned": true,
			"UnprocessedQuantity": 0,
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 60,
			"MaximumPurchasableTotalAvailableQuantity": 60,
			"SumUncountedTransactions": 0,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		},
		{
			"ProductId": 68719498155,
			"InventLocationId": "ANNAPOL",
			"DataAreaId": "usrt",
			"PhysicalInventory": 0,
			"PhysicalReserved": 0,
			"TotalAvailable": 0,
			"TotalAvailableInventoryLevelLabel": "Out of stock",
			"TotalAvailableInventoryLevelCode": "OOS",
			"OrderedInTotal": 0,
			"PhysicalAvailable": 0,
			"PhysicalAvailableInventoryLevelLabel": "Out of stock",
			"PhysicalAvailableInventoryLevelCode": "OOS",
			"LastInventoryTransactionId": 0,
			"UnpostedOnlineOrderedQuantity": 0,
			"UnpostedFulfilledQuantity": 0,
			"IsInventoryAvailabilityQuantityReturned": true,
			"UnprocessedQuantity": 0,
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 0,
			"MaximumPurchasableTotalAvailableQuantity": 0,
			"SumUncountedTransactions": 0,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		},
		{
			"ProductId": 68719498155,
			"InventLocationId": "ANNARBO",
			"DataAreaId": "usrt",
			"PhysicalInventory": 0,
			"PhysicalReserved": 0,
			"TotalAvailable": 0,
			"TotalAvailableInventoryLevelLabel": "Out of stock",
			"TotalAvailableInventoryLevelCode": "OOS",
			"OrderedInTotal": 0,
			"PhysicalAvailable": 0,
			"PhysicalAvailableInventoryLevelLabel": "Out of stock",
			"PhysicalAvailableInventoryLevelCode": "OOS",
			"LastInventoryTransactionId": 0,
			"UnpostedOnlineOrderedQuantity": 0,
			"UnpostedFulfilledQuantity": 0,
			"IsInventoryAvailabilityQuantityReturned": true,
			"UnprocessedQuantity": 0,
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 0,
			"MaximumPurchasableTotalAvailableQuantity": 0,
			"SumUncountedTransactions": 0,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		},
		{
			"ProductId": 68719498155,
			"InventLocationId": "ATLANTA",
			"DataAreaId": "usrt",
			"PhysicalInventory": 0,
			"PhysicalReserved": 0,
			"TotalAvailable": 0,
			"TotalAvailableInventoryLevelLabel": "Out of stock",
			"TotalAvailableInventoryLevelCode": "OOS",
			"OrderedInTotal": 0,
			"PhysicalAvailable": 0,
			"PhysicalAvailableInventoryLevelLabel": "Out of stock",
			"PhysicalAvailableInventoryLevelCode": "OOS",
			"LastInventoryTransactionId": 0,
			"UnpostedOnlineOrderedQuantity": 0,
			"UnpostedFulfilledQuantity": 0,
			"IsInventoryAvailabilityQuantityReturned": true,
			"UnprocessedQuantity": 0,
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 0,
			"MaximumPurchasableTotalAvailableQuantity": 0,
			"SumUncountedTransactions": 0,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		},
		{
			"ProductId": 68719498155,
			"InventLocationId": "TYSONSC",
			"DataAreaId": "usrt",
			"PhysicalInventory": 0,
			"PhysicalReserved": 0,
			"TotalAvailable": 0,
			"TotalAvailableInventoryLevelLabel": "Out of stock",
			"TotalAvailableInventoryLevelCode": "OOS",
			"OrderedInTotal": 0,
			"PhysicalAvailable": 0,
			"PhysicalAvailableInventoryLevelLabel": "Out of stock",
			"PhysicalAvailableInventoryLevelCode": "OOS",
			"LastInventoryTransactionId": 0,
			"UnpostedOnlineOrderedQuantity": 0,
			"UnpostedFulfilledQuantity": 0,
			"IsInventoryAvailabilityQuantityReturned": true,
			"UnprocessedQuantity": 0,
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 0,
			"MaximumPurchasableTotalAvailableQuantity": 0,
			"SumUncountedTransactions": 0,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		}
	],
	"AggregatedProductInventoryAvailabilities": [
		{
			"ProductId": 68719498155,
			"DataAreaId": "usrt",
			"TotalAvailableQuantity": 65,
			"TotalAvailableInventoryLevelLabel": "In stock",
			"TotalAvailableInventoryLevelCode": "AVAIL",
			"PhysicalAvailableQuantity": 65,
			"PhysicalAvailableInventoryLevelLabel": "In stock",
			"PhysicalAvailableInventoryLevelCode": "AVAIL",
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 60,
			"MaximumPurchasableTotalAvailableQuantity": 60,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		}
	],
	"ExtensionProperties": []
}
```

2. To check inventory availability exclusively from the Default Warehouse, ensure that the request parameters include "DefaultWarehouseOnly": true

## Request:

```cs
{
    "searchCriteria": {
        "ProductIds": [
            68719498155
        ],
        "QuantityUnitTypeValue": 2,
        "DefaultWarehouseOnly": true,
			"FilterByChannelFulfillmentGroup" : false
    }
}
```

## Response:

```cs

{
	"@odata.context": "https://<<RetailServerURL>>/Commerce/$metadata#Microsoft.Dynamics.Commerce.Runtime.DataModel.ProductWarehouseInventoryInformation",
	"ProductWarehouseInventoryAvailabilities": [
		{
			"ProductId": 68719498155,
			"InventLocationId": "DC-CENTRAL",
			"DataAreaId": "usrt",
			"PhysicalInventory": 65,
			"PhysicalReserved": 0,
			"TotalAvailable": 65,
			"TotalAvailableInventoryLevelLabel": "In stock",
			"TotalAvailableInventoryLevelCode": "AVAIL",
			"OrderedInTotal": 0,
			"PhysicalAvailable": 65,
			"PhysicalAvailableInventoryLevelLabel": "In stock",
			"PhysicalAvailableInventoryLevelCode": "AVAIL",
			"LastInventoryTransactionId": 68720284617,
			"UnpostedOnlineOrderedQuantity": 0,
			"UnpostedFulfilledQuantity": 0,
			"IsInventoryAvailabilityQuantityReturned": true,
			"UnprocessedQuantity": 0,
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 60,
			"MaximumPurchasableTotalAvailableQuantity": 60,
			"SumUncountedTransactions": 0,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		}
	],
	"AggregatedProductInventoryAvailabilities": [
		{
			"ProductId": 68719498155,
			"DataAreaId": "usrt",
			"TotalAvailableQuantity": 65,
			"TotalAvailableInventoryLevelLabel": "In stock",
			"TotalAvailableInventoryLevelCode": "AVAIL",
			"PhysicalAvailableQuantity": 65,
			"PhysicalAvailableInventoryLevelLabel": "In stock",
			"PhysicalAvailableInventoryLevelCode": "AVAIL",
			"QuantityUnitTypeValue": 2,
			"UnitOfMeasure": "ea",
			"MaximumPurchasablePhysicalAvailableQuantity": 60,
			"MaximumPurchasableTotalAvailableQuantity": 60,
			"IgnoreQuantityUnitType": false,
			"ExtensionProperties": []
		}
	],
	"ExtensionProperties": []
}


```

## Steps to Integrate Third-Party Applications

1. Authentication: Ensure that the third-party application is authenticated to access the Dynamics 365 Commerce environment. This typically involves using OAuth tokens for secure access.
2. API Calls: Use the OOB APIs mentioned above to query inventory availability. The third-party application can make HTTP requests to these APIs, passing the necessary parameters such as product ID, variant ID, and warehouse ID.
3. Data Handling: Process the API responses to extract inventory data. The third-party application can then display this information to users or use it for further processing, such as updating stock levels or triggering alerts for low inventory.
4. Error Handling: Implement error handling mechanisms to manage API call failures or data inconsistencies. This ensures that the third-party application can gracefully handle any issues that arise during the integration process.

## Conclusion

Integrating third-party applications with Dynamics 365 Commerce, specifically the Commerce Scale Unit, provides businesses with real-time access to inventory data, enhancing their ability to meet customer demands efficiently. By leveraging the available OOB APIs, third-party applications can seamlessly query inventory availability, ensuring accurate and up-to-date stock information across various channels. This integration not only streamlines operations but also improves customer satisfaction by providing reliable inventory data.
