LIB_ODATA implements two classes. 

Class HttpRequest ( to execute Get, Post, Patch, Delete RestAPI calls)
methods:
  * new ( <tenant>, <environment URL>)
  * Authenticate()
  * Login()
  * WebCall()
  
Before using the HttpRequest you need to setup the Authentication as described in https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/services-home-page
  
Authentication can be done via ClientId and ClientSecret (WebApplication) or UserName, Password and ClientId (Native).
If your company enforces Multi Factor authentication, you can replace the Authenticate methods by the Login method, which opens a browser tab to enter your credentials with MFA.

The library has a PowerShell script (EncryptCredentials.ps1) to create the file "secure.txt" where you store the encrypted values of these authenthication keys. 
Open this file in ISE, replace the values between <> with your values and run the script to create the secure file. 

 After the encrypted file has been created, make sure to remove the unencrypted fields from the PowerShell file.

 Class Credentials is for internal use.
