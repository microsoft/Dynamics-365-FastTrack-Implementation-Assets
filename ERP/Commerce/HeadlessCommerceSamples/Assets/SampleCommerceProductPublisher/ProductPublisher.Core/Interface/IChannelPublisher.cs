/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

using Microsoft.Dynamics.Commerce.RetailProxy;

namespace ProductPublisher.Core.Interface
{
    public interface IChannelPublisher
    {
        void OnProductCategoriesAvailable(Tuple<IEnumerable<Category>, Dictionary<long, IEnumerable<AttributeCategory>>> categoriesInfo);

        void OnProductAttributesAvailable(IEnumerable<AttributeProduct> attributes);
    }
}
