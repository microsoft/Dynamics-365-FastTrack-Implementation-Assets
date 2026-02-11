# Dynamics 365 Commerce - CAPTCHA on Checkout

## Overview
The following samples demonstrate implementing Google's reCAPCHA v2 on checkout.  There are two components to this sample implementation:
1) [Web module (checkout)](./WebModule/README.md): In this implementation, a custom CAPTCHA challenge module is added to the checkout experience.  When the challenge is completed, the resulting token will be associated with the cart.
2) [Server-side trigger](./HeadlessCommerce/README.md):  The checkout framework on Headless Commerce is extended and will look for the CAPTCHA challenge token during payment validation and in the checkout request.  If the token is missing or invalid, then activity is aborted with the appropriate messaging about the CAPTCHA challenge.  


## CAPTCHA
CAPTCHA is an abbreviation for Completely Automated Public Turing test to tell Computers and Humans Apart.  Due to the prevelance of automated bots, CAPTCHA is used to prevent bots from overwhelming or abusing a website.  Some examples include
- Reduction in fake account creation
- Spam reduction, unauthorized advertising on message boards 
- Account security (prevents brute-force attacks)
- Prevention of polling abuse
- Fraud prevention

## reCAPCHA
![reCAPCHA animated image](https://developers.google.com/static/recaptcha/images/newCaptchaAnchor.gif)
Google has a CAPTCHA service called reCAPCHA. For more information, please read their [developer's guide](https://developers.google.com/recaptcha/intro) and [licensing terms](https://cloud.google.com/recaptcha/docs/compare-tiers).    

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us the rights to use your contribution. For details, visit <https://cla.opensource.microsoft.com>.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.