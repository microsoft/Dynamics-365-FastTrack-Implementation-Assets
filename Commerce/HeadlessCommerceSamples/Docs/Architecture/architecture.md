# Headless Commerce

[[_TOC_]]

## Overview

Dynamics 365 Commerce provides a comprehensive suite of omni-channel order management capabilities, including a first-party point of sale (POS), an e-commerce platform, and an order management system known as Headquarters (HQ). "Omni-channel order management" means that orders created through any channel are processed using the same logic and treated equally, regardless of their origin. This supports scenarios like "Buy Online, Pickup in Store" (BOPIS), "Buy Online, Return in Store" (BORIS), curbside pickup, and "Buy Online, Ship from Store" (BOSS).

This is achieved by centralizing the business logic for order creation and management within Dynamics 365 Commerce. The order intake applications (POS and e-commerce) only handle user experience logic (e.g., hide/show forms, enable/disable buttons) and call the APIs on the headless commerce infrastructure.

If you prefer to retain your existing third-party order intake application (e.g., e-commerce), you can still achieve a similar omni-channel order management experience with Dynamics 365 Commerce by integrating with Headless Commerce. There are no exclusive APIs for Microsoft's first-party POS and e-commerce applications, ensuring that anything possible through a first-party app is also possible through integration.

The **Headless Commerce Engine** is the core microservice of Dynamics 365 Commerce, responsible for handling various commerce operations. It operates on the **Commerce Scale Unit (CSU)**, which is the underlying infrastructure. While the CSU supports multiple services, it is often associated with Headless Commerce due to its critical role in hosting this microservice. When discussing physical infrastructure, we refer to the CSU, whereas discussions about software and services typically mention the Headless Commerce Engine. Despite their distinct roles, the terms are frequently used interchangeably.

## Integration Architecture

![Diagram](../../Resources/Architecture.png)

Headless Commerce is a modern, scalable service designed to handle essential functions such as product discovery (search), order creation, and store operations. It facilitates order creation and asynchronously relays order details to Headquarters, which manages the order lifecycle. While Headless Commerce is extensible and allows for a wide range of customizations, it is recommended to keep customizations focused and within the scope of its original workloads.

The following workloads are integrated into Headless Commerce:

- **System of reference:** Product, merchandising, pricing, discounts, customer, location/warehouse, and inventory data are maintained in other systems. Only reference data is replicated (in near-real-time) to the operating channel database used by Headless Commerce.
- **System of origin:** Orders and customers can be created, but general lifecycle management is assumed to be conducted in Headquarters, which is the system of record for these data concepts. Headless Commerce can make real-time API calls to Headquarters to retrieve order or customer details, provided Headquarters is online and available.

The following workloads are best implemented elsewhere:

- **Not an app:** Headless Commerce is a service, not an application. For POS, use Store Commerce, and for e-commerce, use the first-party app.
- **Not an integration platform:** The CSU infrastructure is optimized for its designed workloads. Using it for other workloads can impact performance.
- **Not a system of record:** Headless Commerce is for order creation and ingestion, relaying orders asynchronously to Headquarters. Use other applications for master data management:
  - **Customer data:** Use Customer Data Platforms (CDP) like Dynamics 365 Customer Insights - Data for handling large volumes of customer profiles.
  - **Inventory on-hand:** Use Dynamics 365 Inventory Visibility service for real-time inventory information and soft reservations.
  - **Merchandising/PLM:** Headless Commerce uses a reference copy of product, pricing, and related data for product discovery and cart creation.
- **Not a logging tool:** Use modern logging tools like Application Insights. For telemetry, use [Operational Insights](https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/operational-insights) to monitor CSU operations.
- **Not a business event network:** Internal triggers and events in Headless Commerce are not broadcast externally. Extensions and ISV solutions can attach to these events to call external services as needed (e.g., tax or freight calculation).

### Integration Components

The following components are essential to any integration:

