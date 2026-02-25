/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using ProductPublisher.Core.Interface;

namespace ProductPublisherApp
{
    /// <summary>
    /// Initializes a new instance of the <see cref="ProductPublisherApp"/> class.
    /// </summary>
    /// <param name="loggerFactory"></param>
    /// <param name="publisher"></param>
    public class ProductPublisherApp(ILoggerFactory loggerFactory, IPublisher publisher)
    {
        private readonly ILogger _logger = loggerFactory.CreateLogger<ProductPublisherApp>();
        private readonly IPublisher _publisher = publisher;

        [Function("ProductPublisherApp")]
        [System.Diagnostics.CodeAnalysis.SuppressMessage("Usage", "CA2254:Template should be a static expression", Justification = "Messages can be different")]
        public async Task Run([TimerTrigger("0 */5 * * * *"
#if DEBUG
                ,RunOnStartup=true
#endif
            )] TimerInfo myTimer)
        {
            try
            {
                _logger.LogInformation($"ProductPublisher timer trigger function executed at: {DateTime.Now}");

                if (myTimer.ScheduleStatus is not null)
                {
                    _logger.LogInformation($"ProductPublisher next timer schedule at: {myTimer.ScheduleStatus.Next}");
                }
                await _publisher.InitializeChannelConfiguration();
                await _publisher.PublishChannel();
                await _publisher.PublishCatalog();
                _logger.LogInformation($"ProductPublisher timer trigger function finished at: {DateTime.Now}");
            }
            catch (Exception ex)
            {
                _logger.LogError($"An error occurred: {ex.Message}");
            }
        }

    }
}
