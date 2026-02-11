# Custom Record Identification
In Dynamics365 Omnichannel it is possible to identify the customer on incoming conversation, providing the chance to view account/contact and case details on the Conversation page.  
In the following [article](https://learn.microsoft.com/en-us/dynamics365/customer-service/record-identification-rule) there is the explaination how it works and how it can be used.  
Anyhow in some cases can happen that the customer identificaton must follow custom logic.
Considering the sample where an IVR asks to the caller for the accountnumber in this way the customer identificaton can directly use the accountnumber column, instead of the OOB columns.

## How to customize the Record Identification 
Add the new condition in RI Rule

**Ex:** ```<condition attribute="accountnumber" operator="eq" value="${AccountNumber}" />```

**Note** : It is case sensitive

Change the RI rule in live work stream based on new attribute

**Entity Name** : msdyn_liveworkstreams

**Attribute Name** : msdyn_recordidentificationrule

Use the following ```GET``` request to fetch all the workstream records and find the one to customize the record identification rule by using the name.  
```
GET [Organization URI]/api/data/v9.1/msdyn_liveworkstreams
Accept: application/json  
OData-MaxVersion: 4.0  
OData-Version: 4.0
If-None-Match: null
```  

Make a ```PATCH``` request to the ```msdyn_liveworkstreams``` table record and update the value of the ```msdyn_recordidentificationrule``` column.

```
PATCH [Organization URI]/api/data/v9.1/msdyn_liveworkstreams(6283ab63-5778-e911-8196-000d3af7d71e)
Accept: application/json  
OData-MaxVersion: 4.0  
OData-Version: 4.0
If-None-Match: null

{
    "msdyn_recordidentificationrule":"<RecordIdentificationRuleSet><RecordIdentificationRule><PrimaryEntity LogicalCollectionName="accounts" PrimaryKeyAttribute="accountid" PrimaryNameAttribute="name"/><fetch version="1.0" output-format="xml-platform" mapping="logical" top="2"><entity name="account"><attribute name="accountid" /><attribute name = "name" /><filter type="and"><condition attribute="statuscode" operator="eq" value="1" /><condition attribute="name" operator="eq" value="${Name}" /><condition attribute="telephone1" operator="eq" value="${Phone}" /><condition attribute="emailaddress1" operator="eq" value="${Email}" /><condition attribute="accountnumber" operator="eq" value="${accountnumber}" /></filter></entity></fetch><ContextKey name="msdyn_account_msdyn_ocliveworkitem_Customer" isPreferred="false"/></RecordIdentificationRule><RecordIdentificationRule><PrimaryEntity LogicalCollectionName="contacts" PrimaryKeyAttribute="contactid" PrimaryNameAttribute="fullname"/><fetch version="1.0" output-format="xml-platform" mapping="logical" top="2"><entity name="contact"><attribute name="contactid" /><attribute name = "fullname" /><filter type="and"><condition attribute="statuscode" operator="eq" value="1" /><condition attribute="contactid" operator="eq" source="msdyn_msdyn_ocliveworkitem_msdyn_livechatengagementctx_liveworkitemid" value="${msdyn_portalcontactid}" /><condition attribute="fullname" operator="eq" value="${Name}" /><condition attribute="telephone1" operator="eq" value="${Phone}" /><condition attribute="emailaddress1" operator="eq" value="${Email}" /></filter></entity></fetch><ContextKey name="msdyn_contact_msdyn_ocliveworkitem_Customer" isPreferred="true"/></RecordIdentificationRule><RecordIdentificationRule><PrimaryEntity LogicalCollectionName="incidents" PrimaryKeyAttribute="incidentid" PrimaryNameAttribute="title"/><fetch version="1.0" output-format="xml-platform" mapping="logical" top="2"><entity name="incident"><attribute name="incidentid" /><attribute name = "title" /><filter type="and"><condition attribute="ticketnumber" operator="eq" value="${CaseNumber}" /><condition attribute="statuscode" operator="eq" value="1" /><filter type="or"><filter type="and"><condition attribute="statuscode" operator="eq" value="1" entityname="ac" /><condition attribute="name" operator="eq" value="${Name}" entityname="ac" /><condition attribute="telephone1" operator="eq" value="${Phone}" entityname="ac" /><condition attribute="emailaddress1" operator="eq" value="${Email}" entityname="ac" /></filter><filter type="and"><condition attribute="statuscode" operator="eq" value="1" entityname="co" /><condition attribute="contactid" operator="eq" source="msdyn_msdyn_ocliveworkitem_msdyn_livechatengagementctx_liveworkitemid" value="${msdyn_portalcontactid}" entityname="co" /><condition attribute="fullname" operator="eq" value="${Name}" entityname="co" /><condition attribute="telephone1" operator="eq" value="${Phone}" entityname="co" /><condition attribute="emailaddress1" operator="eq" value="${Email}" entityname="co" /></filter></filter></filter><link-entity name="account" from="accountid" to="customerid" link-type="outer" alias="ac" /><link-entity name="contact" from="contactid" to="customerid" link-type="outer" alias="co" /></entity></fetch><ContextKey name="msdyn_incident_msdyn_ocliveworkitem" /></RecordIdentificationRule></RecordIdentificationRuleSet>"
}
```

Sample updated rule:
```
<RecordIdentificationRuleSet><RecordIdentificationRule><PrimaryEntity LogicalCollectionName="accounts" PrimaryKeyAttribute="accountid" PrimaryNameAttribute="name"/><fetch version="1.0" output-format="xml-platform" mapping="logical" top="2"><entity name="account"><attribute name="accountid" /><attribute name = "name" /><filter type="and"><condition attribute="statuscode" operator="eq" value="1" /><condition attribute="name" operator="eq" value="${Name}" /><condition attribute="telephone1" operator="eq" value="${Phone}" /><condition attribute="emailaddress1" operator="eq" value="${Email}" /><condition attribute="accountnumber" operator="eq" value="${accountnumber}" /></filter></entity></fetch><ContextKey name="msdyn_account_msdyn_ocliveworkitem_Customer" isPreferred="false"/></RecordIdentificationRule><RecordIdentificationRule><PrimaryEntity LogicalCollectionName="contacts" PrimaryKeyAttribute="contactid" PrimaryNameAttribute="fullname"/><fetch version="1.0" output-format="xml-platform" mapping="logical" top="2"><entity name="contact"><attribute name="contactid" /><attribute name = "fullname" /><filter type="and"><condition attribute="statuscode" operator="eq" value="1" /><condition attribute="contactid" operator="eq" source="msdyn_msdyn_ocliveworkitem_msdyn_livechatengagementctx_liveworkitemid" value="${msdyn_portalcontactid}" /><condition attribute="fullname" operator="eq" value="${Name}" /><condition attribute="telephone1" operator="eq" value="${Phone}" /><condition attribute="emailaddress1" operator="eq" value="${Email}" /></filter></entity></fetch><ContextKey name="msdyn_contact_msdyn_ocliveworkitem_Customer" isPreferred="true"/></RecordIdentificationRule><RecordIdentificationRule><PrimaryEntity LogicalCollectionName="incidents" PrimaryKeyAttribute="incidentid" PrimaryNameAttribute="title"/><fetch version="1.0" output-format="xml-platform" mapping="logical" top="2"><entity name="incident"><attribute name="incidentid" /><attribute name = "title" /><filter type="and"><condition attribute="ticketnumber" operator="eq" value="${CaseNumber}" /><condition attribute="statuscode" operator="eq" value="1" /><filter type="or"><filter type="and"><condition attribute="statuscode" operator="eq" value="1" entityname="ac" /><condition attribute="name" operator="eq" value="${Name}" entityname="ac" /><condition attribute="telephone1" operator="eq" value="${Phone}" entityname="ac" /><condition attribute="emailaddress1" operator="eq" value="${Email}" entityname="ac" /></filter><filter type="and"><condition attribute="statuscode" operator="eq" value="1" entityname="co" /><condition attribute="contactid" operator="eq" source="msdyn_msdyn_ocliveworkitem_msdyn_livechatengagementctx_liveworkitemid" value="${msdyn_portalcontactid}" entityname="co" /><condition attribute="fullname" operator="eq" value="${Name}" entityname="co" /><condition attribute="telephone1" operator="eq" value="${Phone}" entityname="co" /><condition attribute="emailaddress1" operator="eq" value="${Email}" entityname="co" /></filter></filter></filter><link-entity name="account" from="accountid" to="customerid" link-type="outer" alias="ac" /><link-entity name="contact" from="contactid" to="customerid" link-type="outer" alias="co" /></entity></fetch><ContextKey name="msdyn_incident_msdyn_ocliveworkitem" /></RecordIdentificationRule></RecordIdentificationRuleSet>
```