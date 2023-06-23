var extnSample = extnSample || {};
var extnSample = {
    Actions: {
        init: function () {
            try {

                Microsoft.CIFramework.setClickToAct(true);
                Microsoft.CIFramework.addHandler("onclicktoact", extnSample.CommonFunctions.clickToActHandler);
                Microsoft.CIFramework.addHandler("onSessionSwitched", extnSample.CommonFunctions.onSessionSwitched);
                Microsoft.CIFramework.addHandler("onSessionClosed", extnSample.CommonFunctions.onSessionClosed);
                Microsoft.CIFramework.addHandler("onPageNavigate", extnSample.CommonFunctions.onPageNavigate);
                extnSample.CommonFunctions.createSession(true);
            }
            finally {
                extnSample.CommonFunctions.newGuid("extn_interactionid");
                extnSample.CommonFunctions.onChangeNotifyContext();
                extnSample.CommonFunctions.onChangeSessionContext();
            }
        },
        notifyEvent: function () {
            var input = extnSample.CommonFunctions.onChangeNotifyContext();

            var isDefault;
            if (input != null && input.templateParameters != null && input.templateParameters.extnbr_session_template == "extn_default_session")
                isDefault = true;
            else
                isDefault = false;

            if (!isDefault) {
                Microsoft.CIFramework.notifyEvent(input).then(
                    function success(result) {
                        var res = JSON.parse(result);
                        if (res.actionName == "Accept")
                            extnSample.CommonFunctions.createSession(isDefault);
                        else
                            extnSample.CommonFunctions.registerReject(res.actionName, res.responseReason);
                    },
                    function (error) { });
            }
            else {
                alert("Please select the media type.");
            }
            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.notifyEvent.toString());
        },
        notifyEventCustomPage: function () {
            var input = extnSample.CommonFunctions.onChangeNotifyContextCustomPage();

            var isDefault;
            if (input != null && input.templateParameters != null && input.templateParameters.extnbr_session_template == "extn_default_session")
                isDefault = true;
            else
                isDefault = false;

            if (!isDefault) {
                Microsoft.CIFramework.notifyEvent(input).then(
                    function success(result) {
                        var res = JSON.parse(result);
                        if (res.actionName == "Accept")
                            extnSample.CommonFunctions.createSessionCustomPage(isDefault);
                        else
                            extnSample.CommonFunctions.registerReject(res.actionName, res.responseReason);
                    },
                    function (error) { });
            }
            else {
                alert("Please select the media type.");
            }
            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.notifyEventCustomPage.toString());
        },
        // Get all session
        getAllSessions: function () {
            Microsoft.CIFramework.getAllSessions().then(
                function success(result) {
                    alert(result);
                    return result;
                },
                function (error) {
                }
            );

            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.getAllSessions.toString());
        },
        // Get focused session
        getFocusedSession: function () {

            Microsoft.CIFramework.getFocusedSession().then(
                function success(result) {
                    alert(result);
                    return result;
                },
                function (error) {
                }
            );

            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.getFocusedSession.toString());
        },
        setSessionTitle: function () {
            var input =
            {
                sessionId: extnSample.CommonFunctions.getFocusedSession(),
                customerName: "Changed session title"
            };

            Microsoft.CIFramework.setSessionTitle(input);
            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.setSessionTitle.toString());
        },
        notifyEventOnSession: function () {
            Microsoft.CIFramework.getAllSessions().then(
                function success(result) {
                    for (let index = 0; index < result.length; index++) {
                        const element = result[index];

                        Microsoft.CIFramework.notifyNewActivity(element, 2).then(
                            function success(result) {
                            },
                            function (error) {
                            }
                        );
                    }
                },
                function (error) {
                });
            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.notifyEventOnSession.toString());
        },
        notifyUrgentEventOnSession: function () {
            Microsoft.CIFramework.getAllSessions().then(
                function success(result) {
                    for (let index = 0; index < result.length; index++) {
                        const element = result[index];

                        Microsoft.CIFramework.notifyKpiBreach(element, true, null).then(
                            function success(result) {
                            },
                            function (error) {
                            }
                        );
                    }
                },
                function (error) {
                });
            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.notifyUrgentEventOnSession.toString());
        },
        //Request focus on the non focused session
        requestFocusOnSession: function () {


            Microsoft.CIFramework.getFocusedSession().then(
                function success(current_session) {

                    Microsoft.CIFramework.getAllSessions().then(
                        function success(result) {
                            for (let index = 0; index < result.length; index++) {
                                const element = result[index];
                                if (current_session != element) {
                                    Microsoft.CIFramework.requestFocusSession(element).then(
                                        function success(result) {
                                        },
                                        function (error) {
                                        }
                                    );
                                }
                            }
                        },
                        function (error) {
                        });

                    return current_session;
                },
                function (error) {
                }
            );

            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.requestFocusOnSession.toString());
        },
        setAppearAwayPresence: function () {
            var presenceText = "Appear away"
            Microsoft.CIFramework.setPresence(presenceText).then(
                function (result) {
                    if (!result)
                        console.log("Presence set failed");
                    else
                        console.log("Presence set successfully");
                },
                function (error) {
                    console.log(error);
                });
            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.setAppearAwayPresence.toString());
        },
        createCaseRecord: function () {
            var entityLogicalName = "incident";
            var customerid = document.getElementById("customerRecordId").value;
            var data = {
                "title": document.getElementById("extn_subject").value,
                "customerid_account@odata.bind": "/accounts("+customerid+")",
            }
            // create case record
            var jsonData = JSON.stringify(data);
            Microsoft.CIFramework.createRecord(entityLogicalName, jsonData).then(
                function success(result) {
                    res = JSON.parse(result);
                    console.log("case created with ID: " + res.id);

                    var entityFormOptions = {};
                    entityFormOptions["entityName"] = "incident";
                    entityFormOptions["entityId"] = res.id;

                    var formParameters = {};

                    //Open the form
                    Microsoft.CIFramework.openForm(JSON.stringify(entityFormOptions), JSON.stringify(formParameters)).then(
                        function (success) {
                            console.log(success);
                        },
                        function (error) {
                            console.log(error);
                        }
                    );
                    //perform operations on record creation
                },
                function (error) {
                    console.log(error);
                    //handle error conditions
                });
            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.createPhoneCallRecord.toString());
        },
        onChangeMediaType: function () {
            var mediaType = document.getElementById("extnbr_mediatype").value;

            switch (mediaType) {
                case "0":
                    document.getElementById("extnbr_notify_template").value = "N/A";
                    document.getElementById("extnbr_session_template").value = "extn_default_session";
                    break;
                case "1":
                    document.getElementById("extnbr_notify_template").value = "extn_voice_notification";
                    document.getElementById("extnbr_session_template").value = "extn_voice_identified_session";
                    break;
                case "2":
                    document.getElementById("extnbr_notify_template").value = "extn_email_identified_notification";
                    document.getElementById("extnbr_session_template").value = "extn_email_identified_session";
                    break;
                case "3":
                    document.getElementById("extnbr_notify_template").value = "extn_chat_notification";
                    document.getElementById("extnbr_session_template").value = "extn_chat_session";
                    break;
            }

            extnSample.CommonFunctions.onChangeNotifyContext();
            extnSample.CommonFunctions.onChangeSessionContext();
        },
        onChangeCustomerEntityName: function () {
            var customerEntityName = document.getElementById("customerEntityName").value;
            if (customerEntityName == "contact") {
                document.getElementById("customerName").value = "Jacob John";
                document.getElementById("customerRecordId").value = "29b7a247-bebb-ed11-83ff-00224805c003";
            }
            else {
                document.getElementById("customerEntityName").value = "account";
                document.getElementById("customerName").value = "Contoso Bank";
                document.getElementById("customerRecordId").value = "ea7092de-6dbe-ed11-83ff-00224805c952";
            }

            extnSample.CommonFunctions.onChangeNotifyContext();
            extnSample.CommonFunctions.onChangeSessionContext();
        },
        closeCurrentTab: function () {
            Microsoft.CIFramework.getFocusedTab().then(
                function success(result) {
                    console.log(result);
                    alert("Closing tab " + result);
                    Microsoft.CIFramework.closeTab(result).then(
                        function (isClosed) {
                            alert("Tab closed");
                        },
                        function (error) {
                            alert("Error occurred while closing tab :" + error);
                        });
                },
                function (error) {
                    console.log(error.message);
                    // handle error conditions
                }
            );

            extnSample.CommonFunctions.pushFunctionImplementation(extnSample.Actions.closeCurrentTab.toString());
        }
    },
    CommonFunctions: {
        newGuid: function (target) {
            var guid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
                var r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
            });
            document.getElementById(target).value = guid;
            extnSample.CommonFunctions.onChangeNotifyContext();
            extnSample.CommonFunctions.onChangeSessionContext();
        },
        createSession: function (isDefault) {
            var input;
            if (isDefault)
                input = extnSample.CommonFunctions.getDefaultSessionContext(); // Get default context
            else
                input = extnSample.CommonFunctions.onChangeSessionContext(); // Get session context

            Microsoft.CIFramework.createSession(input).then(function success(sessionId) {
                if (!isDefault) {
                    extnSample.CommonFunctions.newGuid("extn_interactionid");
                    extnSample.CommonFunctions.getSessionContext(sessionId);
                }
            }, function (error) { });

        },
        getDefaultSessionContext: function () {

            var input = {
                templateName: "extn_default_session",//document.getElementById("extnbr_session_template").value,
                templateParameters: {},
                context: extnSample.CommonFunctions.getDefaultNotifyContext()
            }

            document.getElementById("session_context").value = JSON.stringify(input);

            return input;
        },
        onChangeSessionContext: function () {
            var customerName = document.getElementById("customerName").value;
            var customerEntityName = document.getElementById("customerEntityName").value;
            var customerRecordId = document.getElementById("customerRecordId").value;

            var extnbr_mediatype = document.getElementById("extnbr_mediatype").value;
            var extnbr_telephone = document.getElementById("extnbr_telephone").value;
            var extn_email_address = document.getElementById("extn_email_address").value;
            var extn_subject = document.getElementById("extn_subject").value;
            var extn_interactionid = document.getElementById("extn_interactionid").value;

            var input = {
                templateName: document.getElementById("extnbr_session_template").value,
                templateParameters: {
                    customerName: customerName,
                    customerEntityName: customerEntityName,
                    customerRecordId: customerRecordId,
                    extn_media_type: parseInt(extnbr_mediatype),
                    extn_phonenumber: extnbr_telephone,
                    extn_email_address: extn_email_address,
                    extn_subject: extn_subject,
                    extn_interactionid: extn_interactionid
                },
                context: {
                    customerName: customerName,
                    customerEntityName: customerEntityName,
                    customerRecordId: customerRecordId,
                    extn_media_type: parseInt(extnbr_mediatype),
                    extn_phonenumber: extnbr_telephone,
                    extn_email_address: extn_email_address,
                    extn_subject: extn_subject,
                    extn_interactionid: extn_interactionid
                }
            }

            document.getElementById("session_context").value = JSON.stringify(input);

            return input;
        },
        getDefaultNotifyContext: function () {

            var extnbr_session_template = "extn_default_session";

            var input = {
                templateName: document.getElementById("extnbr_notify_template").value,
                templateParameters: {
                    extnbr_session_template: extnbr_session_template
                }
            }

            document.getElementById("notify_context").value = JSON.stringify(input);

            return input;
        },
        getSessionContext: function (sessionId) {
            Microsoft.CIFramework.getSession(sessionId).then(
                function success(result) {
                    var mediaType = result.get("context").extn_media_type;

                    switch (mediaType) {
                        case 1:
                            document.getElementById("voice_png").scrollIntoView();
                            break;
                        case 3:
                            document.getElementById("chat_png").scrollIntoView();
                            break;
                        default:
                            document.getElementById("cif-page").scrollIntoView();
                    }
                },
                function (error) {
                }
            );
        },
        onChangeNotifyContext: function () {
            var extnbr_notify_template = document.getElementById("extnbr_notify_template").value;
            var extnbr_session_template = document.getElementById("extnbr_session_template").value;
            var extnbr_customerName = document.getElementById("customerName").value;
            var extnbr_mediatype = document.getElementById("extnbr_mediatype").value;
            var extnbr_telephone = document.getElementById("extnbr_telephone").value;
            var extn_email_address = document.getElementById("extn_email_address").value;
            var extn_subject = document.getElementById("extn_subject").value;
            var extn_interactionid = document.getElementById("extn_interactionid").value;

            var customerRecordId = document.getElementById("customerRecordId").value;
            var customerEntityName = document.getElementById("customerEntityName").value;
            var input = {
                templateName: extnbr_notify_template,
                templateParameters: {
                    extnbr_session_template: extnbr_session_template,
                    customerName: extnbr_customerName,
                    customerEntityName: customerEntityName,
                    customerRecordId: customerRecordId,
                    extn_media_type: parseInt(extnbr_mediatype),
                    extn_phonenumber: extnbr_telephone,
                    extn_email_address: extn_email_address,
                    extn_subject: extn_subject,
                    extn_interactionid: extn_interactionid
                }
            }

            document.getElementById("notify_context").value = JSON.stringify(input);

            return input;
        },
        registerReject: function () {
            var entityLogicalName = "task";
            var data = {
                "subject": actionName + " - " + responseReason,
                "description": JSON.stringify(extnSample.CommonFunctions.onChangeNotifyContext())
            }
            var jsonData = JSON.stringify(data);
            Microsoft.CIFramework.createRecord(entityLogicalName, jsonData).then(
                function success(result) {
                    alert("Taks Created: " + jsonData);
                    res = JSON.parse(result);
                },
                function (error) {
                    alert(error);
                }
            );
        },
        onChangeNotifyContextCustomPage: function () {
            var extnbr_notify_template = document.getElementById("extnbr_notify_template").value;
            var extnbr_session_template = document.getElementById("extnbr_session_template_custompage").value;
            var extnbr_customerName = document.getElementById("customerName").value;
            var extnbr_mediatype = document.getElementById("extnbr_mediatype").value;
            var extnbr_telephone = document.getElementById("extnbr_telephone").value;
            var extn_email_address = document.getElementById("extn_email_address").value;
            var extn_subject = document.getElementById("extn_subject").value;
            var extn_interactionid = document.getElementById("extn_interactionid").value;
            var extn_firstname = document.getElementById("extn_firstname").value;
            var extn_lastname = document.getElementById("extn_lastname").value;
            var extn_businessphone = document.getElementById("extn_businessphone").value;
            var extn_streetaddress = document.getElementById("extn_streetaddress").value;
            var extn_city = document.getElementById("extn_city").value;
            var extn_state = document.getElementById("extn_State").value;
            var extn_zipcode = document.getElementById("extn_zipcode").value;

            var input = {
                templateName: extnbr_notify_template,
                templateParameters: {
                    extnbr_session_template: extnbr_session_template,
                    name: "extn_customsearch_c76f9",
                    recordId: {
                        "firstname": extn_firstname,
                        "lastname": extn_lastname,
                        "mobilePhone": extnbr_telephone,
                        "businessPhone": extn_businessphone,
                        "emailaddress": extn_email_address,
                        "streetaddress": extn_streetaddress,
                        "city": extn_city,
                        "state": extn_state,
                        "zipcode": extn_zipcode
                    }
                }
            };
            document.getElementById("notify_context").value = JSON.stringify(input);
            return input;
        },
        createSessionCustomPage: function (isDefault) {
            var input;
            if (isDefault)
                input = extnSample.CommonFunctions.getDefaultSessionContext(); // Get default context
            else
                input = extnSample.CommonFunctions.onChangeSessionContextCustomPage(); // Get session context

            /*CIFSupport.saveChatHistoryURL(input);*/
            Microsoft.CIFramework.createSession(input).then(function success(sessionId) {
                // Check if it is the default session
                if (!isDefault) {
                    // Call Dynamics API to manage the business rules and send the current context
                    /*CIFSupport.manageCase(input);*/
                    extnSample.CommonFunctions.newGuid("extn_interactionid");
                    extnSample.CommonFunctions.getSessionContext(sessionId);
                }
            }, function (error) { });
        },
        onChangeSessionContextCustomPage: function () {
            // Retrieve input values from HTML elements
            var extnbr_notify_template = document.getElementById("extnbr_notify_template").value;
            var extnbr_session_template = document.getElementById("extnbr_session_template_custompage").value;
            var extnbr_customerName = document.getElementById("customerName").value;
            var extnbr_mediatype = document.getElementById("extnbr_mediatype").value;
            var extnbr_telephone = document.getElementById("extnbr_telephone").value;
            var extn_email_address = document.getElementById("extn_email_address").value;
            var extn_subject = document.getElementById("extn_subject").value;
            var extn_interactionid = document.getElementById("extn_interactionid").value;
            var extn_firstname = document.getElementById("extn_firstname").value;
            var extn_lastname = document.getElementById("extn_lastname").value;
            var extn_businessphone = document.getElementById("extn_businessphone").value;
            var extn_streetaddress = document.getElementById("extn_streetaddress").value;
            var extn_city = document.getElementById("extn_city").value;
            var extn_state = document.getElementById("extn_State").value;
            var extn_zipcode = document.getElementById("extn_zipcode").value;

            var obj = new Object();
            obj.firstname = extn_firstname;
            obj.lastname = extn_lastname;
            obj.mobilephone = extnbr_telephone;
            obj.businessphone = extn_businessphone;
            obj.emailaddress = extn_email_address;
            obj.streetaddress = extn_streetaddress;
            obj.city = extn_city;
            obj.state = extn_state;
            obj.zipcode = extn_zipcode;
            var jsonString = JSON.stringify(JSON.stringify(obj));

            var params = jsonString;


            // Construct an input object with templateName and templateParameters properties
            var input = {
                templateName: "extnbr_session_template_custompage",
                templateParameters: {
                    name: "extn_customsearch_c76f9",
                    recordId: params
                }
            };


            document.getElementById("session_context").value = JSON.stringify(input);


            // Return the input object
            return input;
        },
        getFocusedSession: function () {
            Microsoft.CIFramework.getFocusedSession().then(
                function success(result) {
                    alert(result);
                    return result;
                },
                function (error) {
                }
            );
        },
        clickToActHandler: function (paramStr) {
            console.log("clickToActHandler called: " + paramStr);
            alert("clickToActHandler called: " + paramStr);
        },
        onSessionSwitched: function (paramStr) {
            let params = JSON.parse(paramStr);
            if (params.focused) {
                extnSample.CommonFunctions.clearNotifyUrgentEventOnSession(params.sessionId);
                extnSample.CommonFunctions.getSessionContext(params.sessionId);
            }
        },
        clearNotifyUrgentEventOnSession: function () {
            Microsoft.CIFramework.notifyKpiBreach(sessionId, false, null).then(
                function success(result) {
                },
                function (error) {
                }
            );
        },
        onSessionClosed: function () {
            let params = JSON.parse(paramStr);
            if (params != null && params.context != null)
                if (params.context.templateParameters != null && params.context.templateParameters["extnbr_session_template"] == "extn_default_session")
                    extnSample.CommonFunctions.createSession(true);
        },
        onPageNavigate: function () {
            alert(paramStr);
        },
        pushFunctionImplementation(fn) {

            if (document.getElementById("notify_context").value === null || document.getElementById("notify_context").value === undefined) {
                document.getElementById("notify_context").value = document.getElementById("notify_context").value + "\n\n Function Definition \n\n" + fn.toString();
            }
            else {
                document.getElementById("notify_context").value = fn.toString();
            }
        }

    }
};