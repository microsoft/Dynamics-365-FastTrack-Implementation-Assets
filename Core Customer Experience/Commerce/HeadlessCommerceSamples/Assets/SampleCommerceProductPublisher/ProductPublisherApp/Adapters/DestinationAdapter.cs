using Microsoft.Dynamics.Commerce.RetailProxy;
using ProductPublisherApp.Interface;

namespace ProductPublisherApp.Adapters
{
    internal class DestinationAdapter : IConnectorAdapter
    {
#pragma warning disable CA1822 // Mark members as static
        internal async Task PublishProducts(IEnumerable<Product> products)
#pragma warning restore CA1822 // Mark members as static
        {
            foreach (var product in products)
            {
                // Your code to send the product to the External store goes here.
                _ = $"Product {product.RecordId} sent to External store.";
            }
            await Task.Run(() => { });
        }
    }
}