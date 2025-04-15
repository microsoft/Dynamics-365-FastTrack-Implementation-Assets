# Order integration 

**<span style="color:red">Do not publish. This article is under construction.</span>**


# Sales Order Field Mapping

Sure, I can help with that! The Sales Order creation process using Microsoft Dynamics 365 Headless Commerce involves several steps and components to ensure a seamless and efficient experience for both customers and businesses. Here is an overview of the process:

### Sales Order Creation Business Process


1. **Customer Interaction**: 
The process begins when a customer interacts with the e-commerce platform, either through a website, mobile app, or other digital channels. 
The customer browses products, adds items to their cart, and proceeds to checkout.

2. **Order Capture**: 
During checkout, the customer's order details, including product selections, quantities, and shipping information, are captured. 
This information is sent to the Commerce Scale Unit (CSU) via API calls.

3. **Order Validation**: 
The CSU validates the order details, ensuring that the products are available in inventory, the prices are correct, and any applicable discounts or promotions are applied.
The CSU also checks for any potential issues, such as invalid shipping addresses or payment methods.

4. **Payment Processing**: 
Once the order is validated, the payment processing step is initiated. 
The CSU integrates with various payment gateways to process the customer's payment securely. 
This step may involve tokenization of payment information for added security.
Please refer to the Payments page for more details on payment handling using the Headless Commerce Engine.

5. **Order Creation**: 
After successful payment processing, the CSU creates the sales order in the system. 
The order details are stored in the channel database, which holds transactional data and master data from various commerce channels.

6. **Order Confirmation**: 
The customer receives an order confirmation, either through email or within the e-commerce platform.
This confirmation includes order details, estimated delivery dates, and tracking information if applicable.

7. **Order Fulfillment**: 
The order fulfillment process begins, involving picking, packing, and shipping the products to the customer.
The CSU coordinates with warehouse management systems and logistics providers to ensure timely and accurate fulfillment.

8. **Order Tracking**:
Customers can track the status of their orders through the e-commerce platform.
The CSU provides real-time updates on order status, including shipping and delivery information.

9. **Post-Purchase Support**: 
After the order is delivered, customers may require post-purchase support, such as returns or exchanges.
The CSU facilitates these processes by integrating with customer service systems and providing necessary information for handling returns and refunds.

### Key Components

- **Commerce Scale Unit (CSU)**: The CSU is the core component of the headless commerce architecture. It handles API requests, business logic, and data storage for sales orders and other commerce transactions.
- **Channel Database**: The channel database stores transactional data and master data from various commerce channels. It ensures data consistency and availability across the entire commerce ecosystem.
- **Payment Gateways**: The CSU integrates with multiple payment gateways to process payments securely and efficiently.
- **Warehouse Management Systems**: These systems manage the picking, packing, and shipping of products, ensuring accurate and timely order fulfillment.
- **Customer Service Systems**: These systems handle post-purchase support, including returns, exchanges, and refunds.

This process ensures a seamless and efficient experience for both customers and businesses, leveraging the capabilities of Microsoft Dynamics 365 Headless Commerce to manage the entire sales order lifecycle.

### Sales Order Entity

