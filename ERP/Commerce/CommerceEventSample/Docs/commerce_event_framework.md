# Commerce Event Framework

## Overview

The **Commerce Event Framework** is designed to overcome the limitations of traditional integration methodologies by providing a robust, scalable, and reliable event-driven architecture. This framework is pivotal for integrating Dynamics 365 Commerce with Dynamics 365 Customer Insights Journeys (CIJ) and other third-party systems, enabling real-time decision-making and seamless customer interactions.

## Challenges Addressed

Traditional integration approaches often encounter several challenges:

- **Fire-and-Forget Limitations**: Events are dispatched without confirmation of receipt, risking potential data loss.
- **Latency Issues**: Delays in data processing can result in outdated information, hindering real-time decision-making.
- **Inadequate Monitoring**: Limited event tracking makes troubleshooting and ensuring data integrity cumbersome.

The Commerce Event Framework effectively mitigates these challenges through its core features:

- **Persisted Event Storage**: Events are stored in a read-only event store, enhancing performance and scalability.
- **Near Real-Time Integration**: Ensures that customer data remains current by processing events almost instantaneously.
- **Reliability and Scalability**: Utilizes Azure Service Bus for dependable message delivery and scalable architecture to handle high event volumes.
- **Monitoring and Auditing**: Comprehensive event tracking capabilities streamline monitoring and troubleshooting.
- **Performance Optimization through CQRS**: Separates read and write operations to enhance both performance and scalability.

Designed with extensibility and scalability in mind, the Commerce Event Framework empowers developers to handle complex scenarios with ease. Below, we explore the key components that drive this framework, demonstrating how they collectively form a robust integration solution.

## Key Components

### 1. [CommerceEventsController](../CommerceEvents/CommerceRuntime/CommerceEvent/Controllers/CommerceEventsController.cs)

**Purpose**: Handles the main requests related to commerce events, providing endpoints for retrieving and searching events.

**Endpoints**:
- **GetAllCommerceEvents**: Retrieves all commerce events with pagination and filtering capabilities.
- **Search**: Searches for specific events based on criteria such as event type and date range.

**Features**:
- **Efficient Event Retrieval**: Utilizes `QueryResultSettings` to paginate and filter results, ensuring efficient data handling even with large datasets.
- **Flexibility**: Allows external applications to access relevant event data without unnecessary overhead.

### 2. [CommerceEventEntity](../CommerceEvents/CommerceRuntime/CommerceEvent/Entities/CommerceEventEntity.cs)

**Purpose**: Represents an individual commerce event within the framework.

**Attributes**:
- **EventTransactionId**: Unique identifier for the transaction.
- **EventDateTime**: Timestamp indicating when the event occurred.
- **EventType**: Type of event (e.g., `Checkout`, `AddCartLines`).
- **EventChannelId**, **EventCustomerId**, **EventStaffId**, **EventTerminalId**: Metadata fields capturing contextual details such as channel, customer, staff, and terminal involved.
- **EventData**: Serialized additional event-specific data.

**Significance**: Forms the backbone of the Commerce Event Framework by providing a structured format to store and retrieve detailed event information.

### 3. [CommerceEventDataService](../CommerceEvents/CommerceRuntime/CommerceEvent/Services/CommerceEventDataService.cs)

**Purpose**: Acts as the data handler for managing commerce events within the system, bridging the gap between application logic and the data layer.

**Supported Request Types**:
- **CommerceEventEntityDataRequest**: Retrieves commerce event entities.
- **CreateCommerceEventEntityDataRequest**: Creates new commerce event entities.
- **SearchEventEntityDataRequest**: Searches for events based on specific criteria.

**Key Methods**:
- **GetCommerceEvents**: Queries the underlying SQL view (`COMMERCEEVENTSVIEW`) to retrieve paginated and filtered event lists.
- **SearchCommerceEvents**: Allows searching events based on criteria like event type and date range, utilizing caching mechanisms for improved performance.
- **CreateCommerceEvent**: Inserts new events into the database using stored procedures, ensuring data integrity and security through parameterized queries.

