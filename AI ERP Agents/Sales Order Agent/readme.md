# Sales Order Processor Agent

# 🧩 Use Case
Automating and adding efficiency into the processing of **sales orders** incoming as attachments on email to be added into Microsoft Dynamics 365 finance and operations.
# 🛠️ Approach
The solution will lead with our **first-party agent Document Processor for document extraction, and content validation**. Once the content is validated, we will use a **second agent to create the order and order lines into the ERP.**

**Step 1: Document Processor Agent**
- Monitors Exchange mailbox (personal or shared)
![emailReceivedWithAttachment](images/emailReceivedWithAttachment.png)

- When email is received, the agent persists the attachment in the Data Processing Event table in Dataverse – for each attachment a new record is created. It also parses the attachments into JSON format in the Processed Data column.
![dataProcessingTable](images/dataProcessingTable.png)

- Validates content as per validation rules which are configurable
![docProcessorValidationRules](images/docProcessorValidationRules.png)

- You can also add more advanced rules to validate content grounded in Dataverse knowledge:
![docProcessorAdvancedRules](images/docProcessorAdvancedRules.png)

- When invalid content is found, it brings human into the loop for manual review. The canvas app Validation Station helps the reviewer identify invalid content and allows to edit and make corrections as well as the option to manually approve.
![docProcessorValidationStation](images/docProcessorValidationStation2.png)



**Step 2: Sales Order Processor Agent**
- Triggered when Document Processor Agent has completed processing:
![dataProcessingExported](images/dataProcessingExported.png)


- Implements Sales Order input specific validation rules for customer and product data.
- If validation rules are not met, it emails a human reviewer and stops execution.
- If validation rules are met, it executes Sales Order Header and Lines creation.
- Sends acknowledgement email when the sales order is processed successfully or validation rules are not met.
![emailOrderSuccess](images/emailOrderSuccess.png)
![emailInvalidCustomer](images/emailInvalidCustomer.png)

## ⏳ Business Process Flow
![businessProcessFlow](images/businessProcessFlow.png)


## 📄 Document Processor Agent
**Document Processor Agent** is a robust managed agent, packaged solution for end-to-end document processing including **extraction, validation and human monitoring**. It does not require training custom models, instead a relevant sample document can be uploaded, and the maker can configure the attributes that should be extracted and if any validation rules to be applied. For more details please see: https://learn.microsoft.com/en-us/microsoft-copilot-studio/template-managed-document-processor.
### Configuration Wizard
When configuring the Document Processor Agent, to achieve a more deterministic JSON schema that you can leverage in the Sales Order agent to parse the data for the downstream systems, it is recommended to update the Document Processor extraction rules and include a similar prompt:
![docProcessorValidationRulesCustom](images/docProcessorValidationRulesCustom.png)
![docProcessorValidationCustomAdvanced](images/docProcessorValidationCustomAdvanced.png)

## 🤖 Sales Order Processor Agent
**Sales Order Processor Agent** is an agent template to help support **implement an end-to-end document processing flow into downstream apps such as finance and operations**. The agent includes sales order input validations for customer and product details, creation of a sales order header and related lines, as well as acknowledgement emails.
### Components
- **Instructions** – the agent uses generative AI with the next instructions:
![salesOrderAgentInstructions1](images/salesOrderAgentInstructions1.png)
![salesOrderAgentInstructions2](images/salesOrderAgentInstructions2.png)

- **Trigger** : Dataverse trigger for the agent to run when Document Processor completed successfully
![salesOrderAgentTrigger](images/salesOrderAgentTrigger.png)
![salesOrderTriggerFlow](images/salesOrderTriggerFlow.png) 
![salesOrderAgentTriggerFlowDetails](images/salesOrderAgentTriggerFlowDetails.png)


- **Tools**: For implementing deterministic sales order specific validation rules, as well as sales order header and lines creation, several agent flows have been created:
![salesOrderAgentTools](images/salesOrderAgentTools.png)

  - **Get Customer Number Using Name** – agent flow which receives as input customer name and company code and returns the customer number if it’s found in finance and operations.
  - **Validate Product Codes** – agent flow which receives as input a processed data JSON and company code and it checks if the product codes provided are valid. The JSON is the output of Document Processor and it’s received with the trigger body when the Sales Order Processor agent is triggered.
  - **Create Sales Order Header** – agent flow which receives the customer number and company code and creates the sales order in finance and operations and returns the sales order number.
  - **Create Sales Order Items** – agent flow which receives as input the processed data JSON and sales order number. It will use an AI Builder prompt to extract the product array from the input JSON. It will iterate through the array and create the sales order lines for the product code, quantity, and unit of measure provided.
  - **AI Builder** – custom prompt to extract the items from an input JSON
  ![salesOrderAgentPromptItems](images/salesOrderAgentPromptItems.png)

  - **Send an email (V2)** – connector action which sends email with input as per agent instructions.

## Considerations for configuration
When instantiating the sales order agent template, consider the following to make the agent work for your specific needs and data:
 - Update the agent instructions to email the relevant mailbox
 - Company Code – the agent flows receiving this input parameter use a test value ‘usmf’. You may want to update this in the input parameters of the agent flows within the agent in Copilot Studio.
 - Customer - Sales order processor validates customer name and product codes. Consider if this is necessary for your organization, and update as needed e.g. you may chose to implement this validation in the Document Processor validation rules, or instead of identifying the customer by name, identifying customer by email if its provided – for this change, ensure to update the instructions and the Get Customer Number agent flow filter criteria accordingly.
- Product details – The sales order processor is using product code, quantity, and unit of measure for order line-item creation and it relies on the default sales order settings for sales order warehouse.
- As you are testing the end-to-end flow initially you may choose to send the acknowledgement emails initially to an internal reviewer and then forward the email to the initiating customer.
- If you are processing many items per order, in the Create Sales Order Items agent flow you may want to move the action Respond to the agent before the foreach action for creating the lines, and after the foreach include a new action in this flow for email sending that the creation of the items was successful.
## ✅ Prerequisites
 - Connected Dataverse and finance and operations environment
 - Dataverse virtual tables enabled: Released products V2 (mserp). For more details please see https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/power-platform/enable-virtual-entities 
 - Document Processor Agent installed and configured. For mode details please see https://learn.microsoft.com/en-us/microsoft-copilot-studio/template-managed-document-processor
 - System Administrator role