- **Middleware:** Middleware is the first and most essential aspect of any integration. As a general design principle, you want to ensure that all of the heavy integration workload is separated from your source and target systems.
- **API Management:** A key security best practice when integrating is to put an API management layer in front of your middleware so that it can be secured and controlled from a central management location.
- **Composable orchestration:** Design your orchestrations so that they follow common patterns and can be selectively enabled, disabled, or expanded. This allows you to quickly add new workloads and scenarios to your integrations with no rework.
- **Logging and message correlation:** Integration, as well as any headless implementation, happens in the background and often across multiple threads. Instrumenting your orchestrations with telemetry allows you to monitor, track the health, and react to any problem before it becomes an issue. Correlating
- **Secret / key vault:** Security is extremely important in a digital world. Ensuring that all shared secrets and connections are locked in a vault that is properly maintained (e.g., rotating secrets regularly) is essential to any integration.
- **Data mapping and transformation:** Each source and target system will likely have different unique identifiers for the same data concept. For example, Customer might be tracked as an email address in your marketing system while Dynamics 365 uses a customer account number. The middleware will need to maintain a mapping table so that concepts can be transformed from one system to the other.
- **Message queueing and reliable delivery:** Most integrations will not have a one-to-one alignment of API methods between source and target systems. The middleware will use orchestrations to process signals so that the correct sequence of API methods are invoked. There are several ways that things can break before the signal is fully relayed to the target system. This puts the responsibility on the middleware for ensuring that it can recover from intermittent errors and complete the signal relay.
- **Monitoring:** Implement comprehensive monitoring to ensure the health and performance of your integration. Use tools like Azure Monitor, Application Insights, or other monitoring solutions to track metrics, logs, and traces. Set up alerts for critical issues and performance bottlenecks. Regularly review monitoring data to identify and address potential problems proactively.

### Integration Approach

When designing your integration strategy, consider grouping your activities by business processes. This will help you to focus your specific patterns and reduce complexity as data often needs to flow in a single direction. The following table lists common scenarios that we have detailed with prescriptive guidance.

| Scenario                                       | Direction                                | Patterns                                                                                                                                                                     | Notes                                                                                                                                                                                  |
| ---------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Price](../prices/prices.overview.md)          | From D365 to external system<sup>1</sup> | Real-time pricing can be retrieved using GetActivePrices(). For asynchronous product price lists, use the product publishing framework to export data to external platforms. | Dynamics 365 has complex pricing and discounting logic that is challenging to replicate elsewhere. Only simple price list exports are feasible.                                        |
| [Customer](../customers/customers.overview.md) | From external system to D365             | This pattern involves sending the "Customer" payload to Dynamics 365 based on specific business events.                                                                      | Use the customer APIs in Dynamics 365 Commerce to verify if the customer exists. If the customer does not exist, create a new record; otherwise, update the existing customer details. |
| [Product](../products/products.overview.md)    | From D365 to external system<sup>1</sup> | Product publishing framework                                                                                                                                                 |                                                                                                                                                                                        |
| [Inventory]()                                  | Coming soon                              |                                                                                                                                                                              |                                                                                                                                                                                        |
| [Order creation]()<sup>2</sup>                 | Coming soon                              |                                                                                                                                                                              |                                                                                                                                                                                        |
| [Payments]()                                   | Coming soon                              |                                                                                                                                                                              |                                                                                                                                                                                        |

**Footnote 1:** Headless Commerce does not natively publish events, so the middleware will either need an external event or to set a timer. See our article on using the product publisher to detect changes in product and related data (e.g., prices).

## Design Considerations

- **Security First:** Prioritize security by storing secrets and connection strings in a key vault.
- **Data Protection:** Ensure data residency compliance and encrypt any temporary storage used for relaying signals. Customer and order data contain personally identifiable information (PII) and payment details.
- **Telemetry and Monitoring:** Use referenceable correlation numbers (e.g., GUIDs) instead of identifiable data in logs and monitoring. Integrate external data sources with log data for intelligent reporting, but avoid storing customer data in logs.
- **Self-Healing:** Design processes to be retriable and capable of restarting mid-orchestration. Handle common error patterns and throttling (e.g., HTTP-429) appropriately.
- **Atomic Operations:** Break down work into the smallest independent units that can be executed out of sequence.
- **Asynchronous Processing:** Favor asynchronous patterns for better scalability and resilience, even if it complicates implementation. This approach simplifies the overall solution.
