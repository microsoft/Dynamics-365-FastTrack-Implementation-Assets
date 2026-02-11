/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace SampleConsoleApp.Common
{
    using Microsoft.Dynamics.Commerce.RetailProxy;
    using Microsoft.Dynamics.Commerce.Runtime;

    using System;
    using System.Collections.Generic;
    using System.Collections.ObjectModel;
    using System.Linq;
    using System.Runtime.InteropServices;
    using System.Threading.Tasks;

    /// <summary>
    /// Initialized a new instance of the <see cref="ConsoleStorefront"/> class.
    /// </summary>
    /// <param name="factory">The factory instance to create proxy managers.</param>
    public sealed class CommerceClient(ManagerFactory factory, ILogger logger)
    {
        private readonly ManagerFactory factory = factory;
        private long channelId;
        private readonly ILogger logger = logger;
        public ManagerFactory Factory => factory;
        public long ChannelId => channelId;
        public ILogger Logger => logger;

        /// <summary>
        /// Initializes the context on the factory and caches the channel identifier that
        /// is used across many different API calls.
        /// </summary>
        public async Task InitializeContext()
        {
            ChannelIdentity channelIdentity = await this.ResolveOperatingUnitNumber();
            if (string.IsNullOrWhiteSpace(channelIdentity.OperatingUnitNumber))
            {
                // No online store. 
                return;
            }

            // Save the channel identifier for future API calls.
            this.channelId = channelIdentity.RecordId;

            // Set the corresponding OUN of the channel on the context for all outgoing API calls.

            factory.Context.SetOperatingUnitNumber(channelIdentity.OperatingUnitNumber);
            factory.Context.SetChannelId("\"" + this.channelId + "\"");
            this.Logger.Info($"> Welcome to {channelIdentity.Name} (oun={channelIdentity.OperatingUnitNumber}, channel={channelIdentity.RecordId}, company={channelIdentity.DataAreaId})");
            await Task.CompletedTask;
        }

        /// <summary>
        /// This method uses the Commerce API to retrieve the first online store and uses that for the
        /// context of this console application.
        /// </summary>
        /// <param name="factory">An instance of the proxy factory.</param>
        /// <returns>The first channel of type online store.</returns>
        private async Task<ChannelIdentity> ResolveOperatingUnitNumber()
        {
            IStoreOperationsManager storeOperationsManager = this.Factory.GetManager<IStoreOperationsManager>();

            var settings = new QueryResultSettings
            {
                Paging = new PagingInfo
                {
                    Top = 100,
                    Skip = 0
                },
            };

            string onlineStoreChannelType = RetailChannelType.SharePointOnlineStore.ToString();
            var channels = await storeOperationsManager.GetChannelsByType(onlineStoreChannelType, settings).ConfigureAwait(false);
            if (!channels.Any())
            {
                this.Logger.Error($"There were no online channels at this endpoint. Ensure an online store is configured.");
                return null;
            }

            this.Logger.Info($"> Select an online channel to start.");
            foreach (ChannelIdentity channel in channels)
            {
                this.Logger.Info($"> [{channel.OperatingUnitNumber,10}] {channel.Name}");
            }

            string oun = this.Logger.GetUserTextInput($"Enter operating unit number (e.g. 128): ");
            return channels.First(x => x.OperatingUnitNumber == oun);
        }

        /// <summary>
        /// Returns the product identifier of the first result when searching by the specified keyword.
        /// </summary>
        /// <param name="keyword">The search term.</param>
        /// <returns>The product identifier of the first search result.</returns>
        public async Task SearchProductsByKeyword(string keyword)
        {
            IProductManager productManager = factory.GetManager<IProductManager>();

            var criteria = new ProductSearchCriteria
            {
                Context = new ProjectionDomain
                {
                    ChannelId = this.channelId,
                    CatalogId = 0,
                },
                SearchCondition = keyword,
            };

            var settings = new QueryResultSettings
            {
                Paging = new PagingInfo
                {
                    Top = 10,
                    Skip = 0
                },
            };

            var products = await productManager.Search(criteria, settings);

            Console.WriteLine();
            logger.Log(LogStatus.Info, $"> There were {products.Count()} search results found.");
            foreach (Product product in products)
            {
                logger.Log(LogStatus.Info, $"> [{product.ItemId,10}] {product.SearchName,-20} ${product.Price,5}");
            }
        }

        /// <summary>
        /// Creates a new cart.
        /// </summary>
        /// <returns>new cart</returns>
        public async Task<Cart> CreateCart()
        {
            ICartManager cartManager = factory.GetManager<ICartManager>();

            Cart cart = new()
            {
                Id = ""
            };

            cart = await cartManager.Create(cart);

            logger.Log(LogStatus.Info, $"> A cart is created. Cart Id {cart.Id}.");

            return cart;
        }

        /// <summary>
        /// Adds the specified product or list of products to the cart.
        /// </summary>
        /// <param name="cartId">If not specified, a secure identifier is generated for you.</param>
        /// <param name="productId">The product to add.</param>
        /// <param name="quantity">The quantity to add. This is an optional parameter.</param>
        /// <param name="cartVersion">The cart version used to validate optimistic concurrency. This is an optional parameter.</param>
        /// <returns>The cart identifier.</returns>
        public async Task<Cart> AddItemsToCartAsync(string cartId, long productId, decimal quantity = 1, long? cartVersion = null)
        {
            ICartManager cartManager = factory.GetManager<ICartManager>();

            var cartLine = new CartLine
            {
                LineId = string.Empty, // To be generated by the server.
                ProductId = productId,
                Quantity = quantity
            };

            var cart = await cartManager.AddCartLines(cartId, [cartLine], cartVersion);
            logger.Log(LogStatus.Info, $"> A new item has been added to the cart. There are now {cart.CartLines.Count} lines in the cart.");

            return cart;
        }

        /// <summary>
        /// Creates a sales order from the specified cart.
        /// </summary>
        /// <param name="cartId">The cart identifier.</param>
        /// <param name="amountDue">The amount due. This should be the total balance remaining to be paid.</param>
        /// <param name="receiptEmail">The customer's email address. This is a required field for e-commerce scenarios.</param>
        /// <returns>The sales order.</returns>
        public async Task<SalesOrder> Checkout(string cartId, decimal? amountDue, string receiptEmail)
        {
            ICartManager cartManager = factory.GetManager<ICartManager>();
            IOrgUnitManager orgUnitManager = factory.GetManager<IOrgUnitManager>();

            var channelConfiguration = orgUnitManager.GetOrgUnitConfiguration().Result;

            string cardToken = System.IO.File.ReadAllText("CardToken.xml");
            await Task.CompletedTask;

            //Tokenized card
            CartTenderLine tenderLine = new()
            {
                TenderLineId = string.Empty,
                Amount = amountDue.GetValueOrDefault(),
                TenderTypeId = "3", // Card
                Currency = channelConfiguration.Currency,
                ProcessingTypeValue = (int)PaymentProcessingType.Deferred,
                IsVoidable = true,
                VoidStatusValue = (int)TenderLineVoidStatus.None,
                StatusValue = (int)TenderLineStatus.NotProcessed,
                TokenizedPaymentCard = new TokenizedPaymentCard
                {
                    CardTypeId = "Visa",
                    CardTokenInfo = new CardTokenInfo
                    {
                        CardToken = $"<![CDATA[{cardToken}]]>",
                        MaskedCardNumber = "************1111",
                        ServiceAccountId = "serviceaccount",
                        UniqueCardId = "cardid",
                    },
                },
            };
            var cartTenderLines = new CartTenderLine[] { tenderLine };
            var salesOrder = cartManager.Checkout(
                cartId,
                receiptEmail,
                null,
                receiptNumberSequence: string.Empty,
                cartTenderLines, null
                ).Result;
            return salesOrder;
        }

        /// <summary>
        /// Prints out the supported delivery methods for the cart and specified shipping address.
        /// </summary>
        /// <param name="cartId">The cart identifier.</param>
        /// <param name="address">The shipping address.</param>
        public async Task PrintDeliveryOptions(string cartId, Address address)
        {
            ICartManager cartManager = factory.GetManager<ICartManager>();

            var settings = new QueryResultSettings
            {
                Paging = new PagingInfo
                {
                    Top = 10,
                    Skip = 0
                },
            };

            var options = await cartManager.GetDeliveryOptions(id: cartId, shippingAddress: address, cartLineIds: null, queryResultSettings: settings);

            logger.Log(LogStatus.Info, $"> The are {options.Count()} shipping options available.");
            foreach (DeliveryOption option in options)
            {
                logger.Log(LogStatus.Info, $" > [{option.Code,-10}] {option.Description,-20}");
            }
        }


        /// <summary>
        /// This updates the cart with the changes provided.
        /// </summary>
        /// <param name="cart">The cart entity to update.</param>
        /// <returns>The latest cart object.</returns>
        public async Task<Cart> UpdateCart(Cart cart)
        {
            ICartManager cartManager = factory.GetManager<ICartManager>();
            return await cartManager.Update(cart);
        }

        /// <summary>
        /// This converts the user's shopping cart into a checkout cart.
        /// </summary>
        /// <param name="cartId">The cart identifier.</param>
        /// <returns>The latest cart object.</returns>
        public async Task<Cart> PrepareCartForCheckout(string cartId)
        {
            ICartManager cartManager = factory.GetManager<ICartManager>();

            return await cartManager.Copy(cartId, (int)CartType.Checkout);
        }

        /// <summary>
        /// Gets the latest iteration of the cart.
        /// </summary>
        /// <param name="cartId">The cart identifier.</param>
        /// <returns>The cart object.</returns>
        public async Task<Cart> GetCart(string cartId)
        {
            ICartManager cartManager = factory.GetManager<ICartManager>();

            return await cartManager.Read(cartId);
        }

        /// <summary>
        /// This method converts the friendly item identifiers to system-used product identifiers.
        /// </summary>
        /// <param name="itemId">The user selected item identifier.</param>
        /// <returns>The product identifier.</returns>
        public long ConvertItemIdToProductId(string itemId)
        {
            IProductManager productManager = factory.GetManager<IProductManager>();

            var criteria = new ProductSearchCriteria
            {
                Context = new ProjectionDomain
                {
                    ChannelId = this.channelId,
                    CatalogId = 0,
                },
            };

            var productLookup = new ProductLookupClause { ItemId = itemId };
            criteria.ItemIds.Add(productLookup);

            var settings = new QueryResultSettings
            {
                Paging = new PagingInfo
                {
                    Top = 1,
                    Skip = 0
                },
            };

            var products = productManager.Search(criteria, settings).Result;
            if (!products.Any())
            {
                return 0;
            }

            return products.FirstOrDefault().RecordId;
        }

        /// <summary>
        /// Validates the available inventory for the products in the cart.
        /// </summary>
        /// <param name="cart"></param>
        /// <returns>True, If qty exists for all the items in the cart or else false.</returns>
        public async Task<bool> ValidateInventQtyforCart(Cart cart)
        {
            bool invQtyExists = true;
            IProductManager productManager = factory.GetManager<IProductManager>();

            logger.Log(LogStatus.Info, $"> Validating available inventory for products in cart.");

            List<long> productIds = [.. cart.CartLines.Select(x => x.ProductId.GetValueOrDefault())];

            InventoryAvailabilitySearchCriteria searchCriteria = new()
            {
                ProductIds = [.. productIds],
                DefaultWarehouseOnly = false, // to avoid just searching default warehouse.
                FilterByChannelFulfillmentGroup = true,
                QuantityUnitTypeValue = 2, // sales qty.,
            };

            var productWarehouseInventoryInfo = await productManager.GetEstimatedAvailability(searchCriteria);

            foreach (var cartLine in cart.CartLines)
            {
                ProductInventoryAvailability availability = productWarehouseInventoryInfo.AggregatedProductInventoryAvailabilities
                    .FirstOrDefault(x => x.ProductId == cartLine.ProductId && x.MaximumPurchasablePhysicalAvailableQuantity >= cartLine.Quantity);

                if (availability == null)
                {
                    logger.Log(LogStatus.Error, $"> Insufficient inventory for product : {cartLine.ItemId}");
                    invQtyExists = false;
                }
            }

            return invQtyExists;
        }

        /// <summary>
        /// Searches for a sales order by its identifier.
        /// </summary>
        /// <param name="orderId">Sales id</param>
        /// <returns>Sales Order record</returns>
        public async Task<SalesOrder> SearchOrderByIdAsync(string orderId)
        {
            SalesOrder order = new();
            try
            {
                ISalesOrderManager salesOrderManager = factory.GetManager<ISalesOrderManager>();

                order = await salesOrderManager.GetSalesOrderDetailsBySalesId(orderId);

                logger.Log(LogStatus.Info, $"> Order found: {order.Id}");


            }
            catch (Exception ex)
            {
                logger.Log(LogStatus.Error, ex.Message);
            }
            return order;
        }

        /// <summary>
        /// Cancel order
        /// </summary>
        /// <param name="orderId"></param>
        /// <returns></returns>
        public async Task<OrderCancellationResult> CancelOrderAsync(string orderId)
        {
            logger.Log(LogStatus.Info, $"> Cancelling order {orderId}");

            ISalesOrderManager salesOrderManager = factory.GetManager<ISalesOrderManager>();
            SalesOrdersLookupCriteria salesOrdersLookupCriteria = new();

            SalesOrderLookup lookup = new SalesOrderLookupBySalesId
            {
                SalesId = orderId
            };

            salesOrdersLookupCriteria.SalesOrderLookups.Add(lookup);

            var result = await salesOrderManager.RequestCancellation(salesOrdersLookupCriteria);

            logger.Log(LogStatus.Info, $"> Order cancelled: {orderId}");

            return result;

        }

        /// <summary>
        /// Upload order
        /// </summary>
        /// <param name="orderId"></param>
        /// <returns></returns>
        public async Task<SalesOrder> UploadOrder(SalesOrder salesOrder)
        {
            ISalesOrderManager salesOrderManager = factory.GetManager<ISalesOrderManager>();
            SalesOrder order = await salesOrderManager.Create(salesOrder);
            return order;

        }

        /// <summary>
        /// If the selected product is a master, we need to pick a variant. For now, we just pick the first variant
        /// to make this client application work.
        /// </summary>
        /// <param name="productId">The product identifier to resolve to a variant if available.</param>
        /// <returns>The variant if one exists; otherwise, the original product identifier is returned.</returns>
        public async Task<long> ResolveVariantIfProductMaster(long productId)
        {
            var selectecProductDimValue = new List<KeyValuePair<int, ProductDimensionValue>>();

            IProductManager productManager = this.Factory.GetManager<IProductManager>();

            SimpleProduct product = await productManager.GetById(productId, this.ChannelId);


            if (product.ProductTypeValue == (int)ProductType.Master)
            {
                Console.WriteLine($"> This product is a master product. We need to pick a specific variant to add to cart.");

                if (product.Dimensions.Any())
                {
                    this.Logger.Info($"> Select product dimensions of the product.");

                    foreach (var dimension in product.Dimensions)
                    {
                        string dimensionName = dimension.DimensionTypeValue switch
                        {
                            1 => "Color",
                            2 => "Configuration",
                            3 => "Size",
                            4 => "Style",
                            _ => "Non valid dimension",
                        };

                        var dimSettings = new QueryResultSettings
                        {
                            Paging = new PagingInfo
                            {
                                Top = 10,
                                Skip = 0
                            },
                        };

                        var dimensionValues = await productManager.GetDimensionValues(product.RecordId, this.ChannelId, dimension.DimensionTypeValue, [], null, dimSettings);

                        string dimvalue = string.Empty;

                        if (dimensionValues == null || !dimensionValues.Any())
                        {
                            this.Logger.Error($"No dimension values found for {dimensionName}");
                            continue;
                        }
                        else if (dimensionValues.Count() == 1)
                        {
                            dimvalue = dimensionValues.First().Value;
                            this.Logger.Info($"> {dimvalue} Selected for {dimensionName}");
                        }
                        else
                        {
                            this.Logger.Info($"> Select {dimensionName}");

                            foreach (ProductDimensionValue dim in dimensionValues)
                            {
                                this.Logger.Info($"{dim.Value}");
                            }

                            dimvalue = this.Logger.GetUserTextInput($"Enter {dimensionName} from the above list : ");
                        }

                        ProductDimensionValue selectedDim = dimensionValues?.FirstOrDefault(x => x.Value == dimvalue);

                        if (selectedDim != null)
                        {
                            selectecProductDimValue.Add(new KeyValuePair<int, ProductDimensionValue>(dimension.DimensionTypeValue, selectedDim));
                        }
                        else
                        {
                            this.Logger.Error($"Invalid dimension value or product does not exist with the dimenison combinaiton: {dimvalue}");
                        }
                    }
                }

                var settings = new QueryResultSettings
                {
                    Paging = new PagingInfo
                    {
                        Top = 10,
                        Skip = 0
                    },
                };

                List<ProductDimension> productDimensions = [];

                foreach (KeyValuePair<int, ProductDimensionValue> dimension in selectecProductDimValue)
                {
                    productDimensions.Add(new ProductDimension
                    {
                        DimensionTypeValue = dimension.Key,
                        DimensionValue = dimension.Value
                    });
                }

                var variants = productManager.GetVariantsByDimensionValues(product.RecordId, this.ChannelId, productDimensions, settings).Result;
                var variant = variants.FirstOrDefault();

                if (variant != null)
                {
                    return variant.RecordId;
                }
            }

            return product.RecordId;
        }

    }
}

