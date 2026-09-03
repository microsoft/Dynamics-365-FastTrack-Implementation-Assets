# Sales Order PDF Viewer

A lightweight Microsoft Dataverse overlay that adds an embedded PDF and image viewer to the Sales Order Agent experience.

The solution displays files stored in the `aipod_inputdocument` file column directly from the **Staging Document Quick View Form**. It uses same-origin Dataverse web resources and PDF.js, so users can preview documents without downloading them or navigating away from the sales order.

## Solution details

| Item | Value |
| --- | --- |
| Solution unique name | `SalesOrderPdfViewer` |
| Version | `1.0.0.0` |
| Publisher | AIPOD |
| Publisher prefix | `aipod` |
| Deployment model | Managed overlay |
| Recommended package | `SalesOrderPdfViewer_1_0_0_0_managed.zip` |
| PDF.js version | `5.4.149` |

## Features

- Displays Dataverse PDF and image attachments inside the model-driven app.
- Provides Previous, Next, Zoom In, Zoom Out, Fit, Rotate, and Download controls.
- Uses the current user's Dataverse permissions when retrieving files.
- Preserves the existing Sales Order Agent data model.
- Contains no Dataverse column definitions, cloud flows, connection references, environment variables, or model-driven apps.
- Supports controlled deployment to environments with additional tables, columns, and form customizations.

## How it works

```text
Sales Order Header
        |
        v
Staging Document Quick View Form
        |
        v
aipod_previewFile
        |
        v
aipod_pdfViewer.html
        |
        +--> aipod_pdf.mjs
        +--> aipod_pdf.worker.mjs
        |
        v
Dataverse file-column API
```

The viewer retrieves the selected document through the Dataverse Web API:

```text
/api/data/v9.2/aipod_stagingdocuments(<record-id>)/aipod_inputdocument/$value
```

## Package contents

| Component | Purpose |
| --- | --- |
| Staging Document Quick View Form | Hosts `IFRAME_previewdocument` and invokes the viewer script. |
| `aipod_previewFile` | Builds the viewer URL from the current staging document record. |
| `aipod_pdfViewer.html` | Downloads and displays the Dataverse file in a same-origin viewer. |
| `aipod_pdf.mjs` | PDF.js 5.4.149 runtime. |
| `aipod_pdf.worker.mjs` | Matching PDF.js 5.4.149 worker. |

The `aipod_stagingdocument` table appears in the solution manifest only as a container for the selected form component. The package includes **zero table attributes** and does not add, update, or delete Dataverse columns.

## Prerequisites

Install the Sales Order Agent base solution before importing this overlay. The target environment must already contain:

- Table: `aipod_stagingdocument`
- File column: `aipod_inputdocument`
- Text columns: `aipod_name` and `aipod_contenttype`
- Existing form columns: `aipod_documenttype`, `aipod_extracteddata`, and `ownerid`
- Existing web resource: `aipod_document`
- Staging Document Quick View Form ID: `dfb7596a-8699-f011-bbd3-000d3a371cd7`

If a required component is missing, install or upgrade the base Sales Order Agent solution. Do not bypass dependency warnings by adding unrelated base components to this overlay.

## Deployment guidance

### Standard target environment

Use this path when the target has not changed the packaged **Staging Document Quick View Form**:

1. Import `SalesOrderPdfViewer_1_0_0_0_managed.zip`.
2. Resolve any missing base-solution dependencies.
3. Complete the import.
4. Publish all customizations.
5. Hard-refresh the browser with `Ctrl+Shift+R`.

Additional columns on `aipod_stagingdocument`, or columns added to other forms, do not conflict with this package.

### Customized Quick View form

Use a merge process when the target changed the same **Staging Document Quick View Form**:

1. Back up the target form, web resources, and current solution layers.
2. Reproduce the target layers in an integration or development environment.
3. Import the unmanaged package into that non-production environment only.
4. Preserve all target-only sections, controls, columns, libraries, and event handlers.
5. Confirm hidden controls for `aipod_name` and `aipod_contenttype` remain on the form.
6. Add or retain `IFRAME_previewdocument`.
7. Add `aipod_previewFile` as a form library.
8. Configure Form On Load to call `onLoadForm` with **Pass execution context** enabled.
9. Test the merged form.
10. Export the tested changes as a new managed solution with an increased version.

Do not import the unmanaged package directly into production.

### Managed layer is masked

