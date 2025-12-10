# Sales Order Processor Agent
# Table of contents
1. [Use Case](#usecase)
2. [Sales Order Agent Components](#salesorderagent)
3. [Prerequisites](#prerequisites)
4. [Dataverse Solution Import - Install and configure the Sales Order Agent](#configuration)
5. [Install from Store - Install and configure the Sales Order Agent](#store)
6. [Limitations and constraints](#limitations)
7. [Roadmap](#roadmap)



<a id="usecase"></a>
# 🧩 Use Case 
Sales Order Agent is an autonomous agent for processing sales orders received via email attachments, validating customer and product data, and creating orders in Dynamics 365 finance and operation apps with minimal human intervention. 

1. Email received with attachments in personal or shared mailbox: ![emailReceivedWithAttachment](images/emailReceivedWithAttachment.png)

2. Each attachment and the extracted data saves to Dataverse: ![stagingdocument](images/extractedata.png) 

    ![stagingsalesorderheader](images/stagingsalesorderheader.png)
    

3. After validating the customer and products, the sales order gets created in Dynamics 365 and a notification is also sent:
![salesodererp](images/salesorder.png)

   ![emailnotification](images/emailnotification.png)

## Solution Capabilities
- **Autonomous Email Processing**: Monitors mailbox for email attachments
- **AI-Powered Document Parsing**: Extracts structured data from PDF/image attachments
- **ERP Integration**: Validates customers/products and creates orders in ERP
- **Exception Handling**: Routes items requiring manual review
-	**Automated Notifications**: Sends processing status updates
- **Supported File Types**: PDF documents, image files (JPG, PNG, etc.)

![businessProcessFlow](images/ProcessFlow.png)



<a id ="salesorderagent"></a>
# 🤖 Sales Order Agent Components
The agent orchestrates the entire sales order processing workflow, 
invokes appropriate agent flows based on the staging record processing status, and handles error scenarios and routing.
![componentsdiagram](images/componentsdiagram.png)

## Agent Instructions:
![salesordeagent](images/salesorderagent.png)

## Triggers:
-	Dataverse trigger for processing status updated
-	Office 365 triggers for new emails into personal and shared mailbox

![salesOrderAgentInstructions1](images/agenttriggers.png)


## Agent flows: 
For implementing deterministic sales order specific validation rules, as well as sales order header and lines creation, several agent flows have been created:

![salesOrderAgentTools](images/salesOrderAgentTools.png)

  - **Parse document** – agent flow which uses AI Builder custom prompt to extract data from email attachment in JSON format.
  - **Validate customer** – agent flow which tries to uniquely identify customer in Dynamics 365 using customer name or email.
  - **Validate products** –  agent flow which tries to uniquely identify the products in Dynamics 365 using product codes.
  - **Create order** – agent flow which creates the sales orders in Finance and Operations.
  - **Notify** – agent flow which sends emails when the sales orders are processed or need manual review.
  - **LoadSalesOrderData** - flow which splits the extracted JSON into dedicated Dataverse tables.
- **Update Processing Status to Valid** - flow which updates processing status.
- **Reprocess the not processed lines** - flow which re-tries to proces any failed order lines.

## Dataverse tables and custom app
![salesOrderAgentTools](images/DataverseApp.png)
  - **Sales Order Agent App** - visible to users with **Sales Order  reviewer, sys admin or sys customizer** security roles.
  - **Staging Document** – stores email attachments and extracted data. Key columns: 
    - **Extracted Data** - result of extraction in JSON format
    - **Input Document** - document received as email attachment

  - **Staging Sales Order Header** – stores header level data, customer information. Key columns:
    - **Processing Status** - The automatic successful status transition is **New -> Valid -> Processed**. For failures **New -> Manual Review** or **New -> Valid -> Processing Failed**. 
      - For a **Manual Review** status, the reviewer can insert manually the correct ERP Customer Number and ERP Product Codes and set flags Valid Customer and Valid Lines to Yes. When bot Valid Customer and Valid Lines are updated to Yes, the processing status is set to Valid and the agent tries to create the order in Finance and Operations.
      - For a **Processing Failed** status, the reviewer can analyze the validation messages for the failed lines, perform necessary updates either in the extracted data or in the ERP system, then retry to process those failed lines by setting the flag Try again to process failed lines to Yes.

    - **Valid Customer** - Automatically set by agent execution. If the customer is not identified, the status is set to Manual Review and a notification is sent. A reviewer may do necessary corrections and set the flag Valid Customer to Valid.
    - **Valid Lines** - Automatically set by agent execution. If the product is not identified, the status is set to Manual Review and a notification is sent. A reviewer may do necessary corrections and set the flag Valid Lines to Valid.
    - **ERP Customer Number** - Automatically set during agent execution. If the customer is not identified, the status is set to Manual Review and a notification is sent. A reviewer may insert manually the ERP Customer Number and set the flag Valid Customer to Valid.
    - **ERP Sales Order Number** - Automatically set by agent execution.
    - **Customer Name** , **Customer Email** - Automatically set by agent execution. 
    - **Try again to process failed lines** - Relevent for partially created orders due to intermittent failures or after fixing data issues (e.g. products missing default site), the flag can be set to Yes to re-submit the failed lines.
    - **Validation Message** - Automatically set by agent execution.
    - **Company Code** - Automatically set by agent execution from environment variable value. For changing this behaviour and introduce multiple companies, you can extend the logic in the LoadSalesOrderData flow.
 
    
  - **Staging Sales Order Lines** –  stores line level data, product codes, product details.
    - **Processing Status** - Automatic status transitions similar to the header status transitions.
    - **Product Code**, **Product Description**, **Product Quantity**, **Product Unit of Measure'** - Automatically set by agent execution. 
    - **ERP Product Code** - Automatically set by agent execution. In case the product is not identified, the status is set to Manual Review and a notification is sent. A reviewer may do necessary corrections insert the correct ERP Product Codes and set the flag Valid Lines to Yes.
    - **Validation Message** - Automatically set by agent execution. 
 
 If you require to capture additional columns e.g. VAT Number, you'd need to include the columns in the AI Builder data extraction prompt, also create a new Dataverse column in the staging sales order header and/or lines tables depending on where the data should be stored, and ensure to include in the LoadSalesOrderData flow an update to load the newly added columns from the extracted JSON into the relevant Dataverse table.

## AI Builder Prompt
- **Extracts data from document** - prompt with input a file or image and JSON format output.
![aibuilderprompt](images/aibuilderprompt.png)

<a id="prerequisites"></a>
# ✅ Prerequisites for installing the Sales Order Agent solution
 - Connected Dataverse environment with an environment with  finance and operations apps. To confirm this, you can check in the Power Platform Admin Portal for a given environment that there is a corresponding link to Dynamics 365.
 - The user who installs the Sales Order Agent solution must be a licensed user in Dynamics 365.
 - Dataverse virtual tables enabled: Released products V2 (mserp), Customers V3 (mserp). Learn more about how to enable virtual tables in Dataverse at https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/power-platform/enable-virtual-entities.
 - Sales Order agent solution imported and agent configured as indicated in the next section.
 - System Administrator role for solution import and agent configuration.
 - Manual Reviewers should be assigned the Sales Order Agent Reviewer security role after the solution is imported.
 - During solution import, ensure to provide values for either **a personal mailbox or a shared mailbox to monitor, the mailbox folder to monitor, the company code (for the sample file you can use usmf) and a reviewer email address**. After solution import, the corresponding environment variables can be updated from the context of an unmanaged solution. 
 - Please ensure that the environment where the agent is running either has Copilot Studio credits assigned, or there is a pay as you go billing plan in place. For more details, please see https://learn.microsoft.com/en-us/power-platform/admin/manage-copilot-studio-messages-capacity?tabs=new.
 
 **TIP**: If you require to monitor other folders than Inbox, please ensure there is a rule in place to route the emails automatically to the respective folder. For example, for a subfolder SalesOrder, you'd need to provide the value Inbox/SalesOrder for the folder to monitor.

<a id="configuration"></a>
# ✅ Sales Order Agent installation with Dataverse solution import
Import the Sales Order Agent solution from the Solutions folder and please consider the following to make the agent work for your specific needs and data:
 - **Create the connections** for Power Automate flows access systems using the least privileged accounts or a service principal where possible.
 - **Update the environment variables** - when importing the solution you should provide a **mailbox to monitor** for incoming sales orders attachments. You can choose a shared and/or personal mailbox. Ensure to provide email address for the **reviewer mailbox** and the **company code**. 
 - By default only pdf attachments are processed. If you'd like to process images as well, set **ProcessImagesAttachments** variable to Yes. 

    ![solutionimportvariables](images/solutionimportvariables.png)

  - **Update the Finance and Operation instance** – This step is required for the flow to integrate with your ERP instance. Navigate to make.powerautomate.com, select the relevant environment and from the list of flows, open the flow SOA V3 – Create Order in ERP.
  - Click on the flow and then Edit – this should open the flow in the Power Automate designer. If enabled, disable New Designer when making this change. 
  ![addvariables11](images/updateerp_1.png)
  - Open the condition if the ERP Sales Order was not created and edit the ERP instance for these 2 actions: Create Sales Order Header in ERP and Upload attachment
  ![addvariables12](images/updateerp_2.png)
  - Change the instance and wait for a few seconds for the change to be processed. Please double-check post-change that the input parameters have kept their values and that you are indeed using the classic designer.
    ![addvariables13](images/updateerp_3.png)
    ![addvariables14](images/updateerp_4.png)
    
  - Open Apply to each- > Try to create sales order line and change the ERP instance for Create Sales Order Line action as well and wait for the ERP instance update to complete and to observe the input parameters keeping their values. 
  ![addvariables15](images/updateerp_5.png)
  - Save your flow changes.
  - **TIP – If the flow is not editable, go back to the Flow main page, refresh it, then try to open again the Editor Page.**

 - **Customer validation** - Sales order agent validates customer name, and if not found, will search using the email address if available in the document. The agent flows validating the customer depends on the json extracted to contain the column **deliverycustomername**, **deliverycustomeremail**. Consider if this is necessary for your organization, and update as needed e.g. identifying customer by VAT Number if its provided – if you'd like to change the customer validation criteria, ensure to update the AI Builder extraction prompt to collect the required fields,create Dataverse column to store the VAT Number in the Staging Sales Order Header table, update the LoadSalesOrderData flow to populate the new column from the extracted JSON, and SOA V3 - Validate Customer agent flow to use the VAT Number for customer identification.

- **Products validation** – Sales order agent validates the product codes, and if found, when creating the sales order lines it will use the extracted product code, quantity, and unit of measure. The agent flows depends on the json extracted to contain columns **productcode, productquantity, productunitofmeasure**. Similarly with the customer extraction, if you need to capture different columns with your prompt, you will need to update the AI Builder extraction prompt, create Dataverse columns in the Staging Sales Order Line table, and update LoadSalesOrderData flow and SOA V3 - Validate Products agent flow.

- **Sample document** - You can use the attached test pdf document for testing if you have the sample data available in your Finance and Operations environment. Company Code should be usmf and the products 1000, A0001 should have  default order settings (Site and Warehouse) configured.


<a id="store"></a>
# ✅ Sales Order Agent installation via store
After installing the solution containing the sales order agent and components in Dataverse, there are several post-installation and configuration steps necessary. If you face issues please dont hesitate to reach out by filling out this form https://forms.office.com/r/BzUfaL89da  :

 - **1. Create an unmanaged solution** - once the package from the store is succesfully deployed you will see two managed solutions installed in your Dataverse environment. Please proceed to create a new **unmanaged** solution to store the components which need to be configured. For step by step guidance, please see https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-solution. 

 - **2. Add environment variables to the unmanaged solution** - once you create your unmanaged solution, open it, and click Add Existing - > More - > Environment variable:
 ![addvariables1](images/envvariables_1.png)
 ![addvariables2](images/envvariables_2.png)

 - **3. Update environment variables** -  Provide values for the **CompanyCode** (for sample data you can use usmf), **SharedMailboxToMonitor** and/or **PersonalEmailAddressToMonitor** and the corresponding **SharedMailboxFolderToMonitor**, **PersonalEmailMailboxFolderToMonitor**, **ReviewerEmailAddress**. You can choose if you'd like to monitor a shared and/or personal mailbox. By default only pdf attachments are processed. If you'd like to process images as well, set **ProcessImagesAttachments** variable to Yes. 

 - **4. Update Connection References** - start by adding these 4 connection references to your unmanaged solution (Add existing -> More - > Connection references).
  ![addvariables3](images/connectionreferences_1.png)
    - Open each connection reference (Edit) and update its related connection by creating either a new connection or by using an existing connection if available. (we are in the process of documenting least privileges for each, for now you can choose a sys admin access)
    -	For example when trying to create a new Fin & Ops (Dynamics 365) connection for the Fin & Ops connection reference, a new Connection page is opened, type to search for Dynamics 365 and select the create Action. Afterwards, in the unmanaged solution, associate the newly created connection with your Connection Reference. 
    ![addvariables4](images/connectionreferences_2.png)
    ![addvariables5](images/connectionreferences_3.png)
    - **Repeat** this process for the **Fin & Ops, Dataverse, Copilot Studio and Office 365 connection references**.



- **5. Enable flows** - as we didn’t have valid connection references previously, several flows are now disabled and need to be enabled – this can be achieved in multiple ways, an option is to open the managed solution imported when the package was installed from the store, the solution **Sales Order Agent Processing Template** and enable the flows:
    - Open the Managed Solution Sales Order Agent Processing Template and turn the status to On for all of the flows with status Off by selecting the flow, then pressing Turn on button. Unfortunately, you can only enable one flow at a time. 
    - Please note that if you didn’t provide values for shared mailbox address and folder to monitor via the respective environment variables, the flow “When a new email with attachment arrives in a shared mailbox (V2)” should remain disabled, otherwise the flow should be turned on as well.  Similarly, for the flow “When sales order email with attachment arrives” if you didn’t provide values for personal mailbox address and folder to monitor via the respective environment variables, the flow should be disabled.
![addvariables6](images/cloudflows_1.png)
  - After enabling the flows, we should see a status of On (except for the mailbox trigger flow depending on if you use shared and/or personal mailbox for monitoring)
![addvariables7](images/cloudflows_2.png)

- **6. Confirm product and customers Dataverse virtual tables are enabled** - follow instructions detailed at this page https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/power-platform/enable-virtual-entities. In order to open the Classic Advanced Find, you can also open the Power Platform Environment Settings app, click on Search in the toolbar then click on “Search for rows in a table using advanced filters”:
  ![addvariables8](images/virtualtables_1.png)
  - From the left corner, click on Switch to Classic
  ![addvariables9](images/virtualtables_2.png)
  - Look for Available Finance and Operations Entities and add in the criteria Name contains ReleasedProductV2Entity. Press Results, and open the record found, tick the Visible checkbox and save.
    ![addvariables10](images/virtualtables_3.png)
  - Repeat the process and change criteria for Name contains CustomerV3, press Results, open the record found, tick the Visible checkbox and save.


**7. Update the Finance and Operation instance** – this step is required for the flow to integrate with your ERP instance. 
  - Navigate to make.powerautomate.com, select the relevant environment and from the list of flows, open the flow SOA V3 – Create Order in ERP.
  - Click on the flow and then Edit – this should open the flow in the Power Automate designer. If enabled, disable New Designer when making this change. 
  ![addvariables11](images/updateerp_1.png)
  - Open the condition if the ERP Sales Order was not created and edit the ERP instance for these 2 actions: Create Sales Order Header in ERP and Upload attachment
  ![addvariables12](images/updateerp_2.png)
  - Change the instance and wait for a few seconds for the change to be processed. Please double-check post-change that the input parameters have kept their values and that you are indeed using the classic designer.
    ![addvariables13](images/updateerp_3.png)
    ![addvariables14](images/updateerp_4.png)
    
  - Open Apply to each - > Try to create sales order line and change the ERP instance for Create Sales Order Line action as well and wait for the ERP instance update to complete and to observe the input parameters keeping their values. 
  ![addvariables15](images/updateerp_5.png)
  - Save your flow changes.
  - **TIP – If the flow is not editable, go back to the Flow main page, refresh it, then try to open again the Editor Page.**

**8. Publish the Sales Order Agent** - open copilotstudio.microsoft.com, select the environment, in the list of agents find SalesOrderAgent, open the agent and press Publish button
 ![addvariables16](images/publishagent.png)

**9.Billing setup** – the agent is going to consume Copilot Studio credits – depending on the complexity and size of the documents parsed it can consume around 30 to 80 credits (1 credit = 0.01$) per attachment processed. Please ensure that the environment where the agent is running either has Copilot Studio credits assigned, or there is a pay as you go billing plan in place. For more details, please see https://learn.microsoft.com/en-us/power-platform/admin/manage-copilot-studio-messages-capacity?tabs=new. 

**10. Test the agent** - send an email with attachment to the configured mailbox address.

**11.	Monitor the agent** using the Sales Order Agent App – in order to access the monitoring app, you can open make.powerapps.com, select the environment where you installed the Sales Order Agent solution, then select Apps from the left-side options, select Sales Order Agent App then Play button from the ribbon.
 ![addvariables17](images/salesorderagentapp.png)

 - **Optional - Update Customer validation** - Sales order agent validates customer name, and if not found, will search using the email address if available in the document. The agent flows validating the customer depends on the json extracted to contain the column **deliverycustomername**, **deliverycustomeremail**. Consider if this is necessary for your organization, and update as needed e.g. identifying customer by VAT Number if its provided – if you'd like to change the customer validation criteria, ensure to update the AI Builder extraction prompt to collect the required fields,create Dataverse column to store the VAT Number in the Staging Sales Order Header table, update the LoadSalesOrderData flow to populate the new column from the extracted JSON, and SOA V3 - Validate Customer agent flow to use the VAT Number for customer identification.

- **Optional - Update Products validation** – Sales order agent validates the product codes, and if found, when creating the sales order lines it will use the extracted product code, quantity, and unit of measure. The agent flows depends on the json extracted to contain columns **productcode, productquantity, productunitofmeasure**. Similarly with the customer extraction, if you need to capture different columns with your prompt, you will need to update the AI Builder extraction prompt, create Dataverse columns in the Staging Sales Order Line table, and update LoadSalesOrderData flow and SOA V3 - Validate Products agent flow.

- **Optional - Sample document** - You can use the attached test pdf document for testing if you have the sample data available in your Finance and Operations environment. Company Code should be usmf and the products 1000, A0001 should have  default order settings (Site and Warehouse) configured.

<a id="limitations"></a>
# 🧩 Limitations and constraints

- The processing of email attachments, the extracted sales order data validations and processing are asyncronous operations. 
- The agent is going to consume Copilot Studio credits. Depending on the complexity and size of the documents parsed it can consume around 30 to 80 credits (1 credit = 0.01$) per attachment processed. 
- The agent only processes the email attachments: pdf by default, and optionally also images (png,jpeg,jpg) (controlled with environment variable)
- The agent uses AI Builder custom GPT prompts for document extraction. The GPT prompts support documents with less than 50 pages, for the full list of limitations please see https://learn.microsoft.com/en-us/ai-builder/add-inputs-prompt#limitations 
- The agent uses Office 365 connectors for monitoring the mailboxes, please see the limitations https://learn.microsoft.com/en-us/connectors/office365/#limits 
- Other Copilot Studio limitations https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-quotas 

<a id="roadmap"></a>
# 🤖 Sales Order Agent Roadmap
For customers with larger documents where AI Builder custom GPT prompt is not feasible, we are planning to enhance the sales order agent document extraction with another method for document analysis using Azure AI services.

👉 Want to explore how this can transform your document processing workflows? Fill out this form https://forms.office.com/r/BzUfaL89da to onboard into our Viva Engage community to connect with other users, share insights, and stay updated on the latest features.