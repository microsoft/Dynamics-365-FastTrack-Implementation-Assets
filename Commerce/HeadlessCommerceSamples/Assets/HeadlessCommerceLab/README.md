# 🛒 Microsoft Dynamics 365 Commerce – Headless Commerce Lab

This repository contains lab materials and exercises for learning and exploring **Headless Commerce APIs** in Microsoft Dynamics 365 Commerce.

## 📄 Lab Document

The lab is designed to give hands-on experience using Insomnia to explore various API roles and endpoints available in Dynamics 365 Commerce, including anonymous, application, and customer-level roles.

📘 [Download Lab Guide (PDF)](./FastTrackAsset-%20%20Headless%20Commerce%20Lab.pdf)

## 🎯 Lab Objectives

By completing this lab, you will be able to:

- Understand different security roles in Headless Commerce API access
- Configure Insomnia or Postman for API exploration
- Execute API requests using proper authentication methods
- Simulate business flows like:
  - Searching products anonymously
  - Managing customers via application role
  - Creating and checking out a cart
  - Viewing order history
  - Fetching invoices
  - Performing a deal price lookup via pricing APIs

## 🧰 Prerequisites

- [Insomnia](https://insomnia.rest/download) installed
- Access to your own workstation with internet
- Basic familiarity with REST APIs and Microsoft Entra ID (formerly Azure AD)

## 🧪 Labs Included

| Lab # | Title                                  | Description |
|-------|----------------------------------------|-------------|
| 01    | Configure Insomnia                     | Set up API client and import lab collection |
| 02    | Anonymous Role                         | Perform product search without authentication |
| 03    | Application Role                       | Authenticate using client credentials and manage customers |
| 04    | Application Role – Order to Cash       | Simulate checkout and cart management |
| 05    | Application Role – Order History       | Retrieve historical order and invoice data |
| 06    | Customer Role                          | Use a user ID token for login and retrieving customer data |
| 07    | Knowledge Test                         | Test understanding of pricing APIs via "CalculateSalesDocument" |

## 📚 References

- [Retail Server Customer and Consumer API Docs](https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/retail-server-customer-consumer-api)
- [Commerce Pricing APIs](https://learn.microsoft.com/en-us/dynamics365/commerce/pricing-apis)
- [Microsoft Entra App Registration](https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/consume-retail-server-api)

## 🛑 Terms of Use

This lab is intended for training and feedback purposes only. Please read the Terms of Use section in the lab PDF for details on usage restrictions.

---

© 2025 Microsoft Corporation. All rights reserved.
