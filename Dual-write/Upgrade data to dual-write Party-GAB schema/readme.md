# Comments for Azure Data Factory template

These are the activities in the template. 

Activity | Description
---|---
1 to 6 | Identify the companies that are enabled for dual-write and build a filter clause for them.
7-1 to 7-9 | Retrieve the data from both Finance and Operations and customer engagement apps and stage the data for upgrade.
8 to 9 | Compare the **Party** number for **Account**, **Contact**, and **Vendor** between Finance and Operations and customer engagement apps. The records that don’t have party number are skipped.
Step 10 | Generate 2 csv files for **Party** records to create in customer engagement apps and Finance and Operations applications.<br>FOCDSParty.csv contains all party records of both systems regardless of whether **Company** is enabled for dual write<br>FONewParty.csv contains the subset of the **Party** which Dataverse is aware, for example, **Account** of type **Prospect**.
11 | Create the **Parties**  in customer engagement apps.
12 | Retrieve the **Party** guids from customer engagement apps and stage them for association with **Account**, **Contact**, and **Vendor** records in the subsequent steps.
13 | Associate the **Account**, **Contact**, and **Vendor** records with the **Party** guid.
14-1 to 14-3 | Update the **Account**, **Contact**, and **Vendor** records in the customer engagement apps with the **Party** guid.
15-1 to 15-3 | Prepare **Contact for Party** records for **Account**, **Contact**, and **Vendor**.
16-1 to 16-7 | Retrieve reference data like salutations, and personal character types, and associate them with **Contact for Party** records.
17 | Merge the **Contact for Party** records for **Account**, **Contact**, and **Vendor**.
18 | Import **Contact for Party** records into customer engagement apps.
