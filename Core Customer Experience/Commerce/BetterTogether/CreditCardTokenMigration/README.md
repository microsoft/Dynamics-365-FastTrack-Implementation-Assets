# Credit Card Token Migration

The Credit Card Tokenization project contains sample code for importing an Adyen credit card token file into D365 Finance.

The project consists of an extension to the CreditCardTokenize class, a set of objects for the batch job import, a set of objects for the import entity,  and a table for staging the import data (which is then consumed by the batch job service).

## Installation
A D365 Finance and Operations project has been included for easy install - ImportAdyenCCToken.axpp. For more information on importing an .axpp file see the following: https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/dev-tools/projects#import-an-axpp-file

## Notes
- The code was created under Fleet Management Extensions. You’ll need to port it over to the model of your choosing.
- The code is written assuming that the customer account number is set in the echoData field of the Adyen output.csv file. 

- There is a mapping function mapPaymentMethodToAdyenCardType() in case the file output file from Adyen contains subvariants but this is not currently used.
    - Normally the subvariant and the main CC brand are sent in the JSON object to D365 Commerce and directly added as a property but this is not included in the output.csv file.
    - You will want to get a full test import file and see what payment variants are going to be used. 
    - If subvariants like “visacommericaldebit” or “mccorporatedebit” show up in the file, use the above mapping method.
- The batch job for importing the CC tokens is multithreaded and has a prompt for the number of the threads to use in processing.
- The card’s address fields are being populated off of the address on the customer (line 25 in tokenization class). You may want to change this.