| Field Name                        | Data Type | Description |
|-----------------------------------|-----------|-------------|
| IsRequiredAmountPaid              | Boolean   | Indicates if the required amount is paid |
| IsDiscountFullyCalculated         | Boolean   | Indicates if the discount is fully calculated |
| IgnoreDiscountCalculation         | Boolean   | Indicates if discount calculation should be ignored |
| AmountDue                         | Decimal   | Total amount due |
| AmountPaid                        | Decimal   | Total amount paid |
| IsTaxIncludedInPrice              | Boolean   | Indicates if tax is included in the price |
| BeginDateTime                     | DateTime  | Start date and time of the order |
| CartTypeValue                     | Integer   | Type of cart |
| ChannelId                         | Integer   | Identifier for the sales channel |
| ChargeAmount                      | Decimal   | Amount charged |
| CustomerOrderRemainingBalance     | Decimal   | Remaining balance for the customer order |
| Comment                           | String    | Additional comments |
| InvoiceComment                    | String    | Comments on the invoice |
| CustomerId                        | String    | Identifier for the customer |
| CustomerOrderModeValue            | Integer   | Mode of the customer order |
| DeliveryMode                      | String    | Mode of delivery |
| DiscountAmount                    | Decimal   | Total discount amount |
| DiscountAmountWithoutTax          | Decimal   | Discount amount excluding tax |
| DiscountCodes                     | String    | Codes applied for discounts |
| Id                                | String    | Unique identifier for the order |
| TransactionTypeValue              | Integer   | Type of transaction |
| IncomeExpenseTotalAmount          | Decimal   | Total income and expense amount |
| IsReturnByReceipt                 | Boolean   | Indicates if the return is by receipt |
| ReturnTransactionHasLoyaltyPayment| Boolean   | Indicates if the return transaction has loyalty payment |
| IsFavorite                        | Boolean   | Indicates if the order is marked as favorite |
| IsRecurring                       | Boolean   | Indicates if the order is recurring |
| IsSuspended                       | Boolean   | Indicates if the order is suspended |
| LoyaltyCardId                     | String    | ID of the loyalty card used |
| ModifiedDateTime                  | DateTime  | Date and time when the order was last modified |
| AvailableDepositAmount            | Decimal   | Available deposit amount for the order |
| PrepaymentAmountPaid              | Decimal   | Prepayment amount paid for the order |
| PrepaymentRoundingDifference      | Decimal   | Difference due to rounding in prepayment amount |
| PrepaymentAppliedOnPickup         | Decimal   | Prepayment amount applied on pickup |
| PrepaymentAmountInvoiced          | Decimal   | Invoiced prepayment amount |
| PromotionLines                    | String    | Lines for promotions applied |
| RequiredDepositAmount             | Decimal   | Required deposit amount |
| RequiredDepositWithoutCarryoutAmount | Decimal | Required deposit amount excluding carryout |
| StaffId                           | String    | Identifier for the staff member |
| SubtotalAmount                    | Decimal   | Subtotal amount |
| SubtotalAmountWithoutTax          | Decimal   | Subtotal amount excluding tax |
| NetPrice                          | Decimal   | Net price |
| SubtotalSalesAmount               | Decimal   | Subtotal sales amount |
| TaxAmount                         | Decimal   | Total tax amount |
| TaxOnCancellationCharge           | Decimal   | Tax on cancellation charge |
| TaxOnShippingCharge               | Decimal   | Tax on shipping charge |
| TaxOnNonShippingCharges           | Decimal   | Tax on non-shipping charges |
| TerminalId                        | String    | Identifier for the terminal |
| TotalAmount                       | Decimal   | Total amount |
| TotalSalesAmount                  | Decimal   | Total sales amount |
| TotalReturnAmount                 | Decimal   | Total return amount |
| TotalCarryoutSalesAmount          | Decimal   | Total carryout sales amount |
| TotalCustomerOrderSalesAmount     | Decimal   | Total customer order sales amount |
| TotalManualDiscountAmount         | Decimal   | Total manual discount amount |
| TotalManualDiscountPercentage     | Decimal   | Total manual discount percentage |
| WarehouseId                       | String    | Identifier for the warehouse |
| IsCreatedOffline                  | Boolean   | Indicates if the order was created offline |
| CartStatusValue                   | Integer   | Status of the cart |
| ReceiptTransactionTypeValue       | Integer   | Type of receipt transaction |
| CommissionSalesGroup              | String    | Sales group for commission |
| Version                           | Integer   | Version of the order |
| TotalItems                        | Integer   | Total number of items |
| HasTaxCalculationTriggered        | Boolean   | Indicates if tax calculation was triggered |
| HasChargeCalculationTriggered     | Boolean   | Indicates if charge calculation was triggered |
| ShippingChargeAmount              | Decimal   | Amount charged for shipping |
| OtherChargeAmount                 | Decimal   | Amount charged for other services |
| PeriodicDiscountsCalculateScopeValue | Integer | Scope value for periodic discounts calculation |
| TaxCalculationTypeValue           | Integer   | Type of tax calculation |
| CustomerRequisition               | String    | Customer requisition details |
| AffiliationLines                  | String    | Lines for affiliations applied |
| AttributeValues                   | String    | Attribute values |

### Order Lines

