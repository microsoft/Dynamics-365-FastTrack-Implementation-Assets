using Microsoft.Dynamics.Commerce.RetailProxy;

namespace ProductPublisherApp.Interface
{
    /// <summary>
    /// This interface defines the template for the adapter to handle the products received from CRT.
    /// The PublishProducts method is used to control the publishing execution flow.
    /// </summary>
    internal interface IConnectorAdapter
    {
        /// <summary>
        /// Place the code to control the execution flow of the adapter here, using the received product collection.
        /// </summary>
        /// <param name="products"></param>
        /// <returns></returns>
        internal async Task PublishProducts(IEnumerable<Product> products)
        {
            await Task.Run(() => { });
        }
    }
}
