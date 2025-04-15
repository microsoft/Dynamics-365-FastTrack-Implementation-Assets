/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace SampleConsoleAppUploadOrder
{
    using Microsoft.Dynamics.Commerce.RetailProxy;
    using SampleConsoleApp.Common;

    class OrderHelper
    {
        /// <summary>
        /// Fill order
        /// </summary>
        /// <returns></returns>
        public static async Task<SalesOrder> FillOrder(CommerceClient client)
        {
            string transactionId = "fabrikamonline" + DateTime.Now.ToString("yyyyMMddHHmmss");
            SalesOrder order = new()
            {
                AmountDue = 0,
                AmountPaid = 629.48M,
                ChannelId = client.ChannelId,
                CreatedDateTime = DateTime.Now,
                BeginDateTime= DateTime.Now,
                CurrencyCode = "USD",
                CustomerId = "004009",
                DiscountAmount = 82.5M,
                DiscountAmountWithoutTax = 82.5M,
                GrossAmount = 629.48M,
                Id = transactionId,
                NetAmountWithNoTax = 592.45M,
                NetAmountWithTax = 629.48M,
                NetAmountWithoutTax= 592.45M,
                NetAmount =592.45M,
                SubtotalAmount = 592.45M,
                SubtotalAmountWithoutTax = 592.45M,
                TaxAmount = 37.03M,
                TotalAmount = 629.48M,
                NetPrice=674.95M,
                TransactionTypeValue = (int?)TransactionType.PendingSalesOrder,
                ReceiptEmail = "test@test.com",
                ChannelReferenceId= Guid.NewGuid().ToString(),
                NumberOfItems=2
            };
            await FillOrderLines(order);
            await FillPayments(client, order);
            return order;
        }

        /// <summary>
        /// Fill order lines
        /// </summary>
        /// <returns></returns>
        public static async Task<SalesOrder> FillOrderLines(SalesOrder order)
        {
            SalesLine line1 = new()
            {
                ProductId = 22565430667,
                OriginalPrice = 275M,
                TotalAmount = 204.53M,
                PeriodicDiscount = 82.5M,
                UnitOfMeasureSymbol = "ea",
                ItemId = "81325",
                Description = "Silver Chronograph Watch",
                Quantity = 1,
                Price = 275M,
                ItemTaxGroupId = "RP",
                SalesTaxGroupId = "TX",
                TaxAmount = 12.03M,
                SalesOrderUnitOfMeasure = "ea",
                NetAmount = 192.5M,
                GrossAmount = 192.5M,
                NetAmountWithAllInclusiveTax = 192.5M,
                NetAmountWithoutTax=192.5M,
                LineNumber = 1,
                DeliveryMode="99",
                LineDiscount= 82.5M,
                DiscountAmount= 82.5M,
                ShippingAddress = new()
                {
                    Name = "John Doe",
                    Street = "100 Main St",
                    City = "Bellevue",
                    State = "WA",
                    ZipCode = "98004",
                    ThreeLetterISORegionName = "USA",
                },
                InventoryLocationId= "DC-CENTRAL"
            };
            line1.DiscountLines.Add(new DiscountLine()
            {
                SaleLineNumber = 1,
                OfferId = "ST100015",
                OfferName = "Watches",
                DiscountCost = 82.5M,
                EffectiveAmount = 82.5M,
                Percentage = 30,
                DiscountLineTypeValue = 2,
            });
            line1.TaxLines.Add(new()
            {
                TaxBasis = -192.5M,
                TaxCode = "RP_TXST",
                Amount = 12.03M,
                SaleLineNumber = 1,
                TransactionId = order.Id
            });
            SalesLine line2 = new()
            {
                ProductId = 22565429697,
                OriginalPrice = 399.95M,
                TotalAmount = 424.95M,
                InventoryDimensionId = "004342",
                UnitOfMeasureSymbol = "ea",
                ItemId = "81108",
                Description = "Trim Blazer",
                Quantity = 1,
                Price = 399.95M,
                ItemTaxGroupId = "RP",
                SalesTaxGroupId = "TX",
                TaxAmount = 25M,
                SalesOrderUnitOfMeasure = "ea",
                NetAmount = 399.95M,
                GrossAmount = 399.95M,
                NetAmountWithAllInclusiveTax = 399.95M,
                NetAmountWithoutTax = 399.95M,
                LineNumber = 2,
                LineDiscount=0,
                DiscountAmount=0,
                DeliveryMode = "99",
                ShippingAddress = new()
                {
                    Name = "John Doe",
                    Street = "100 Main St",
                    City = "Bellevue",
                    State = "WA",
                    ZipCode = "98004",
                    ThreeLetterISORegionName = "USA",
                },
                InventoryLocationId = "DC-CENTRAL"
            };
            line2.TaxLines.Add(new()
            {
                TaxBasis = -399.95M,
                TaxCode = "RP_TXST",
                Amount = 25M,
                SaleLineNumber = 2,
                TransactionId = order.Id
            });
            order.SalesLines.Add(line1);
            order.SalesLines.Add(line2);
            return await Task.Run(() => order);
        }

        public static async Task<SalesOrder> FillPayments(CommerceClient client, SalesOrder order)
        {
            string authToken = System.IO.File.ReadAllText(Path.Combine(Directory.GetParent(Directory.GetCurrentDirectory()).Parent.Parent.FullName, "AuthToken.xml"));
            string cardToken = System.IO.File.ReadAllText(Path.Combine(Directory.GetParent(Directory.GetCurrentDirectory()).Parent.Parent.FullName, "CardToken.xml"));
            order.TenderLines.Add(new()
            {
                TransactionId = order.Id,
                AuthorizedAmount= 629.48M,
                TenderDate = DateTime.Now,
                CardTypeId = "Visa",
                MaskedCardNumber = "************1111",
                ChannelId= client.ChannelId,
                Currency="USD",
                TenderTypeId="3",
                LineNumber= 1,
                IsPreProcessed = true,
                IsVoidable = true,
                TenderLineId ="1",
                ExchangeRate=0.00M,
                CompanyCurrencyExchangeRate=0.00M,
                ProcessingTypeValue = (int)PaymentProcessingType.Deferred,
                StatusValue = (int)TenderLineStatus.NotProcessed,
                TransactionStatusValue = (int)TransactionStatus.Normal,
                //Without compression
                Authorization = "<![CDATA[" + authToken + "]]>",
                CardToken = "<![CDATA[" + authToken + "]]>"
            });
            return await Task.Run(() => order);
        }
    }
}
