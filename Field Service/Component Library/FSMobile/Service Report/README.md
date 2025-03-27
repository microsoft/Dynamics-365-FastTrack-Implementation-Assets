# Introduction 
This open-source project allows Field Service technicians to generate service reports that summarize their completed tasks. These reports can include details such as tasks performed, and products or parts used during the service. Service reports can be provided to customers in PDF format.
The service report is integrated into Field Service as a Microsoft Power Apps component framework (PCF) control. Administrators or developers can download and import the reporting package as a solution in Power Apps. The sample report can be customized by updating branding, logos, and adding additional data fields using the supplied source code and templates.

Includes:

	- Custom PCF Control
	- Customizations to Bookable Resource Booking table including 
		- New form
		- Ribbon customizations 
		- New field
	- TypeScript files, etc.

# Getting Started

## Installation process

> Note: If you have installed a previous version of the managed solution from Microsoft Learn, it is recommended that you uninstall it before installing this new solution to avoid any conflicts.
### To import and try out the reporting solution as-is in a sandbox environment:
1. Download [ReportingSolution_managed.zip](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Field%20Service/Component%20Library/FSMobile/Service%20Report/solutions/ReportingSolution_managed.zip).
2. Import the reporting solution into your environment.
3. After importing the reporting solution, open your app module in App Designer and enable the "Reporting" form for the "Bookable Resource Booking" table.


### To customize the reporting solution before installation in a sandbox environment:
1. Leverage your favorite IDE to edit the sample Reporting PCF control. Modify this control to change the layout, add additional branding, updated data, or other updates necessary to meet your reporting requirements. 
Read the [Extending the control](#extending-the-control) section below for more details.
2. After modifications are completed, simply run `msbuild /t:build /restore` command from the control's root folder. This will ensure that all necessary packages are downloaded and finally build the projects to generate both unmanaged and managed solutions for import under the "\solutions\FieldServiceReporting\Solution\bin\Debug" directory.
3. Import the reporting solution into your development environment.
4. After importing the reporting solution, open your app module in App Designer and enable the "Reporting" form for the "Bookable Resource Booking" table.
5. Test and follow your organization's application lifecycle management practices to import the solution to non-development environment(s).


# Extending the control

## Prerequisites

This solution uses Microsoft Power Apps component framework (PCF) control, you need install the following components:

- [Visual Studio Code (VSCode)](https://code.visualstudio.com/Download) (Ensure the Add to PATH option is select)
- [node.js](https://nodejs.org/en/download/) (LTS version is recommended)
- [Microsoft Power Platform CLI](https://learn.microsoft.com/en-us/powerapps/developer/data-platform/powerapps-cli#install-power-apps-cli) (Use the Visual Studio Code extension)

For additional details on how to create and deploy code components using Microsoft Power Platform CLI, please read the how-to guides: [Create and build a code component - Power Apps | Microsoft Learn](https://learn.microsoft.com/en-us/power-apps/developer/component-framework/create-custom-controls-using-pcf)


## Code Customizations

### Basics
The first step is to change the name of the PCF control, this can be done by changing the name from ReportPreview to anything else in these files:
- `ControlManifest.Input.xml`
- `index.ts`
- `css/viewer.css`

To change the report visuals, you will likely only need to modify these two files:
- `ReportPreview/SampleReport.tsx`
- `ReportPreview/styles.ts`

`SampleReport.tsx` contains the code that renders the report view. This is what is displayed on the reporting form and is what gets converted to a PDF when the report is saved.

You can add CSS to the report PDF by modifying `styles.ts`. If you want to change how the report is rendered in the app/browser without affecting the final PDF that is generated, you can make CSS changes to `ReportPreview/viewer.css`.

To view your changes locally, simply run `npm install` and `npm start` in the PCF control's root folder.

To build the control and deploy it into an org, increment the version number in `ControlManifest.Input.xml`, build, and import the control. 

### Adding data from other entities to the report

You can also fetch any other data you want and add it to the report. Whatever entities you want to use must also be enabled for offline.

The general steps for adding custom data to the report:

1. Define your new data type (`ReportPreview/models/ReportViewerModel.ts`)
2. Add custom query to fetch data (`ReportPreview/DataProviders/GetReportData.ts`)
3. Pass the data to the report (`index.ts`)
4. Display and style the data on the report (`ReportPreview/SampleReport/SampleReport.tsx`)

---
For example, if you would like to add some data that is available on the Account entity, you can start by defining your data type in `ReportPreview/models/ReportViewerModel.ts`:

```
export class Account {
    name: string;
    email: string;
    phone: string;
    // add any other fields you would like to include
}
```

Extend the report properties by adding an entry to `ReportViewerProps`:
```
export interface ReportViewerProps {
    account: Account;  <--- (add your new data type here) 
    booking: Booking;
    serviceInfo: ServiceInfo;
    ...
}
```
---
Now, you can add a query in the `GetReportData.ts` file to fetch this data. There are a number of examples already there to refer to. There are also tons of documentation online on fetching data using the web API: [Reference](https://docs.microsoft.com/en-us/powerapps/developer/model-driven-apps/clientapi/reference/xrm-webapi)

You can skip this step if you just want to see how the report will look. Just skip to the next step and run npm start to visualize the report.

---

Now, pass the data to the report by calling your query in index.ts:
```
public getDataFetchPromises(): Promise<any>[] {
		let dataGetter = new GetReportData(this._context);

		const updateAccountData = dataGetter.getAccountData().then(
			(account) => {
				this.props.account = account;                               <--- Trigger the data fetch
				this.renderReportViewer(this.props);
			}}
		);

		const updateBookingData = dataGetter.getBookingData().then(
			(booking) => {
				this.props.booking = booking;
				this.renderReportViewer(this.props);
			}}
		);
		return [updateAccountData, updateBookingData ... ]
}
```

Make sure you also add a default value for the account to the props:
```
this.props = {
    account: undefined,
    booking: undefined,
    products: [],
    ...
}
```
---
Now the data should be available in SampleReport.tsx for you to display. You can display it in any way you see fit, but can also use some of the helper functions available:
```
<FieldInfo name="Account name" value={account?.name}></FieldInfo>
```

Run `npm start` to see how the report looks or build and import it into your org. There are comments throughout the files for additional instructions that allow you to do even more like download and use additional font types, add images, etc...

### Adding Custom Font
In some cases, we need to use a custom font for the pdf or to handle special characters for certain languages. We can do that by adding a custom font for jsPDF.

Edit the `ReportPreview\helpers\pdfPrinter.js`
```
		//Use an online tool to create a base64 content of a custom font file
		const customFont = 'BASE64 CONTENT';  

		// Adding a custom font
		pdf.addFileToVFS("customFont.ttf", customFont);
		pdf.addFont("customFont.ttf", "customFontName", "normal");
		pdf.setFont("customFontName", "normal");

		// Note: 'customFontName' should match the font used on the generated HTML report (see reportPreview/styles.ts)
```

### Navigating to Timeline
After a report is saved, the app generates a notification that will navigate users to the timeline tab. The user will be navigated to the tab named `fstab_Timeline`, this can be changed by modifying common/Constants.ts in the PCF control or by changing the name of your tab in the org's customizations.




# Disclaimer
The source code and managed solution provided herein is supplied "as-is" without any warranties or guarantees, express or implied. It is the sole responsibility of the user to thoroughly review, customize, test, and validate the code to ensure its suitability and functionality within their specific sandbox environment. Microsoft or the author of the code shall not be held liable for any issues, damages, or losses arising from the use or implementation of the code. Furthermore, Microsoft will not provide support for any issues or inquiries related to this code and its associated controls.
