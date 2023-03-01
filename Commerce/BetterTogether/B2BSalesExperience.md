# Better Together – B2B Lead to Cash Experience

This solution combines Dynamics 365 Sales, Dynamics 365 Commerce, Viva Sales and Microsoft Teams to provide a complete B2B Sales experience.

# Architecture

![Better Together B2B Lead to Cash Experience](B2BLeadtoCashExperience.png)

# Dataflow

1. A customer requests a business relationship in the Dynamics 365 e-Commerce site.
1. The prospect in commerce presents in Dynamics 365 Sales as an lead.
1. Within Dynamics 365 Sales a Teams meeting is created to qualify and on-board the business partner.
2. Viva Sales is embeded to help with trancript and next steps.
 
 

# Components

-   [Dynamics 365 Commerce](https://dynamics.microsoft.com/commerce/capabilities/) can help retailers to deliver personalized, seamless shopping experiences across physical and digital channels. It’s used here by the end consumer to shop online. It’s also used by the retail merchandizer to create and activate a coupon code.

-  [Dynamics 365 Sales](https://dynamics.microsoft.com/sales/overview/) helps companies grow customer relationships and sell at scale by empowering sales teams with actionable sales intelligence.

-  [Microsoft Teams](https://www.microsoft.com/microsoft-teams/teams-for-work) helps employees improve productivity, save time, and accomplish more by keeping everyone in the loop and ensuring everyone has a voice.

-  [Microsoft Viva Sales](https://www.microsoft.com/microsoft-viva/sales) harnesses the power of generative AI to deliver automatic content creation in Microsoft 365 apps resulting in deeper customer engagement and increased seller productivity.

-   [Dataverse](https://powerplatform.microsoft.com/dataverse/) lets you securely store and manage data that's used by business applications. It’s used here to link customer insights to marketing data.

# Scenario details

The Chief Revenue officer (CRO) wants to increase B2B propects to customers by building stronger relationship with their customer and personalize the customer buying journey.

They decide to tackle this challenge with 2 initiatives:

-   Implementing Dynamics sales to accelerate their sales
-   Implementing Microsoft Teams chat in Dynamics Sales to collaborate
-   Using Viva Sales in Dynamics Sales/team for deeper customer engagement and increased seller productivity

With personal help from Sales representative and collaboration, they are able to see more customer from B2B E-commerce site .

This showcases how Dynamics 365 Applications - Commerce, Sales, Team, Viva Sales work together seamlessly 

The Chief Revenue Officer is now able to achieve his goal to increase conversion from propects to customer.

# Potential use cases

This solution was created to enables salespeople to build stronger relationships with their customers and personalize the customer buying journey.It can be applied in industries like retail, financial services, manufacturing, and health care. It can be used by any organization that wants to bring Dynamics 365 apps together to manage pipeline, nurture sales from lead to order, and accelerate the sales.

You can use this solution to:

-   Gain better understanding of prospects.
-   Target prospects to convert them to customers.
-   Provide personalized experiernce to targeted prospects.
-   Collaborate within organization.
-   Self service onboarding of B2B customers.

# Deploying the Scenario


## Pre-requisites

-   Dynamics 365 demo environments 
    - If you do not have demo environment , refer to this page [Get started with a Dynamics 365 free trial](https://dynamics.microsoft.com/dynamics-365-free-trial/)

-   Dyanmics 365 Commerce with E-commerce
    -   Setup guide: [E-commerce site overview - Commerce \| Dynamics 365 \| Microsoft Learn](https://learn.microsoft.com/dynamics365/commerce/online-store-overview)

- Dynamics 365 Sales 
   - [Learn the basics of Dynamics 365 Sales | Microsoft Learn](https://learn.microsoft.com/dynamics365/sales/user-guide-learn-basics)
- Dual Write
   - [Dual-write overview - Finance & Operations | Dynamics 365 | Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-overview)
- Viva sales
    - There are no prerequisites to the purchase of Viva Sales. However, the Viva Sales app will run on top of the Outlook and Teams applications. Hence to deploy Viva Sales you need to have access to an instance of these applications, which requires a Microsoft 365 for enterprise or Office 365 for enterprise product license. They must also have a CRM system(Dynamics 365 Sales. Salesforce,..) to connect to Viva Sales.
    - You need to be a Microsoft 365 administrator to deploy and install the Viva Sales add-in for Outlook. You need to be a Teams administrator to deploy and install Viva Sales for Teams.
    [Install Viva Sales](https://learn.microsoft.com/Viva/sales/install-viva-sales/)
- Teams
    - [Microsoft Teams deployment overview](https://learn.microsoft.com/microsoftteams/deploy-overview/)
    
## Configuration
The following steps assume you are setting up the solution for an existing Dynamics 365 Commerce demo environment.

### Step 1: Enable dual-write in Dynamics 365 Commerce
#### Install dual-write  
- [Make sure that you meet all the system requirements and complete all the prerequisites](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/requirements-and-prerequisites). 
  - At step #7. the following are the seperated packages you need to apply
      - Dual-write Application Core Solutions 
      - Dual-write Party and Global Address Book Solutions
      - ...
```
- TODO we need to tell them which of these solutions are required.
- https://appsource.microsoft.com/en-US/marketplace/apps?exp=ubp8&search=dual-write&page=1. 
- And, are there 2 'core' pacakges? a Dual-write Core and a Dual-write Applicaiton Core. It sure looks like there is. 
```
- [Link your finance and operations app environment to Dataverse by using the dual-write wizard](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/link-your-environment).
```
- TODO: Is there a second step where we have to do something in the specific D365 Commerce environment? Follow this steps to push prospects to lead  [Party and global address book](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/party-gab#setup)
```
- [Enable the table maps](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/enable-entity-map).

#### Troubleshooting dual-write installation and configuration
- Follow this step to fix number sequence [Number sequence issue] (https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-prospect-to-cash#number-sequences-for-quotations-and-orders)
- Follow these steps if you have lookup field more than 10 values. [Lookup field issue](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-troubleshooting-initial-sync#error-customer-map)

#### Optional steps. Not required for a demo environment.
- Optional: [Configure a <em>Dynamics 365 Sales team</em> to own records created through dual write](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/user-specified-team-owner). By default, when you enable dual-write, the root business unit’s default team will become the default owner for all rows integrated through dual-write. This may not be what you want when you want to limit access to these records to just a subset of users.

### Step 2: Configure exchange settings for Sales

[Choose the records to synchronize between customer engagement apps and Exchange - Power Platform | Microsoft Learn](https://learn.microsoft.com/power-platform/admin/choose-records-synchronize-dynamics-365-outlook-exchange)

### Step 3: Configure Teams in Dynamics 365 Sales

- [Collaborate using Microsoft Teams with the Dynamics 365 Sales Enterprise license | Microsoft Learn](https://learn.microsoft.com/dynamics365/sales/manage-teams?tabs=sales)

### Step 4: Install and pin Viva Sales in Teams

- [Install and pin Viva Sales in Teams | Microsoft Learn](https://learn.microsoft.com/Viva/sales/install-pin-viva-sales-teams)

## Additional reference topics
