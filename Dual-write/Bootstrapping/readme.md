Why do I need bootstrapping?
----------------------------

You might have an existing Common Data Service (CDS) or other Dynamics
365 app instance with business data, and you want to enable dual-write
connection against it. In this case, you need to bootstrap Common Data
Service or other Dynamics 365 app data with company information before
enabling dual-write connection.

Overview
----------------------------

This document describes sample scenarios explaining how to use Azure
Data Factory (ADF) to bootstrap data into CDS entities (for DualWrite
solution). It doesn't cover all entities, error handling scenarios,
lookup etc. Use this document and template as a reference to setup your
own ADF pipeline to import/update data into CDS.

High-level scenario
-------------------

-   Consider 'Customers' (in Finance & Operations) and 'Account' (in
    CDS) entities for example.

-   Use Initial write to copy reference/dependent entities e.g. Company
    entity, Customer groups entity, Terms of payment entity etc. from
    F&O to CDS

-   Use data management framework to export data from F&O in csv format
    e.g. setup export project in data management to export customers
    from each companies (with DataAreaId field) in F&O. It's one-time
    manual process.

-   Use Azure Blob Storage to store the csv files for lookup,
    transformation etc. Upload your F&O customers csv file in Azure Blob
    Strorage.

-   Use Azure Data Factory
    ([ADF](https://docs.microsoft.com/en-us/azure/data-factory/introduction))
    to bootstrap data into CDS.

High-level flow
---------------
![ProcessFlow](/Dual-write/Bootstrapping/ProcessFlow.png)

Assumptions
-----------

-   Source data is in Dynamics 365 Finance & Operations app.

-   If an account exists in CDS and it doesn't exist in Finance &
    Operations app, that account will not be bootstrapped as part of this flow.

-   All account records in CE has a natural key (account number) that
    matches Finance and Operations natural key (CustomerAccount)

-   Records have 1-1 mapping across the apps.

-   All fields of account entity are not mapped in provided template. This template should be used as reference so that you can add more lookups and map remaining fields of account entity by your own.

Prerequisites
-------------

-   **Azure subscription** - You will require **contributor access** to
    an existing Azure subscription. If you don\'t have an Azure
    subscription, create a [free Azure
    account](https://azure.microsoft.com/en-us/free/) before you begin.

-   **Azure storage account** -  If you don\'t have a storage account,
    see [Create an Azure storage
    account](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal#create-a-storage-account)Â for
    steps to create one.

-   **Azure data factory** - Create an Azure Data Factory resource
    follow the steps to [create a Data
    factory](https://docs.microsoft.com/en-us/azure/data-factory/tutorial-copy-data-portal#create-a-data-factory)

-   **Dynamics 365 Finance & Operations -** Use Data management
    framework to export data in csv format (click
    [here](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/data-entities-data-packages)).
    In this template, example is used for exporting customers using
    'CustCustomerV3Entity'.

-   **Dynamics 365 CDS -** Dynamics 365 CDS administrator user
    credentials to bootstrap the data.

-   **Dual-Write -** Dual-write solutions installed, and Reference data
    is copied using initial-write.

Deployment steps
----------------

-   ### Setup Azure Storage account

> If you don\'t have a storage account, see [Create an Azure storage
> account](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal#create-a-storage-account) for
> steps to create one. Create one container namely 'ce-data' in your
> storage account (this container will be used to store all data files,
> you can change it if needed in your datasets/pipe-lines). Navigate to
> 'Access keys' and copy 'Connection string' as highlighted below (note
> it down as it's required at the time of importing Azure Data Factory
> template):

![bootstrapstorageaccount](/Dual-write/Bootstrapping/bootstrapstorageaccount.png)

-   ### Deploy Azure Data Factory Template

    1.  Note down Azure data factory name that you created.

    2.  Note down the Azure Storage account connection string.

    3.  Note down Dynamics 365 CDS instance service URI, Admin user name
        & password.

    4.  Here are all parameters you need

| Parameter name                                       | Description                       | Example                |
| :--------------------                                | :---------------------:           | --------------------:  |
|Factory Name                                          | Name of your data factory         |BootstrapCDSDataADF     |
|Bootstrap blob stroage account Linked Service_connection String                                        | Connection string of blob strorage       |As copied at the time of creating storage account   |
|Bootstrap Dynamics 365 Linked Service_service Uri                        | URI of Dynamics 365 CDS instance        |https://contosod365.crm4.dynamics.com              |
|Bootstrap Dynamics 365 Linked Service_properties_type Properties_username                                             | Dynamics 365 Admin user id          | <adminservice@contoso.onmicrosot.com> |  
|Bootstrap Dynamics 365 Linked Service_password                                            | Dynamics 365 Admin user's password                       | \*\*\*\*\*\*\*\* | 

5.  Download the [ARM template
    file](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Dual-write/Bootstrapping/arm_template.json) to
    your local directory.

6.  Click \[Template
    deployment\] <https://ms.portal.azure.com/#create/Microsoft.Template>

7.  Click Build your own template in the editor option.

8.  Click load file and locate the ARM template file you downloaded
    earlier and click Save.

9.  Provide required parameters and Review + create.

![CustomDeployment](/Dual-write/Bootstrapping/CustomDeployment.png)

10. After successful deployment, you will find below Pipelines, Datasets
    and Data flows.

![ADFPipeLine](/Dual-write/Bootstrapping/ADFPipeLine.png)

Execution
---------

-   **Dynamics 365 Finance & Operations --** Use Data management
    framework to export data in csv format (click
    [here](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/data-entities-data-packages)).
    In this template, example is used for exporting customers using
    'CustCustomerV3Entity'. Setup the 'CustCustomerV3Entity' and remove
    'FullPrimaryAddress' field map from the mapping. Add 'DataAreaId'
    field in the csv field. Rename the exported file as
    '01-CustomersV3Export-Customers V3.csv' and upload in Azure Storage
    account (ce-data container)

![F&OCustomerFileImage](/Dual-write/Bootstrapping/F&OCustomerFileImage.png)

- Download Dynamics 365 Finance & Operations [Sample customer file](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Dual-write/Bootstrapping/01-CustomersV3Export-Customers%20V3.csv)

-   Run 'BootstrapAccountsPipeline' from Azure Data Factory.