| Field Name                        | Data Type | Description |
|-----------------------------------|-----------|-------------|
| LineId                            | String    | Unique identifier for the line item |
| ItemId                            | String    | Unique identifier for the item |
| Barcode                           | String    | Barcode of the item |
| EntryMethodTypeValue              | Integer   | Method used to enter the item |
| Description                       | String    | Description of the item |
| InventoryDimensionId              | String    | Inventory dimension identifier |
| Comment                           | String    | Comment about the line item |
| ProductId                         | String    | Unique identifier for the product |
| WarehouseId                       | String    | Identifier for the warehouse |
| Quantity                          | Decimal   | Quantity of the item |
| Price                             | Decimal   | Price of the item |
| ExtendedPrice                     | Decimal   | Extended price of the item |
| TaxAmount                         | Decimal   | Tax amount for the item |
| ItemTaxGroupId                    | String    | Tax group identifier for the item |
| TotalAmount                       | Decimal   | Total amount for the line item |
| NetAmountWithoutTax               | Decimal   | Net amount excluding tax |
| NetPrice                          | Decimal   | Net price of the item |
| DiscountAmountWithoutTax          | Decimal   | Discount amount excluding tax |
| DiscountAmount                    | Decimal   | Total discount amount for the line item |
| LineDiscount                      | Decimal   | Line discount amount |
| LinePercentageDiscount            | Decimal   | Line percentage discount |
| LineManualDiscountPercentage      | Decimal   | Manual discount percentage for the line |
| LineManualDiscountAmount          | Decimal   | Manual discount amount for the line |
| UnitOfMeasureSymbol               | String    | Symbol for the unit of measure |
| DeliveryMode                      | String    | Mode of delivery for the line item |
| IsWarrantyLine                    | Boolean   | Indicates if the line item is a warranty |
| WarrantableTransactionId          | String    | Transaction ID for the warrantable item |
| WarrantableSalesId                | String    | Sales ID for the warrantable item |
| WarrantableLineNumber             | Integer   | Line number for the warrantable item |
| WarrantableSerialNumber           | String    | Serial number for the warrantable item |
| ReturnTransactionId               | String    | Transaction ID for the return |
| ReturnLineNumber                  | Integer   | Line number for the return |
| ReturnInventTransId               | String    | Inventory transaction ID for the return |
| ReturnStore                       | String    | Store for the return |
| ReturnTerminalId                  | String    | Terminal ID for the return |
| IsVoided                          | Boolean   | Indicates if the line item is voided |
| IsTaxOverideCodeTaxExempt         | Boolean   | Indicates if the line item is tax exempt |
| IsGiftCardLine                    | Boolean   | Indicates if the line item is a gift card |
| IsPriceKeyedIn                    | Boolean   | Indicates if the price was keyed in |
| GiftCardId                        | String    | ID of the gift card |
| GiftCardCurrencyCode              | String    | Currency code for the gift card |
| GiftCardOperationValue            | Integer   | Operation value for the gift card |
| GiftCardTypeValue                 | Integer   | Type value for the gift card |
| SalesStatusValue                  | Integer   | Sales status value |
| QuantityCanceled                  | Decimal   | Quantity canceled |
| FulfillmentStoreId                | String    | ID of the fulfillment store |
| SerialNumber                      | String    | Serial number of the item |
| ElectronicDeliveryEmail           | String    | Email for electronic delivery |
| ElectronicDeliveryEmailContent    | String    | Content of the electronic delivery email |
| IsPriceOverridden                 | Boolean   | Indicates if the price was overridden |
| IsInvoiceLine                     | Boolean   | Indicates if the line item is an invoice line |
| InvoiceId                         | String    | ID of the invoice |
| InvoiceAmount                     | Decimal   | Amount of the invoice |
| GiftCardBalance                   | Decimal   | Balance of the gift card |
| LineVersion                       | Integer   | Version of the line item |
| PromotionLines                    | String    | Lines for promotions applied |
| RelatedDiscountedLineIds          | String    | IDs of related discounted lines |
| TaxRatePercent                    | Decimal   | Tax rate percentage |
| IsCustomerAccountDeposit          | Boolean   | Indicates if the line item is a customer account deposit |
| LineNumber                        | Integer   | Line number |
| CommissionSalesGroup              | String    | Sales group for commission |
| StaffId                           | String    | ID of the staff member |
| CatalogId                         | Integer   | ID of the catalog |
| BarcodeEmbeddedPrice              | Decimal   | Price embedded in the barcode |
| PriceInBarcode                    | Boolean   | Indicates if the price is in the barcode |
| InvoiceTypeValue                  | Integer   | Type value for the invoice |
| DetailedLineStatusValue           | Integer   | Detailed status value for the line item |
| SalesAgreementLineRecordId        | Integer   | Record ID for the sales agreement line |
| PriceLines                        | String    | Lines for prices applied |
| RecordId                          | String    | Record ID |
| Value                             | Decimal   | Value of the line item |
| PriceMethod                       | String    | Method used for pricing |
| OriginId                          | String    | Origin ID |
| PriceChangedByExtensions          | Boolean   | Indicates if the price was changed by extensions |
| SaleLineNumber                    | Integer   | Sale line number |
| ExtensionProperties               | String    | Extension properties |
| DiscountLines                     | String    | Lines for discounts applied |
| ReasonCodeLines                   | String    | Lines for reason codes applied |
| ChargeLines                       | String    | Lines for charges applied |
| ChargeLineId                      | String    | ID of the charge line |
| ChargeCode                        | String    | Code for the charge |
| CurrencyCode                      | String    | Currency code |
| ModuleTypeValue                   | Integer   | Type value for the module |
| IsHeaderChargeProrated            | Boolean   | Indicates if the header charge is prorated |
| ChargeTypeValue                   | Integer   | Type value for the charge |
| ChargeMethodValue                 | Integer   | Method value for the charge |
| CalculatedAmount                  | Decimal   | Calculated amount for the charge |
| Description                       | String    | Description of the charge |
| MarkupAutoLineRecordId            | Integer   | Record ID for the markup auto line |
| MarkupAutoTableRecId              | Integer   | Table record ID for the markup auto line |
| SaleLineNumber                    | Integer   | Sale line number |
| FromAmount                        | Decimal   | From amount for the charge |
| ToAmount                          | Decimal   | To amount for the charge |
| Keep                              | Decimal   | Keep amount for the charge |
| AmountRefunded                    | Decimal   | Amount refunded |
| IsRefundable                      | Boolean   | Indicates if the charge is refundable |
| IsShipping                        | Boolean   | Indicates if the charge is for shipping |
| IsOverridden                      | Boolean   | Indicates if the charge is overridden |
| IsInvoiced                        | Boolean   | Indicates if the charge is invoiced |
| CalculatedProratedAmount          | Decimal   | Calculated prorated amount for the charge |
| SpecificUnitSymbol                | String    | Specific unit symbol for the charge |
| Quantity                          | Decimal   | Quantity for the charge |
| Price                             | Decimal   | Price for the charge |
| ItemTaxGroupId                    | String    | Tax group ID for the item |
| TaxAmount                         | Decimal   | Tax amount for the charge |
| NetAmount                         | Decimal   | Net amount for the charge |
| NetAmountPerUnit                  | Decimal   | Net amount per unit for the charge |
| GrossAmount                       | Decimal   | Gross amount for the charge |
| TaxAmountExemptInclusive          | Decimal   | Tax amount exempt inclusive for the charge |
| TaxAmountInclusive                | Decimal   | Tax amount inclusive for the charge |
| TaxAmountExclusive                | Decimal   | Tax amount exclusive for the charge |
| NetAmountWithAllInclusiveTax      | Decimal   | Net amount with all inclusive tax for the charge |
| BeginDateTime                     | DateTime  | Start date and time for the charge |
| EndDateTime                       | DateTime  | End date and time for the charge |
| TaxRatePercent                    | Decimal   | Tax rate percentage for the charge |
| IsReturnByReceipt                 | Boolean   | Indicates if the charge is return by receipt |
| ReturnLineTaxAmount               | Decimal   | Tax amount for the return line |
| TaxExemptPriceInclusiveReductionAmount | Decimal | Tax exempt price inclusive reduction amount |
| TaxExemptPriceInclusiveOriginalPrice | Decimal | Tax exempt price inclusive original price |
| ChargeLineOverrides               | String    | Overrides for the charge line |
| ReasonCodeLines                   | String    | Lines for reason codes applied |
| TaxLines                          | String    | Lines for taxes applied |
| TaxMeasures                       | String    | Measures for taxes applied |
| ReturnTaxLines                    | String    | Lines for return taxes applied |
| ExtensionProperties               | String    | Extension properties |
| AttributeValues                   | String    | Attribute values |
| ThirdPartyGiftCardInfo            | String    | Information for third party gift cards |
| Amount                            | Decimal   | Amount for the charge |
| Authorization                     | String    | Authorization for the charge |
| ExtensionProperties               | String    | Extension properties |
```
