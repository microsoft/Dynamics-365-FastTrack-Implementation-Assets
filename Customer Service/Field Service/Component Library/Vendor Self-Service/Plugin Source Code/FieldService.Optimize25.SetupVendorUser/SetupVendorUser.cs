using System;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;

namespace FieldService.Optimize25.SetupVendorUser
{
    public class SetupVendorUser : IPlugin
    {
        public void Execute(IServiceProvider serviceProvider)
        {
            // Obtain the execution context and org service
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));
            var factory = (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));
            var service = factory.CreateOrganizationService(context.UserId);
            var tracingService = (ITracingService)serviceProvider.GetService(typeof(ITracingService));

            tracingService.Trace("SetupVendorUser plugin started");

            // Check if the primary entity is systemuser and the message is create
            if (context.PrimaryEntityName.ToLower() == "systemuser" && context.MessageName.ToLower() == "create")
            {
                tracingService.Trace("SetupVendorUser plugin started on create of systemuser");

                // Get the target entity
                Entity targetUser = (Entity)context.InputParameters["Target"];

                try
                {
                    // Get the post image
                    if (context.PostEntityImages.Contains("PostImage"))
                    {
                        Entity postImage = context.PostEntityImages["PostImage"];

                        tracingService.Trace("PostImage retrieved - querying for contact where emailaddress1 = {0}", postImage["internalemailaddress"]);

                        // Query contact based on email and setup contractor flag
                        QueryExpression query = new QueryExpression("contact")
                        {
                            ColumnSet = new ColumnSet("contactid", "fullname", "o25fs_setuptechnician", "o25fs_bookableresourceid", "o25fs_startlocation", "o25fs_endlocation", "o25fs_organizationalunitid",
                            "o25fs_displayonscheduleboard", "o25fs_enableforavailabilitysearch", "o25fs_hourlyrate", "o25fs_timeoffapprovalrequired", "o25fs_warehouseid", "ownerid",
                            "address1_latitude", "address1_longitude"),
                            Criteria = new FilterExpression
                            {
                                Conditions =
                                {
                                    new ConditionExpression("emailaddress1", ConditionOperator.Equal, postImage["internalemailaddress"]),
                                    new ConditionExpression("o25fs_setuptechnician", ConditionOperator.Equal, true)
                                }
                            }
                        };

                        EntityCollection results = service.RetrieveMultiple(query);

                        if (results.Entities.Count > 0)
                        {
                            tracingService.Trace("Contact found - updating User record coordinates");
                            Entity contact = results.Entities[0];

                            // Update systemuser coordinates
                            if (contact.Attributes.Contains("address1_latitude") && contact.Attributes.Contains("address1_longitude"))
                            {
                                tracingService.Trace("Updating User record coordinates");

                                Entity systemuser = new Entity("systemuser", targetUser.Id);
                                systemuser.Attributes["address1_latitude"] = contact.Attributes["address1_latitude"];
                                systemuser.Attributes["address1_longitude"] = contact.Attributes["address1_longitude"];
                                service.Update(systemuser);

                                tracingService.Trace("User record coordinates updated");
                            }

                            // Create bookable resource booking record
                            tracingService.Trace("Creating Bookable Resource record");

                            Entity bookableResource = new Entity("bookableresource");
                            bookableResource["userid"] = new EntityReference("systemuser", targetUser.Id);
                            bookableResource["name"] = contact.Attributes["fullname"];
                            bookableResource["resourcetype"] = new OptionSetValue(3); //User

                            if (contact.Attributes.Contains("o25fs_startlocation"))
                                bookableResource["msdyn_startlocation"] = contact.Attributes["o25fs_startlocation"];

                            if (contact.Attributes.Contains("o25fs_endlocation"))
                                bookableResource["msdyn_endlocation"] = contact.Attributes["o25fs_endlocation"];

                            if (contact.Attributes.Contains("o25fs_organizationalunitid"))
                                bookableResource["msdyn_organizationalunit"] = (EntityReference)contact.Attributes["o25fs_organizationalunitid"];
                            else
                                bookableResource["msdyn_organizationalunit"] = null;

                            if (contact.Attributes.Contains("o25fs_displayonscheduleboard"))
                                bookableResource["msdyn_displayonscheduleboard"] = contact.Attributes["o25fs_displayonscheduleboard"];

                            if (contact.Attributes.Contains("o25fs_enableforavailabilitysearch"))
                                bookableResource["msdyn_displayonscheduleassistant"] = contact.Attributes["o25fs_enableforavailabilitysearch"];

                            if (contact.Attributes.Contains("o25fs_hourlyrate"))
                                bookableResource["msdyn_hourlyrate"] = contact.Attributes["o25fs_hourlyrate"];
                            else
                                bookableResource["msdyn_hourlyrate"] = null;

                            if (contact.Attributes.Contains("o25fs_timeoffapprovalrequired"))
                                bookableResource["msdyn_timeoffapprovalrequired"] = contact.Attributes["o25fs_timeoffapprovalrequired"];

                            if (contact.Attributes.Contains("o25fs_warehouseid"))
                                bookableResource["msdyn_warehouse"] = (EntityReference)contact.Attributes["o25fs_warehouseid"];
                            else
                                bookableResource["msdyn_warehouse"] = null;

                            if (contact.Attributes.Contains("ownerid"))
                                bookableResource["ownerid"] = (EntityReference)contact.Attributes["ownerid"];

                            Guid bookableresourceid = service.Create(bookableResource);

                            tracingService.Trace("Bookable Resource created");

                            // Update contact's o25fs_bookableresourceid lookup field
                            tracingService.Trace("Updating contact with bookableresourceid");

                            Entity contactUpdate = new Entity("contact", contact.Id);
                            contactUpdate["o25fs_bookableresourceid"] = new EntityReference("bookableresource", bookableresourceid);
                            service.Update(contactUpdate);

                            tracingService.Trace("Contact updated with bookableresourceid");

                            // Get all Vendor Characteristics for the contact and create Bookable Resource Characteristics
                            tracingService.Trace("Getting Vendor Characteristics");
                            QueryExpression vcquery = new QueryExpression("o25fs_vendorcharacteristic")
                            {
                                ColumnSet = new ColumnSet("o25fs_vendorcharacteristicid", "o25fs_characteristicid", "o25fs_ratingvalueid"),
                                Criteria = new FilterExpression
                                {
                                    Conditions =
                                    {
                                        new ConditionExpression("o25fs_vendorcontactid", ConditionOperator.Equal, contact.Id)
                                    }
                                }
                            };

                            EntityCollection vcresults = service.RetrieveMultiple(vcquery);

                            tracingService.Trace("Vendor Characteristics retrieved");

                            foreach (Entity vendorCharacteristic in vcresults.Entities)
                            {
                                tracingService.Trace("Creating Bookable Resource Characteristic");
                                Entity bookableResourceCharacteristic = new Entity("bookableresourcecharacteristic");

                                bookableResourceCharacteristic["characteristic"] = vendorCharacteristic.Attributes["o25fs_characteristicid"];

                                if (vendorCharacteristic.Attributes.Contains("o25fs_ratingvalueid"))
                                    bookableResourceCharacteristic["ratingvalue"] = vendorCharacteristic.Attributes["o25fs_ratingvalueid"];

                                bookableResourceCharacteristic["resource"] = new EntityReference("bookableresource", bookableresourceid);

                                service.Create(bookableResourceCharacteristic);
                                tracingService.Trace("Bookable Resource Characteristic created");
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    throw new InvalidPluginExecutionException($"An error occurred in SetupVendorUser plugin: {ex.Message}", ex);
                }
            }

            // If the primary entity is systemuser and the message is update
            else if (context.PrimaryEntityName.ToLower() == "systemuser" && context.MessageName.ToLower() == "update")
            {
                tracingService.Trace("SetupVendorUser plugin started on update of systemuser");

                // Get the target entity and preimage
                Entity targetUser = (Entity)context.InputParameters["Target"];
                Entity systemUser = service.Retrieve("systemuser", targetUser.Id, new ColumnSet("internalemailaddress"));

                // Check if the address1_latitude or address1_longitude has changed and if the depth is not 2
                // We only want to let depth of 2 through since that allows the plugin for copying coordinates from contact to systemuser but reverts other updates
                if ((targetUser.Attributes.Contains("address1_latitude") || targetUser.Attributes.Contains("address1_longitude")) && context.Depth != 2)
                {
                    tracingService.Trace($"SystemUser coordinates changed - Depth: {context.Depth}");

                    // Get latitude and longitude from the contact
                    var query = new QueryExpression("contact")
                    {
                        ColumnSet = new ColumnSet("address1_latitude", "address1_longitude"),
                        Criteria = new FilterExpression
                        {
                            Conditions =
                            {
                                new ConditionExpression("emailaddress1", ConditionOperator.Equal, systemUser.Attributes["internalemailaddress"])
                            }
                        }
                    };

                    EntityCollection results = service.RetrieveMultiple(query);

                    // Check to ensure both latitude and longitude are not null and not 0
                    if (results.Entities.Count > 0 && results.Entities[0].Attributes.Contains("address1_latitude") && results.Entities[0].Attributes.Contains("address1_longitude")
                        && (double)results.Entities[0].Attributes["address1_latitude"] != 0 && (double)results.Entities[0].Attributes["address1_longitude"] != 0)
                    {
                        tracingService.Trace("Contact found with coordinates - reverting SystemUser coordinates");

                        Entity contact = results.Entities[0];

                        // Update the SystemUser coordinates
                        targetUser["address1_latitude"] = contact.Attributes["address1_latitude"];
                        targetUser["address1_longitude"] = contact.Attributes["address1_longitude"];

                        tracingService.Trace("SystemUser coordinates reverted pre-operationally");
                    }
                }
            }

            // If the primary entity is not systemuser, check if it is contact
            else if (context.PrimaryEntityName.ToLower() == "contact" && context.MessageName.ToLower() == "update")
            {
                tracingService.Trace("SetupVendorUser plugin started on update of Contact to sync data to Bookable Resource");

                // Get the Target
                Entity targetContact = (Entity)context.InputParameters["Target"];
                // Get the PostImage
                Entity postImage = context.PostEntityImages["PostImage"];

                try
                {
                    // Check if the contact is a contractor
                    if (postImage.Attributes.Contains("o25fs_bookableresourceid"))
                    {
                        tracingService.Trace("Contact has a Bookable Resource - syncing to Bookable Resource");
                        EntityReference o25fs_bookableresourceid = (EntityReference)postImage.Attributes["o25fs_bookableresourceid"];
                        tracingService.Trace("Bookable Resource ID: {0}", o25fs_bookableresourceid.Id);

                        // Map fields from contact to bookable resource
                        Entity bookableResource = new Entity("bookableresource", o25fs_bookableresourceid.Id);

                        if (postImage.Attributes.Contains("o25fs_startlocation"))
                            bookableResource["msdyn_startlocation"] = postImage.Attributes["o25fs_startlocation"];

                        if (postImage.Attributes.Contains("o25fs_endlocation"))
                            bookableResource["msdyn_endlocation"] = postImage.Attributes["o25fs_endlocation"];

                        if (postImage.Attributes.Contains("o25fs_organizationalunitid"))
                            bookableResource["msdyn_organizationalunit"] = (EntityReference)postImage.Attributes["o25fs_organizationalunitid"];
                        else
                            bookableResource["msdyn_organizationalunit"] = null;

                        if (postImage.Attributes.Contains("o25fs_displayonscheduleboard"))
                            bookableResource["msdyn_displayonscheduleboard"] = postImage.Attributes["o25fs_displayonscheduleboard"];

                        if (postImage.Attributes.Contains("o25fs_enableforavailabilitysearch"))
                            bookableResource["msdyn_displayonscheduleassistant"] = postImage.Attributes["o25fs_enableforavailabilitysearch"];

                        if (postImage.Attributes.Contains("o25fs_hourlyrate"))
                            bookableResource["msdyn_hourlyrate"] = postImage.Attributes["o25fs_hourlyrate"];
                        else
                            bookableResource["msdyn_hourlyrate"] = null;

                        if (postImage.Attributes.Contains("o25fs_timeoffapprovalrequired"))
                            bookableResource["msdyn_timeoffapprovalrequired"] = postImage.Attributes["o25fs_timeoffapprovalrequired"];

                        if (postImage.Attributes.Contains("o25fs_warehouseid"))
                            bookableResource["msdyn_warehouse"] = (EntityReference)postImage.Attributes["o25fs_warehouseid"];
                        else
                            bookableResource["msdyn_warehouse"] = null;

                        // Sync Owner
                        if (postImage.Attributes.Contains("ownerid"))
                            bookableResource["ownerid"] = (EntityReference)postImage.Attributes["ownerid"];

                        // Update the Bookable Resource
                        tracingService.Trace("Updating Bookable Resource");
                        service.Update(bookableResource);
                        tracingService.Trace("Bookable Resource updated");

                        if (targetContact.Attributes.Contains("address1_latitude") && targetContact.Attributes.Contains("address1_longitude"))
                        {
                            tracingService.Trace("Contact has address changes - updating SystemUser coordinates");

                            Entity bookableResourceRecord = service.Retrieve("bookableresource", o25fs_bookableresourceid.Id, new ColumnSet("userid"));
                            tracingService.Trace("Bookable Resource record retrieved");

                            // Update the SystemUser coordinates
                            if (bookableResourceRecord.Attributes.Contains("userid"))
                            {
                                tracingService.Trace("SystemUser found - updating coordinates");
                                Entity systemUser = new Entity("systemuser", ((EntityReference)bookableResourceRecord.Attributes["userid"]).Id);
                                systemUser["address1_latitude"] = targetContact.Attributes["address1_latitude"];
                                systemUser["address1_longitude"] = targetContact.Attributes["address1_longitude"];
                                service.Update(systemUser);
                                tracingService.Trace("SystemUser coordinates updated");
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    throw new InvalidPluginExecutionException($"An error occurred in SetupVendorUser plugin: {ex.Message}");
                }
            }

            // If the primary entity is not systemuser or contact, check if it is o25fs_vendorcharacteristic
            else if (context.PrimaryEntityName.ToLower() == "o25fs_vendorcharacteristic")
            {
                if (context.MessageName.ToLower() == "create")
                {
                    tracingService.Trace("SetupVendorUser plugin started on create of Vendor Characteristic to sync data to Bookable Resource Characteristic");

                    // Get the PostImage
                    Entity targetVendorCharacteristic = (Entity)context.InputParameters["Target"];
                    Entity postImage = context.PostEntityImages["PostImage"];

                    try
                    {
                        if (postImage.Attributes.Contains("o25fs_vendorcontactid"))
                        {
                            tracingService.Trace("Vendor Characteristic created - creating Bookable Resource Characteristic");
                            EntityReference o25fs_vendorcontactid = (EntityReference)postImage.Attributes["o25fs_vendorcontactid"];
                            Entity contact = service.Retrieve("contact", o25fs_vendorcontactid.Id, new ColumnSet("o25fs_bookableresourceid"));

                            if (contact.Attributes.Contains("o25fs_bookableresourceid"))
                            {
                                EntityReference o25fs_bookableresourceid = (EntityReference)contact.Attributes["o25fs_bookableresourceid"];

                                Entity bookableResourceCharacteristic = new Entity("bookableresourcecharacteristic");
                                bookableResourceCharacteristic["characteristic"] = postImage.Attributes["o25fs_characteristicid"];
                                if (postImage.Attributes.Contains("o25fs_ratingvalueid"))
                                    bookableResourceCharacteristic["ratingvalue"] = postImage.Attributes["o25fs_ratingvalueid"];
                                bookableResourceCharacteristic["resource"] = o25fs_bookableresourceid;

                                tracingService.Trace("Creating Bookable Resource Characteristic");
                                service.Create(bookableResourceCharacteristic);
                                tracingService.Trace("Bookable Resource Characteristic created");
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        throw new InvalidPluginExecutionException($"An error occurred in SetupVendorUser plugin: {ex.Message}");
                    }
                }

                else if (context.MessageName.ToLower() == "delete")
                {
                    tracingService.Trace("SetupVendorUser plugin started on delete of Vendor Characteristic to sync data to Bookable Resource Characteristic");

                    // Get the PreImage
                    Entity preImage = context.PreEntityImages["PreImage"];

                    try
                    {
                        // Query for the Bookable Resource Characteristic
                        if (preImage.Attributes.Contains("o25fs_vendorcontactid"))
                        {
                            tracingService.Trace("Vendor Characteristic deleted - getting Bookable Resource");

                            Entity contact = service.Retrieve("contact", ((EntityReference)preImage.Attributes["o25fs_vendorcontactid"]).Id, new ColumnSet("o25fs_bookableresourceid"));

                            if (contact.Attributes.Contains("o25fs_bookableresourceid"))
                            {
                                EntityReference o25fs_bookableresourceid = (EntityReference)contact.Attributes["o25fs_bookableresourceid"];

                                tracingService.Trace("Bookable Resource found - querying for Bookable Resource Characteristic");
                                var query = new QueryExpression("bookableresourcecharacteristic")
                                {
                                    ColumnSet = new ColumnSet("bookableresourcecharacteristicid"),
                                    Criteria = new FilterExpression
                                    {
                                        Conditions =
                                        {
                                            new ConditionExpression("resource", ConditionOperator.Equal, o25fs_bookableresourceid.Id),
                                            new ConditionExpression("characteristic", ConditionOperator.Equal, ((EntityReference)preImage.Attributes["o25fs_characteristicid"]).Id)
                                        }
                                    }
                                };

                                EntityCollection results = service.RetrieveMultiple(query);

                                // Delete the Bookable Resource Characteristic
                                if (results.Entities.Count > 0)
                                {
                                    tracingService.Trace("Bookable Resource Characteristic found - deleting");
                                    service.Delete("bookableresourcecharacteristic", results.Entities[0].Id);
                                    tracingService.Trace("Bookable Resource Characteristic deleted");
                                }
                            }
                        }

                    }
                    catch (Exception ex)
                    {
                        throw new InvalidPluginExecutionException($"An error occurred in SetupVendorUser plugin: {ex.Message}");
                    }
                }
            }
        }
    }
}
