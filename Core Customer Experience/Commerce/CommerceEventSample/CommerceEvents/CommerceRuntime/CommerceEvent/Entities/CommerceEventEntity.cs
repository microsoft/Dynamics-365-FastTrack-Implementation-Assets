/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

namespace CommerceEvent.CommerceRuntime.Entities.DataModel
{
    using System;
    using System.Runtime.Serialization;
    using Microsoft.Dynamics.Commerce.Runtime.ComponentModel.DataAnnotations;
    using Microsoft.Dynamics.Commerce.Runtime.DataModel;
    using SystemAnnotations = System.ComponentModel.DataAnnotations;

    /// <summary>
    /// Defines a simple class that holds information about opening and closing times for a particular day.
    /// </summary>
    public class CommerceEventEntity : CommerceEntity
    {
        private const string EventDateTimeColumn = "EVENTDATETIME";
        private const string EventTypeColumn = "EVENTTYPE";
        private const string EventChannelIdColumn = "EVENTCHANNELID";
        private const string EventCustomerIdColumn = "EVENTCUSTOMERID";
        private const string EventDataColumn = "EVENTDATA";
        private const string EventTransactionIdColumn = "EVENTTRANSACTIONID";
        private const string EventTerminalIdColumn = "EVENTTERMINALID";
        private const string EventStaffIdColumn = "EVENTSTAFFID";
        private const string EventDataAreaIdColumn = "EVENTDATAAREAID";

        /// <summary>
        /// Initializes a new instance of the <see cref="CommerceEventEntity"/> class.
        /// </summary>
        public CommerceEventEntity()
            : base("CommerceEvent")
        {
        }

        [SystemAnnotations.Key]
        [Column(EventTransactionIdColumn)]
        public string EventTransactionId
        {
            get { return (string)this[EventTransactionIdColumn]; }
            set { this[EventTransactionIdColumn] = value; }
        }

        [SystemAnnotations.Key]
        [DataMember]
        [Column(EventDateTimeColumn)]
        public DateTime EventDateTime
        {
            get { return (DateTime)this[EventDateTimeColumn]; }
            set { this[EventDateTimeColumn] = value; }
        }

        [SystemAnnotations.Key]
        [DataMember]
        [Column(EventTypeColumn)]
        public string EventType
        {
            get { return (string)this[EventTypeColumn]; }
            set { this[EventTypeColumn] = value; }
        }

        [SystemAnnotations.Key]
        [DataMember]
        [Column(EventDataAreaIdColumn)]
        public string EventDataAreaId
        {
            get { return (string)this[EventDataAreaIdColumn]; }
            set { this[EventDataAreaIdColumn] = value; }
        }

        [DataMember]
        [Column(EventDataColumn)]
        public string EventData
        {
            get { return (string)this[EventDataColumn]; }
            set { this[EventDataColumn] = value; }
        }

        [DataMember]
        [Column(EventChannelIdColumn)]
        public long EventChannelId 
        { 
            get { return (long)this[EventChannelIdColumn]; }
            set { this[EventChannelIdColumn] = value; }
        }

        [DataMember]
        [Column(EventTerminalIdColumn)]
        public string EventTerminalId 
        {
            get { return (string)this[EventTerminalIdColumn]; }
            set { this[EventTerminalIdColumn] = value; }
        }

        [DataMember]
        [Column(EventStaffIdColumn)]
        public string EventStaffId
        {
            get { return (string)this[EventStaffIdColumn]; }
            set { this[EventStaffIdColumn] = value; }
        }

        [DataMember]
        [Column(EventCustomerIdColumn)]
        public string EventCustomerId
        {
            get { return (string)this[EventCustomerIdColumn]; }
            set { this[EventCustomerIdColumn] = value; }
        }
    }
}