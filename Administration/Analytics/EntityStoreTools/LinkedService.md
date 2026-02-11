# Linked Service - Azure Synapse Studio

Linked Services provide the ability to pre-configure connections to various Azure components (Storage/Compute). Different modes of authentication can be specified during setup.
Visit [Microsoft Docs](https://docs.microsoft.com/en-us/azure/data-factory/concepts-linked-services) for more information.

### Note: In order to run the Entity Store Notebook you must setup a Linked Service to your KeyVault that contains secrets with ConnectionStrings to ADLS and SQL pools.

1. Navigate to Synapse Studio -> Manage -> Linked Services
2. Click on +New button.
3. Search of Key Vault and then click continue.
4. The image below indicates the required inputs.
    - Name for the Linked Service.
    - Azure key vault selection method: Enter Manually.
    - Base URL: Enter the Vault URI of the KeyVault.
    - Test connection to verify if the connection works.
    - Create.

![Images](.wiki/images/LinkedServiceIMG.png)

## Key Vault
1. Create two separate secrets for ADLS and SQL pool Connection Strings.
2. Add Access Policy for your Synapse Workspace, within the Key Vault.
