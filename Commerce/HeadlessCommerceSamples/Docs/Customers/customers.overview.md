# Customer Integration

Dynamics 365 Commerce headless integration for customer data ensures seamless synchronization between external marketing systems and Dynamics 365 Commerce. This integration maintains accurate customer information across platforms, providing a consistent and efficient experience.

## Integration Approach

The integration process assumes that customers are initially created in the external marketing system, each identified by a unique email address. Integration is triggered by events from the external marketing system, providing real-time data updates. When a customer action occurs, the data is sent to Dynamics 365 Commerce. The email address serves as the key identifier, ensuring accurate matching and synchronization across platforms.

## Architecture

![Architecture diagram](../../resources/customers.architecture.png)

## Integration Overview

### Role of Middleware

Middleware is essential for transforming data from any third-party application to the Dynamics 365 Commerce format, allowing for data transformation and workflow processing. For example, middleware queries Dynamics 365 Commerce to check if the user exists. If not, it creates a new customer; otherwise, it updates the existing customer and returns the details.

### Data Integration to Dynamics 365 Commerce

Dynamics 365 Commerce headless commerce engine offers APIs for seamless integration with third-party applications. When customer data is sent from an external system, middleware can leverage these Customer APIs to process and synchronize the information efficiently.

### Customer Identification

Dynamics 365 Commerce uses the email address as the primary key to identify customers. If a customer with the same email address exists, the existing data is updated. If no matching email address is found, a new customer record is created.

#### Search Customer

```json
POST: {Commerce server url}/Customers/SearchByFields?$top=1
Body:
{
  "CustomerSearchByFieldCriteria": {
    "Criteria": [
      {
        "SearchTerm": "",
        "SearchField": {
          "Name": "Email",
          "Value": 3
        }
      }
    ],
    "DataLevelValue": 1
  }
}
```

#### Get Customer

```json
GET: {Commerce server url}/Customers('{{accountId}}')?api-version=7.3
```

#### Create Customer

```json
POST: https://{{Commerce server url}}/Commerce/Customers?api-version=7.3
Body:
{
  "AccountNumber": "{{AccountNumber}}",
  "FirstName": "{{FirstName}}",
  "Name": "{{Name}}",
  "MiddleName": "{{MiddleName}}",
  "LastName": "{{LastName}}",
  "CustomerTypeValue": "{{CustomerTypeValue}}",
  "Language": "{{Language}}",
  "CustomerGroup": "{{CustomerGroup}}",
  "CurrencyCode": "{{CurrencyCode}}",
  "IsAsyncCustomer": "{{IsAsyncCustomer}}",
  "TitleRecordId": "{{TitleRecordId}}",
  "ReceiptEmail": "{{ReceiptEmail}}",
  "Email": "{{Email}}",
  "Addresses": [
    {
      "Name": "{{Name}}",
      "Id": "{{Id}}",
      "FullAddress": "{{FullAddress}}",
      "Street": "{{Street}}",
      "StreetNumber": "{{StreetNumber}}",
      "County": "{{County}}",
      "CountyName": "{{CountyName}}",
      "City": "{{City}}",
      "DistrictName": "{{DistrictName}}",
      "State": "{{State}}",
      "StateName": "{{StateName}}",
      "ZipCode": "{{ZipCode}}",
      "ThreeLetterISORegionName": "{{ThreeLetterISORegionName}}",
      "ExtensionProperties": []
    }
  ],
  "ExtensionProperties": []
}
```

#### Update Customer

```json
PATCH: https://{{Commerce server url}}/Commerce/Customers({{AccountNumber}})?api-version=7.3
Body:
{
  "AccountNumber": "{{AccountNumber}}",
  "Email": "{{Email}}",
  "FirstName": "{{FirstName}}",
  "LastName": "{{LastName}}"
}
```

#### Customer Data Mapping

The table below maps the fields to the Customer API in Dynamics 365 headless commerce integration. View the Commerce metadata for the Customer Entity here: https://{Commerce server url}/Commerce/metadata#Customers/entity

| **Dynamics 365 Entity** | **Dynamics 365 Field**   | **Dynamics 365 Type** | **Description**                                      |
| ----------------------- | ------------------------ | --------------------- | ---------------------------------------------------- |
| Customers               | AccountNumber            | String                |                                                      |
| Customers               | FirstName                | String                |                                                      |
| Customers               | LastName                 | String                |                                                      |
| Customers               | Address_State            | String                |                                                      |
| Customers               | Email                    | String                |                                                      |
| Customers               | CreatedDateTime          | DateTime              |                                                      |
| Customers               | CurrencyCode             | String                |                                                      |
| Customers               | Phone                    | String                |                                                      |
| Customers               | IsOptedInMarketing       | Boolean               |                                                      |
| Customers               | CustomerAccount          | String                |                                                      |
| Customers               | Name                     | String                |                                                      |
| Customers               | FullAddress              | String                |                                                      |
| Customers               | Street                   | String                |                                                      |
| Customers               | City                     | String                |                                                      |
| Customers               | State                    | String                |                                                      |
| Customers               | CountryName              | String                |                                                      |
| Customers               | ZipCode                  | String                |                                                      |
| Customers               | Phone                    | String                | Formatted using E.164 standard (e.g., +16135551111). |
| Customers               | Province_Code            | String                |                                                      |
| Customers               | ThreeLetterISORegionName | String                | 3 characters                                         |
| Customers               | IsPrimary                | Boolean               |                                                      |

### Data Validation & Error Handling

Validate customer data to meet required formats and standards, including localized country-specific formats. Check for discrepancies or errors when updating or creating customer records in Dynamics 365 Commerce, and log integration errors. Implement error handling to manage issues during integration, providing notifications for failed attempts to ensure prompt resolution.
