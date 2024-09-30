# Schedule Board Settings Management

## Overview

The Schedule Board Settings Management is a custom Power Apps component framework (PCF) control designed to enhance the management of Schedule Board settings in Dynamics 365 Field Service. This control provides a user-friendly interface for viewing, copying, deleting, and enabling/disabling Schedule Board settings.

## Features

- **View Schedule Board Settings**: Display a dropdown list of all available Schedule Board settings.
- **Copy Settings**: Create a copy of an existing Schedule Board setting with a new name. This provides a quick way to achieve Save As functionality for Schedule Board tabs.
- **Delete Settings**: Remove a selected Schedule Board setting (except for system-protected boards - see the Limitations section).
- **Enable/Disable Settings**: Toggle the active state of a Schedule Board setting. Disabled records will not show as tabs in the Schedule Board.
- **Detailed View**: Show comprehensive details of each Schedule Board setting, including JSON configurations.
- **Open in New Tab**: Ability to open the selected Schedule Board setting in a new browser tab for sharing a board with other users/teams.
- **Refresh**: Reload the list of Schedule Board settings to reflect recent changes.

![](images/image1.gif)

## Technical Details

- Built using TypeScript and React
- Utilizes the Fluent UI React components for a consistent look and feel
- Integrates with Dynamics 365 Web API for data operations
- Implements error handling and user feedback mechanisms

## Usage

1. Select a Schedule Board setting from the dropdown.
2. View detailed information about the selected setting.
3. Use the provided buttons to copy, delete, or enable/disable the setting.
4. Open the setting in a new tab for more detailed editing/sharing if needed.
5. Refresh the list to see any changes made outside of the control.

## Installation

### Option 1
1. Build the solution using the Power Apps CLI.
2. Import the solution into your Dynamics 365 environment.
3. Add the control to a model-driven app via the Navigation link page type, with a URL field reference like so: /main.aspx?pagetype=control&controlName=o25fs_MicrosoftOptimize25.ScheduleBoardManagement&forceUCI=1. 

#### Note: This is a full-page control and is not intended to be embedded into a form.

### Option 2
Alternatively, the included unmanaged solution named FieldServiceExtensionsOptimize25_1_3_0_0 in the Solutions folder will install the control and a barebones model-driven app named Field Service Extentions, which has two pages. The Board Management page is a URL reference to the control and the Schedule Board page is a link to the Schedule Board in the same way the board is referenced in the OOB Field Service model-driven app. There are 4 components in this solution: the model-driven app, the model-driven app's sitemap, the control, and an image for the model-driven app for the app picker.

Use this option for the fastest way to try this component out.

#### Note: The Field Service Extensions model-driven app has security scoped to System Customizer and System Administrator security roles by default.

## Limitations

- System-protected Schedule Board settings (e.g., "Default", "Initial public view", "Resource utilization view") cannot be deleted or disabled.
- The control requires appropriate user permissions to perform operations on Schedule Board settings.

## Third-Party Libraries

This project uses the following third-party libraries:

- **highlight.js**: Used for syntax highlighting of JSON content.
  - License: BSD 3-Clause License
  - Website: https://highlightjs.org/
  - License details: https://github.com/highlightjs/highlight.js/blob/main/LICENSE

## Support

This control source code and unmanaged solution are provided as-is. Bugs, feature addition/modification requests, and other changes are the responsibility of the end-user.
You accept any responsibility for issues you may cause in modifying/copying Schedule Board Settings via this component. Always thoroughly test components in a non-prod environment.