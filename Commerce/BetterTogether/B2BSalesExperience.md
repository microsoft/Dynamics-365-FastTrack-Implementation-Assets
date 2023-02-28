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
-   Target prospects to convert them to customer.
-   Provide personalized experiernce to targeted prospects.
-   Collaborate within organization.

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


### Step 1: Enable Dual write in Dynamics 365 Commerce
  
- Follow this steps to push prospects to lead  [Party and global address book](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/party-gab#setup)
- Follow this step to fix number sequence [Number sequence issue] (https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-prospect-to-cash#number-sequences-for-quotations-and-orders)
- Follow steps if you have lookup field more than 10 [Lookup field issue](https://learn.microsoft.com/dynamics365/fin-ops-core/dev-itpro/data-entities/dual-write/dual-write-troubleshooting-initial-sync#error-customer-map)

### Step 2: Configure Teams in Dynamics 365 Sales

- [Create or manage teams in Dynamics 365 Sales | Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/sales/manage-teams?tabs=sales)

### Step 3: Install or pin Viva Sales in Teams

- [Install and pin Viva Sales in Teams | Microsoft Learn](https://learn.microsoft.com/en-us/Viva/sales/install-pin-viva-sales-teams)

## Additional reference topics