**Significance**: Provides essential functions to manage commerce events effectively, supporting the framework's goals of reliability and scalability.

### 4. [CheckoutCartRequestHandler](../CommerceEvents/CommerceRuntime/CommerceEvent/Handlers/CheckoutCartRequestHandler.cs)

**Purpose**: Extends the Commerce Event Framework to capture specific business events related to the checkout process.

**Functionality**:
- **Process Checkout Requests**: Handles the checkout process when a customer completes a purchase.
- **Create CommerceEventEntity**: Records the checkout event with relevant metadata (e.g., customer ID, channel, transaction ID).
- **Atomic Handling**: Utilizes `TransactionScope` to ensure that the checkout and event creation are processed atomically, maintaining data consistency.

**Significance**: Ensures that checkout events are reliably captured and stored, facilitating auditing, analytics, and troubleshooting.

### 5. [AddCartLineRequestHandler](../CommerceEvents/CommerceRuntime/CommerceEvent/Handlers/AddCartLineRequestHandler.cs)

**Purpose**: Extends the Commerce Event Framework to capture specific business events related to adding items to a cart.

**Functionality**:
- **Process AddCartLines Requests**: Handles the addition of products to a customer's cart.
- **Create CommerceEventEntity**: Records the add-to-cart event with essential information (e.g., event type, transaction ID, event data).
- **Atomic Handling**: Ensures that the cart modification and event creation are handled together to maintain data integrity.

**Significance**: Logs all cart modification activities, enabling comprehensive auditing and analytics of customer behavior.

### 6. [Commerce Event Messaging Files](../CommerceEvents/CommerceRuntime/CommerceEvent/MessagingFiles/)

**Purpose**: Serve as data carriers, encapsulating the requests and responses required to perform various operations within the Commerce Event Framework.

**Key Messaging Classes**:
- **CommerceEventEntityDataRequest**: Represents requests to retrieve commerce event entities.
- **CreateCommerceEventEntityDataRequest**: Handles requests to create new commerce event entities.
- **CreateCommerceEventEntityDataResponse**: Confirms the outcome of creating a commerce event entity.
- **GetCommerceEventLastSyncDataRequest**: Retrieves the last synchronization datetime for commerce events.
- **GetCommerceEventLastSyncDataResponse**: Provides the last sync datetime.
- **SearchEventEntityDataRequest**: Encapsulates criteria for searching specific events.
- **SearchEventEntityDataResponse**: Contains results of search requests, including matching commerce event entities.
- **SetCommerceEventLastSyncDataRequest**: Updates the last sync datetime for synchronization tracking.

**Additional Features**:
- **Standardization**: These messaging files standardize interactions between different application layers, maintaining separation of concerns.
- **Optimization**: Events can be cleaned up with scripts during package deployment to keep the system optimized and free of obsolete data.

## Benefits of the Commerce Event Framework

- **Persisted Event Storage**: Enhances performance and scalability by storing events in a read-only event store with lightweight payloads.
- **Near Real-Time Integration**: Ensures customer data is current by processing events almost instantaneously.
- **Reliability and Scalability**: Azure Service Bus ensures dependable message delivery and the architecture scales to handle high event volumes.
- **Monitoring and Auditing**: Comprehensive event tracking facilitates monitoring and streamlined troubleshooting.
- **Performance Optimization through CQRS**: Separates read and write operations to enhance performance and scalability.

## Extensibility

Partners and customers can leverage the Commerce Event Framework to create custom events tailored to their business needs, such as:

- **CustomerCreate**: Triggered when a new customer is created.
- **ProductUpdate**: Triggered when product details are updated.
- **OrderCancellation**: Triggered when an order is canceled.

This extensibility ensures that the framework can adapt to various business scenarios, enhancing its applicability across different domains.

## Conclusion

The Commerce Event Framework provides a comprehensive solution for integrating Dynamics 365 Commerce with Dynamics 365 Customer Insights Journeys and other external systems. By addressing the challenges of traditional integration methods and offering a scalable, reliable, and extensible architecture, it empowers developers to create robust, real-time event-driven applications that enhance customer interactions and business decision-making.

---
