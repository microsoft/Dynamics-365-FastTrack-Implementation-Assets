# Copilots in Dynamics 365 Finance 

Copilots have changed the landscape of business and productivity apps and made AI the new UX. Lets see how copilots work in Dynamics 365 Finance and how these can be extended. This article will explore few copilot samples. With Power automate, we will build some low code but very powerful capabilities. When it comes to extensibility, Dynamics 365 for Finance offers three type of plugins, that extend the capabilities of copilot. 

1. **Low code plugins** –Microsoft Copilot Studio provides the orchestration of the AI capabilities for Copilot for finance and operations apps. Therefore, it enables a low-code maker experience for customizing the Copilot capabilities. You can utilize Power automate and its vast number of connectors to build some powerful capabilities.  

2. **Client plugins** - Client plugins, or client actions, are Microsoft Copilot plugins that invoke client code and are available for users in the context of client experiences for finance and operations apps. Developers can extend the Copilot chat capabilities in finance and operations apps by defining plugins that convert the functionality, operations, and business logic of the X++ code base into actions that users can invoke through natural language. For more information about client plugins and syntax, see [Create client plugins for Copilot in finance and operations apps](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-client-plugins). 

3. **AI plugins** - AI plugins also extend the capabilities of copilot experiences in Microsoft Copilot Studio by using business logic in finance and operations X++ code. These plugins are headless operations that don't require specific application context in the finance and operations client. They can be added to Copilot for finance and operations apps to extend the in-app chat experience, or they can be added to other custom copilots. For more information, see [Create AI plugins for copilots with finance and operations business logic](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-ai-plugins). 


This document will focus on low code plugins and create three fully functional samples step by step. 

# Table of Contents
1. [Post 1: Summarise sales order](#post-1-summarise-sales-order)
2. [Post 2: Summarise customer](#post-2-summarise-customer)
3. [Post 3: Get stock on hand](#post-3-get-stock-on-hand)

# Pre-requisites
Enable Copilot in Finance and Operations apps in your environment. For instructions, see [Enable Copilot capabilities in finance and operations apps](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/enable-copilot)


# Post 1: Summarise sales order

The scenario is that as a user one can desire a summary of a sales order. This can be handy as you don’t need to open different forms and tabs inside a sales order form to get the details. Such a topic in Copilot studio will be triggered when user types phrase like “summarise sales order”. Copilot will request for a sales order number. Please note in next example “summarise customer” we will automate so the copilot can use the page context/user context info to fetch the customer number, company ID as copilot have page and user contexts available. See for more: [Use application context with Copilot - Finance & Operations | Dynamics 365 | Microsoft Learn](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/copilot/copilot-application-context)
Next the summarise sales order topic will call a Power automate action to retrieve data entity record for the sales order. Then another action will use the record information and call an AI prompt to summarise the record into human readable paragraph. We use the power of GPT LLM models available in Power automate to read data entity record details (JSON) and come up with a human readable natural language summary. The summary is not perfect but shows the potential of such copilots. The final summarised paragraph is returned to the user.
1.	Create topic in copilot studio. Go to copilot studio and select environment associated with your Dynamics 365 Finance.
2.	Make sure Generative AI setting is set to Classic. Generative option can randomly choose topics, actions and knowledge to progress a chat.


