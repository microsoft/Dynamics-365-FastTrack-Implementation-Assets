# Update the assistant instructions

Use this procedure to change the assistant's tone, rules, or task guidance without changing the POS extension.

## Before you start

- Ask for **Storage Blob Data Contributor** access to the deployed storage account.
- Keep a backup of the package's `assistant-instructions.txt` file.
- Use the exact file name `assistant-instructions.txt` and save it as UTF-8 plain text.

## Update the file

1. Open the package's `assistant-instructions.txt` file in a text editor.
2. Update the instructions and save the file.
3. Sign in to the [Azure portal](https://portal.azure.com/).
4. Open the deployment resource group and select the storage account. Its name normally ends in `stg`.
5. Select **Data storage** > **Containers** > **assistant-config**.
6. Select **Upload** and choose the updated `assistant-instructions.txt` file from the package.
7. Enable **Overwrite if files already exist**, and then select **Upload**.
8. Wait up to 15 minutes for the API Management cache to refresh.
9. Test a few representative questions in POS.

This upload replaces the existing blob. It does not create another instructions file.

Keep the package file as the source of truth. `deploy.ps1` uploads that same file on every deployment.

## Verify

- The blob shows a new **Last modified** time.
- Existing POS requests continue to succeed.
- The assistant follows the updated guidance after the cache refresh.

To roll back, replace the package file with the backup and upload it again with overwrite enabled.

## Microsoft guidance

- [Upload, download, and list blobs with the Azure portal](https://learn.microsoft.com/azure/storage/blobs/storage-quickstart-blobs-portal)
- [Assign an Azure role for access to blob data](https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access)

[Back to guide index](README.md)
