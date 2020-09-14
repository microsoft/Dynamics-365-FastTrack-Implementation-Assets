# Why do I need bootstrapping?
You might have an existing Common Data Service (CDS) or other Dynamics 365 app instance with business data, and you want to enable dual-write connection against it. In this case, you need to bootstrap Common Data Service or other Dynamics 365 app data with company information before enabling dual-write connection.

# Summary
This document describes sample scenarios explaining how to use Azure Data Factory (ADF) to bootstrap data into CDS entities (for DualWrite solution). It doesn’t cover all entities, error handling scenarios, lookup etc. Use this document and template as a reference to setup your own ADF pipeline to import/export data into/from CDS.   