An unmanaged customization on the same form or `aipod_previewFile` can remain the active top layer and hide the managed viewer changes.

Back up the active customization, inspect solution layers, and merge the viewer configuration into the active unmanaged form. Remove an unmanaged layer only after its changes are safely captured and the removal has been approved and tested outside production.

## Import with Power Platform CLI

```powershell
pac auth create --environment https://<target>.crm.dynamics.com
pac auth select --index <target-profile-index>

pac solution import `
  --environment https://<target>.crm.dynamics.com `
  --path .\SalesOrderPdfViewer_1_0_0_0_managed.zip `
  --publish-changes `
  --async `
  --max-async-wait-time 30
```

Do not use `--force-overwrite` for the managed distribution package. Do not use `--skip-dependency-check` unless the solution owner or Microsoft Support has confirmed that the reported dependency is irrelevant.

## Post-import checks

Confirm that:

- `IFRAME_previewdocument` exists on the Staging Document Quick View Form, is initially hidden, and has sufficient height.
- `aipod_previewFile` is registered as a form library.
- Form On Load calls `onLoadForm` and passes the execution context.
- The Sales Order Header form references the packaged Quick View form.
- Target-specific columns and controls remain in their expected locations.

Publish the form and model-driven app if either was changed during a merge.

## Functional validation

1. Open a Sales Order Header linked to a Staging Document containing a PDF in `aipod_inputdocument`.
2. Confirm that the viewer toolbar and page canvas appear.
3. Test Previous, Next, Zoom In, Zoom Out, Fit, Rotate, and Download.
4. Confirm that the displayed file name matches `aipod_name`.
5. Test a multi-page PDF and an image attachment.
6. Confirm that target-added columns remain available on their configured forms.
7. Repeat the test with a non-administrator business user.

Expected browser requests include:

```text
/WebResources/aipod_pdfViewer.html
/WebResources/aipod_pdf.mjs
/WebResources/aipod_pdf.worker.mjs
/api/data/v9.2/aipod_stagingdocuments(<record-id>)/aipod_inputdocument/$value
```

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| Import reports missing Staging Document components | Install or upgrade the Sales Order Agent base solution. |
| Viewer does not appear after a successful import | Inspect solution layers for an unmanaged form or script layer masking the managed change. |
| Target-added controls disappeared | Restore the backed-up form and merge the definitions in an integration environment. |
| Old or blocked-content viewer remains | Hard-refresh the browser and verify that the active `aipod_previewFile` layer references `aipod_pdfViewer.html`. |
| Viewer reports missing parameters | Confirm that hidden `aipod_name` and `aipod_contenttype` controls are present and populated. |
| File request returns HTTP 401 or 403 | Grant the user read access to the staging document row and file column. |
| File request returns HTTP 404 | Verify the table, record ID, and `aipod_inputdocument` logical name. |
| PDF canvas is blank | Confirm both PDF.js resources are version 5.4.149 and inspect the browser console. |

## Rollback

1. Export the failed state for investigation.
2. Uninstall `SalesOrderPdfViewer` if no other solution depends on it.
3. Publish all customizations and hard-refresh the app.
4. If a form was modified during a merge, restore the approved backup or previous form definition.
5. Verify that target-specific controls and columns are restored.

Removing the managed overlay removes its managed layers and viewer web resources. It does not delete target-added Dataverse columns because the package contains no column components.

## Package integrity

Verify the managed package before distribution:

```powershell
Get-FileHash .\SalesOrderPdfViewer_1_0_0_0_managed.zip -Algorithm SHA256
```

Expected SHA-256:

```text
779FD897CC78151E0C87DB695573F7D8DB081EA72F4654F96D2F10AC100D8363
```

## Distribution files

- `SalesOrderPdfViewer_1_0_0_0_managed.zip` - production distribution package
- `SalesOrderPdfViewer_1_0_0_0_unmanaged.zip` - development, inspection, and emergency recovery only
- `SalesOrderPdfViewer-Distribution-Implementation-Guide.docx` - detailed deployment and merge guide

## Microsoft documentation

- [Solutions overview](https://learn.microsoft.com/power-platform/alm/solution-concepts-alm)
- [Solution layers](https://learn.microsoft.com/power-apps/maker/data-platform/solution-layers)
- [Import, update, and export solutions](https://learn.microsoft.com/power-apps/maker/data-platform/import-update-export-solutions)
- [Use file column data](https://learn.microsoft.com/power-apps/developer/data-platform/file-column-data)

