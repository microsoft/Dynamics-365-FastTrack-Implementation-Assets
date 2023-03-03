# Better Together – B2B Lead to Cash Experience

This solution combines Dynamics 365 Sales, Dynamics 365 Commerce, Viva Sales and Microsoft Teams to provide a complete B2B lead to cash experience.

# Architecture

![Better Together B2B Lead to Cash Experience](B2BLeadtoCashExperience.png)

# Dataflow

1. A **prospect** intiates a business relationship using the **Dynamics 365 Commerce** B2B e-Commerce site.
1. The prospect's request lands as a **lead** in **Dynamics 365 Sales**.
3. In Dynamics 365 Sales, an **appointment** with **Microsoft Teams** link is created to collaborate with the lead.
4. In Microsoft Teams, **Viva Sales** sentiment analysis AI is used to review meeting.
5. In Dynamics 365 Sales, lead get converted to **Opportunity** .
6. Microsoft Teams channel is used for internal Team collaboration.
7. Opportunity information is shared in Teams channel with Viva Sales.
8. When the opportunity is won in Dynamics 365 Sales, Dynamics 365 Commerce lead converts to **customer**.

# Components

-   [Dynamics 365 Commerce](https://dynamics.microsoft.com/commerce/capabilities/) can help retailers to deliver personalized, seamless shopping experiences across physical and digital channels. It’s used here by the end consumer to shop online. It’s also used by the retail merchandizer to create and activate a coupon code.

-  [Dynamics 365 Sales](https://dynamics.microsoft.com/sales/overview/) helps companies grow customer relationships and sell at scale by empowering sales teams with actionable sales intelligence.

-  [Microsoft Teams](https://www.microsoft.com/microsoft-teams/teams-for-work) helps employees improve productivity, save time, and accomplish more by keeping everyone in the loop and ensuring everyone has a voice.

-  [Microsoft Viva Sales](https://www.microsoft.com/microsoft-viva/sales) harnesses the power of generative AI to deliver automatic content creation in Microsoft 365 apps resulting in deeper customer engagement and increased seller productivity.

-   [Dataverse](https://powerplatform.microsoft.com/dataverse/) lets you securely store and manage data that's used by business applications. It’s used here to link customer insights to marketing data.

# Scenario details

This solution was created to provide guided experience for lead to customer journey.

For that we decide to tackle this challenge with below initiatives:

-   Implementing Dynamics sales to accelerate their sales
-   Implementing Microsoft Teams chat in Dynamics Sales to collaborate
-   Using Viva Sales in Dynamics Sales/team for deeper customer engagement and increased seller productivity

With personal help from Sales representative and collaboration, they are able to see more customer from B2B E-commerce site .

This showcases how Dynamics 365 Applications - Commerce, Sales, Team, Viva Sales work together seamlessly 

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

-   Dyanmics 365 Commerce with B2B E-commerce
    -   Setup guide: [Set up a B2B e-commerce site - Commerce | Dynamics 365 | Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/commerce/b2b/set-up-b2b-site)

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

### Step 1: Enable dual-write in Dynamics 365 Commerce
#### Install dual-write  
- [Dual-write setup - Finance & Operations](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-home-page)
     
  - At Step #7 in, [Link your finance and operations app environment to Dataverse by using the dual-write wizard](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/link-your-environment), After applying the soluton, ensure you take the latest version of entities underneath.

For this B2B lead to cash experience , ensure that you follow all the steps in below documentation:

 - [Party and global address book - Finance & Operations | Dynamics 365 | Microsoft Learn](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/party-gab)
 - [Prospect-to-cash in dual-write - Finance & Operations | Dynamics 365 | Microsoft Learn](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-prospect-to-cash)


#### Troubleshooting dual-write installation and configuration
- Follow this step to fix number sequence [Number sequence issue] (https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-prospect-to-cash#number-sequences-for-quotations-and-orders)
- Follow these steps if you have lookup field more than 10 values. [Lookup field issue](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-troubleshooting-initial-sync#error-customer-map)

#### Optional steps. Not required for a demo environment.
- Optional: [Configure a <em>Dynamics 365 Sales team</em> to own records created through dual write](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/user-specified-team-owner). By default, when you enable dual-write, the root business unit’s default team will become the default owner for all rows integrated through dual-write. This may not be what you want when you want to limit access to these records to just a subset of users.

### Step 2: Configure exchange settings for Sales

[Choose the records to synchronize between customer engagement apps and Exchange - Power Platform | Microsoft Learn](https://learn.microsoft.com/power-platform/admin/choose-records-synchronize-dynamics-365-outlook-exchange)

### Step 3: Configure Teams in Dynamics 365 Sales

- [Collaborate using Microsoft Teams with the Dynamics 365 Sales Enterprise license | Microsoft Learn](https://learn.microsoft.com/dynamics365/sales/manage-teams?tabs=sales)

### Step 4: Install Viva Sales

- [Install Viva Sales from Microsoft 365 admin center](https://learn.microsoft.com/en-gb/Viva/sales/install-viva-sales-individual-add-in-admin-center)
- [Install and pin Viva Sales in Teams](https://learn.microsoft.com/en-gb/viva/sales/install-pin-viva-sales-teams)

## Additional reference topics
- [Privileges and Permissions to install and configure Viva vales](https://learn.microsoft.com/en-gb/Viva/sales/install-viva-sales) 
