Restrict access with Conditional access
=======================================

You can limit access to Microsoft Dynamics 365 for Finance and
Operations by using Conditional access. Conditional access is a
capability of Azure Active Directory. With Conditional access, you can
implement automated access control decisions for accessing your cloud
apps that are based on conditions.

![RestrictAccessWithConditionalAccess](/CloudSecurity/ConditionalAccess/RestrictAccessWithConditionalAccess.png)

Common scenarios for using conditional access
---------------------------------------------

### Location/ IP ranges: 

Azure AD is accessible from anywhere. What if an access attempt is
performed from a network location that is not under the control of your
IT department? A username and password combination might be good enough
as proof of identity for access attempts from your corporate network.
What if you demand a stronger proof of identity for access attempts that
are initiated from other unexpected countries or regions of the world?
What if you even want to block access attempts from certain locations?

### [Device management](https://docs.microsoft.com/en-us/azure/active-directory/conditional-access/conditions#device-platforms): 

In Azure AD, users can access cloud apps from a broad range of devices
including mobile and personal devices. What if you demand that access
attempts only be performed with devices that are managed by your IT
department? What if you even want to block certain device types from
accessing cloud apps in your environment?

### [Sign-in risk](https://docs.microsoft.com/en-us/azure/active-directory/conditional-access/conditions#sign-in-risk): 

Azure AD Identity Protection detects sign-in risks. How do you restrict
access if a detected sign-in risk indicates a bad actor? What if you
would like to get stronger evidence that a sign-in was performed by the
legitimate user? What if your doubts are strong enough to even block
specific users from accessing an app?

Requirements & consideration for enabling Conditional access
------------------------------------------------------------

