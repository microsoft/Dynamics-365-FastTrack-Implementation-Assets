LIB_ODATA implements Authentication and Get, Post, Patch, Delete RestAPI calls. 

Authentication can be done via ClientId and ClientSecret or UserName, Password and ClientId.

The library has a file "secure.txt" where you store the encrypted values of these authenthication keys. 

The library has a method encrypt that you use to encrypt the keys and write them to the file secret.txt
For ClientId and ClientSecret you can use following code

using module LIB_OData
cls

[string] $file = "<directory>\secure.txt"
$key = encrypt ""
$value = encrypt ""

Out-File $file
($key+'-'+$value) | Add-Content $file
  
 For Username and Passowrd : 
  
using module LIB_OData
cls

[string] $file = "<directory>\secure.txt"
$key = encrypt ""
$value = encrypt ""

Out-File $file
($key+'-'+$value+'-'+$clientid) | Add-Content $file

