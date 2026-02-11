using Azure.Messaging.EventGrid.SystemEvents;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SignalRCIFAdaptor
{
    // Class representing the structure of Event Grid event data
    public class EventGridDetails
    {
        public string EventType { get; set; }
        public string Subject { get; set; }
        public string Data { get; set; }
    }

    public class EventData
    { 
        public string userId { get; set; }
        public string connectionId { get; set; }
        public string hubName { get; set; }
        public string timeStamp { get; set; }


    }

}
