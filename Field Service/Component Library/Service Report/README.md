# Introduction 
Adds mobile reporting support for bookings.  
Includes:
- PCF control to render preview
- Report generation
- Relevant forms and ribbon elements

# Getting Started
## Installation process
To install the reporting solution:
1. Download [Reporting Solution](http://link.com).
2. Download sample [Reporting PCF Control](http://link.com) source code.
3. Import the reporting Solution into your environment. This will install a reporting form, ribbon command, and includes a sample report so you can execute functionality within your environment,
4. After importing the reporting solution, open your app module in App Designer and enable the Reporting form for the Bookable Resource Booking entity. This will enable the sample report template, the next steps detail how to create your own reports.
5. Leverage your favorite IDE to edit the sample Reporting PCF control. Modify this control to change layout, add additional branding, updated data, or other updates necessary to meet your reporting requirements.
6. Import the modified PCF control back into your environment, replacing the sample report. Refer to the 'Extending the control' section below for more details. [Steps to import a PCF control](https://docs.microsoft.com/en-us/powerapps/developer/component-framework/import-custom-controls)
7. Update customizations to point to your new PCF template by going to Customize the System > Bookable Resource Booking > Forms > Reporting > ReportView. Under Controls, search for and add your newly named report, which should be enabled for web, phone, and tablet.


##	Software dependencies
Download the Powerapps CLI tool and browse documentation here: 

https://docs.microsoft.com/en-us/powerapps/developer/component-framework/create-custom-controls-using-pcf

You will also need to have Node.js and NPM installed.

#	Extending the control
The first step is to change the name of the PCF control, this can be done by changing the name from ReportPreview to anything else in these files:
- ControlManifest
- index.ts
- css/viewer.css

To change the report visuals, you will likely only need to modify these two files:
- ReportPreview/SampleReport.tsx
- ReportPreview/styles.ts

SampleReport.tsx contains the code that renders the report view. This is what is displayed on the reporting form and is what gets converted to a PDF when the report is saved.

You can add CSS to the report PDF by modifying styles.ts. If you want to change how the report is rendered in the app/browser without affecting the final PDF that is generated, you can make CSS changes to ReportPreview/viewer.css.

To view your changes locally, simply run npm install and npm start in the PCF control's root folder.

To build the control and deploy it into an org, increment the version number in ControlManifest.Input.xml, build, and import the control. Additional details can be found in the PCF documentation available online. [Steps to import a PCF control](https://docs.microsoft.com/en-us/powerapps/developer/component-framework/import-custom-controls)

## Adding data from other entities to the report

You can also fetch any other data you want and add it to the report. Whatever entities you want to use must also be enabled for offline.

The general steps for adding custom data to the report:

1. Define your new data type (ReportPreview/models/ReportViewerModel.ts)
2. Add custom query to fetch data (ReportPreview/DataProviders/GetReportData.ts)
3. Pass the data to the report (index.ts)
4. Display and style the data on the report (ReportPreview/SampleReport/SampleReport.tsx)

---
For example, if you would like to add some data that is available on the Account entity, you can start by defining your data type in ReportPreview/models/ReportViewerModel.ts:

```
export class Account {
    name: string;
    email: string;
    phone: string;
    // add any other fields you would like to include
}
```

Extend the report properties by adding an entry to ReportViewerProps:
```
export interface ReportViewerProps {
    account: Account;  <--- (add your new data type here) 
    booking: Booking;
    serviceInfo: ServiceInfo;
    ...
}
```
---
Now, you can add a query in the GetReportData.ts file to fetch this data. There are a number of examples already there to refer to. There is also tons of documentation online on fetching data using the web API: [Reference](https://docs.microsoft.com/en-us/powerapps/developer/model-driven-apps/clientapi/reference/xrm-webapi)

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

Run 'npm start' to see how the report looks or build and import it into your org. There are comments throughout the files for additional instructions that allow you to do even more like download and use additional font types, add images, etc...

## Adding Custom Font
In some cases, we need use a custom font for the pdf or to handle special characters for certain languages. We can do that by adding a custom font for jsPDF.

Edit the ReportPreview\helpers\pdfPrinter.js
```
		//Use an online tool to create a base64 content of a custom font file
		const customFont = 'BASE64 CONTENT';  

		// Adding a custom font
		pdf.addFileToVFS("customFont.ttf", customFont);
		pdf.addFont("customFont.ttf", "customFontName", "normal");
		pdf.setFont("customFontName", "normal");

		// Note: 'customFontName' should match the font used on the generated HTML report (see reportPreview/styles.ts)
```

## Navigating to Timeline
After a report is saved, the app generates a notification that will navigate users to the timeline tab. The user will be navigated to the tab named "fstab_Timeline", this can be changed by modifying common/Constants.ts in the PCF control or by changing the name of you tab in the org's customizations.