1.  The Azure Active Directory tenant must have Active Directory Premium
    enabled, click
    [here](https://azure.microsoft.com/en-us/pricing/details/active-directory/)
    for details.

2.  Conditional Access policies defined for Microsoft ERP application
    are applied to all environments within the tenant.

3.  Conditional access excludes the following scenarios:

    a.  Any Dynamics 365 integrations authenticating through Web
        Apps/shared secret; however, it works with native app.

    b.  With Microsoft Logic Apps and Power Automate, at the time
        signing into the connector, it checks the login for Conditional
        access, however, once the connection is established, it does not
        check the conditional accesss on each call. For example, it does
        not check IP of the caller each time, but it checks the IP of
        the caller at the time of signing into the connector for the
        first time.

    c.  Dynamics 365 Warehouse Mobile Application

    d.  CPOS & MPOS logins

    e.  Dual write integration -- Dual write doesn\'t run against the
        logged-in Finance and Operations user. As long as Dual write is
        setup and Dynamics 365 for Finance and Operations is accessible,
        it uses App registration & Dual write user to upsert the
        records.

    f.  Finance and Operations Virtual Entities
    
Steps to enable Conditional access with Dynamics 365 for Finance and Operations
-------------------------------------------------------------------------------

1.  Sign into the Azure portal, click on the Azure Active Directory >
    Enterprise applications.

![EnterpriseApplication](/CloudSecurity/ConditionalAccess/EnterpriseApplication.png)

2.  On the next screen you will see Conditional access under security
    section. Click on Conditional Access to add conditions to secure
    Microsoft Dynamics 365 for Finance and Operations.

![ConditionalAccess](/CloudSecurity/ConditionalAccess/ConditionalAccess.png)

3.  Browse to the Conditional Access-Policies page and click on New
    policy button

![NewPolicy](/CloudSecurity/ConditionalAccess/NewPolicy.png)

4.  On the next page, name the Conditional Access policy and define the
    assignment to conditional grant and block the access to the
    resource.

![DefinePolicy](/CloudSecurity/ConditionalAccess/DefinePolicy.png)

5.  Select the Users and groups. You can apply Conditional access at
    multiple levels i.e. Groups, specific user or all users. For
    example, in case you are applying Conditional Access security at
    group level then you can exclude service accounts.

![User](/CloudSecurity/ConditionalAccess/User.png)

6.  Next you will assign the Cloud apps on which you want to apply the
    security, you either apply these Conditional to all apps and exclude
    some or have specific conditions for each app. In case of
    specifically defining security permission for Dynamics 365 for
    finance and operations. Select "**Microsoft Dynamics ERP"** cloud
    app has shown in the figure below.

![CloudApp](/CloudSecurity/ConditionalAccess/CloudApp.png)

7.  Next you will define conditions, details on Sign in risk, Device
    platforms, client apps, Device state and locations can be found on
    the following link:

<https://docs.microsoft.com/en-us/azure/active-directory/conditional-access/conditions>

In this article, we will dig deeper into defining locations as it deals
IP restriction.

8.  To select either block or whitelist certain location, you need to
    first add those IP ranges into Name locations.

![NamedLocation](/CloudSecurity/ConditionalAccess/NamedLocation.png)

Note: Named Locations should be created first before it can be assigned under the conditions for access the resource.  Locations can be defined by going into Enterprise application > Conditional Access policies > Named locations.  

Click on the new locations and enter the IP ranges which are considered
as trust locations.

![OfficeIP](/CloudSecurity/ConditionalAccess/OfficeIP.png)

In this scenario, we are blocking all the locations excluding the
selected locations.

![NSGLocation](/CloudSecurity/ConditionalAccess/NSGLocation.png)

To exclude the trusted locations from conditionally blocking Dynamics
365 for Finance and Operations, click on the exclude tab as shown above.
User can either exclude as the trust locations defined in the name
locations or selectively pick individual trusted location.

Once the exclusion is defined on the locations, switch to include tab to
include all the locations which needed to be blocked.

![LocationInclude](/CloudSecurity/ConditionalAccess/LocationInclude.png)

9.  In the Access control sections, either you define the grant or
    block. Which means when the above conditions are meet then grant the
    access with additional check marked or block the access expect for
    the condition in the excluded list.

![BlockScreenshot](/CloudSecurity/ConditionalAccess/BlockScreenshot.png)

10. Finally, you enable the policy. As soon as you try to access the
    Dynamics 365 for Finance and Operations for any location other then
    exclude one. It will give error message at the time of login

![ErrorMsgPolicy](/CloudSecurity/ConditionalAccess/ErrorMsgPolicy.png)

Known Behavior
--------------
Dynamics 365 for Finance and Operations [Mobile
    App](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/mobile-apps/mobile-app-home-page)
    login is unsuccessful even though 'mobile device' is compliant if
    device complaint is required by Conditional access policy.

Additional resource 
-------------------

<https://docs.microsoft.com/en-us/azure/active-directory/conditional-access/>

<https://docs.microsoft.com/en-us/azure/active-directory/conditional-access/location-condition>

<https://docs.microsoft.com/en-us/azure/active-directory/conditional-access/conditions>

Reference scenarios
-------------------

You can define conditional policy based on your organization need. Below
are few scenarios that you can refer, and design policy based on your
need for your implementation.

### Scenario a: Block all users to login from all locations except few selected locations e.g., IP/Country. 

Define BlockPolicy to include 'All users'

![01.BlockPolicyUsers](/CloudSecurity/ConditionalAccess/01.BlockPolicyUsers.png)

Define BlockPolicy to exclude 'Selected locations'

![02.BlockPolicyExcludeLocation](/CloudSecurity/ConditionalAccess/02.BlockPolicyExcludeLocation.png)

With above setup, if any user logs-in from selected location, then only
he/she can access to Finance and Operations apps.

### Scenario b: Grant all users to login and enforce MFA (Multi Factor Authentication) and Device compliance

Define GrantPolicy to include 'All users'

![03.GrantPolicyAllUsers](/CloudSecurity/ConditionalAccess/03.GrantPolicyAllUsers.png)

Define GrantPolicy to enforce 'Multi-factor authentication' and 'Device
compliant'

![04.GrantPolicyMFA](/CloudSecurity/ConditionalAccess/04.GrantPolicyMFA.png)

### Scenario c: Block all user to login except from all locations except from few selected locations/IP and enforce MFA & Device compliance to grant access.

This requires two policies (BlockPolicy & GrantPolicy):

(a) BlockPolicy: Block all users to login from all locations except few
    selected locations e.g. IP/Country

(b) GrantPolicy: Grant access to all user and enforce MFA & Device
    compliance

You will need to enable both policies. These two policies will be
applied as 'AND' condition.
