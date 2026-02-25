using Microsoft.Dynamics.Commerce.RetailProxy;
using ProductPublisher.Core.Interface;

namespace ProductPublisherApp
{
    internal class ChannelPublisher : IChannelPublisher
    {


        public void OnProductCategoriesAvailable(Tuple<IEnumerable<Category>, Dictionary<long, IEnumerable<AttributeCategory>>> categoriesInfo)
        {

        }

        public void OnProductAttributesAvailable(IEnumerable<AttributeProduct> attributes)
        {
        }
    }
}
