using Microsoft.WindowsAzure.Storage.Table;

namespace CIFadaptorServer
{
    public class ConnectionEntity : TableEntity
    {
        public ConnectionEntity(string userId, string connectionId, string hubName, int connectionStatus)
        {
            this.RowKey = connectionId;
            this.PartitionKey = userId;
            this.HubName = hubName;
            this.ConnectionStatus = connectionStatus;
        }

        public ConnectionEntity() { }

        public string UserId { get; set; }

        public string ConnectionId { get; set; }
        public int ConnectionStatus { get; set; }
        public string HubName { get; set; }
    }
}