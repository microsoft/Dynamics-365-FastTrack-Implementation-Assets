import * as React from "react";
import * as ReactDOM from "react-dom";

import { GetReportData } from "./DataProviders/GetReportData";
import { IInputs, IOutputs } from "./generated/ManifestTypes";
import { printDocument } from "./helpers/pdfPrinter";
import { SaveReportToastNotificationService } from "./helpers/SaveReportNotificationService";
import { ReportViewerProps } from "./models/ReportViewerModel";
import ReportViewer from "./ReportViewer";

export class ReportPreview implements ComponentFramework.StandardControl<IInputs, IOutputs> {

	private _container: HTMLDivElement;
	private _context: ComponentFramework.Context<IInputs>;
	private _saveReportToastNotificationService: SaveReportToastNotificationService;
	private bookingID: string;
	private workOrderID: string;
	private signature: string;
	private reportView: string;
	private _notifyOutputChanged: () => void;
	private props: ReportViewerProps;

	/**
	 * Used to initialize the control instance. Controls can kick off remote server calls and other initialization actions here.
	 * Data-set values are not initialized here, use updateView.
	 * @param context The entire property bag available to control via Context Object; It contains values as set up by the customizer mapped to property names defined in the manifest, as well as utility functions.
	 * @param notifyOutputChanged A callback method to alert the framework that the control has new outputs ready to be retrieved asynchronously.
	 * @param state A piece of data that persists in one session for a single user. Can be set at any point in a controls life cycle by calling 'setControlState' in the Mode interface.
	 * @param container If a control is marked control-type='standard', it will receive an empty div element within which it can render its content.
	 */
	public init(context: ComponentFramework.Context<IInputs>, notifyOutputChanged: () => void, state: ComponentFramework.Dictionary, container: HTMLDivElement) {
		// Add control initialization code
		this._container = container;
		this._context = context;
		this._notifyOutputChanged = notifyOutputChanged;

		this.bookingID = context.parameters?.BookingId?.formatted;
		this.workOrderID = context.parameters?.WorkOrder?.raw[0]?.id;
		this._saveReportToastNotificationService = new SaveReportToastNotificationService(this._context.resources, this.bookingID);
		this.signature = context.parameters?.Signature?.raw;
		this.reportView = context.parameters?.ReportView?.raw;
		if(this.reportView) {
			this.resetReportView();
		}

		// This is the information that is passed to the report component in SampleReport.tsx
		// You can add additional data here to consume it in the report.
		// If data needs to be fetched, add your own query and call it from getDataFetchPromises below.
		this.props = {
			booking: undefined,
			serviceInfo: undefined,
			products: [],
			servicetasks: [],
			services: [],
			signature: this.signature,
			context: context,
			isSpinnerVisible: false
		};

		if (!this.bookingID && !this.workOrderID) {
			this.renderReportViewer(this.props);
			return;
		}

		// displays the loading spinner, while data is being fetched
		this.setSpinnerVisibility(true);

		// start fetching the data
		const initDataRetrievalPromises = this.getDataFetchPromises();
		// remove the loading spinner once data fetches complete
		Promise.all(initDataRetrievalPromises).finally(() => this.setSpinnerVisibility(false));
		this.renderReportViewer(this.props);
	}

	/**
	 *  Retruns list of all the data fetches we need to render the report.
	 *  If you want to use other entity data, add a query in GetReportData, and pass that data to the report here.
	 * 	Entities being fetched MUST be enabled for offline for offline support.
	 */
	public getDataFetchPromises(): Promise<void>[] {
		const dataGetter = new GetReportData(this._context);

		// Just calling the data fetching functions we defined in GetReportData.ts

		const updateBookingData = dataGetter.getBookingData().then(
			(booking) => {
				this.props.booking = booking;
				this.renderReportViewer(this.props);
			}, (err) => {
				// eslint-disable-next-line no-console
				console.log("BOOKING DATA ERROR: ", err);
			}
		);

		const updateProductData = dataGetter.getProducts().then(
			(products) => {
				this.props.products = products;
				this.renderReportViewer(this.props);
			}, (err) => {
				// eslint-disable-next-line no-console
				console.log("PRODUCTS ERROR: ", err);
			}
		);

		const updateTasksData = dataGetter.getServiceTasks().then(
			(tasks) => {
				this.props.servicetasks = tasks;
				this.renderReportViewer(this.props);
			}, (err) => {
				// eslint-disable-next-line no-console
				console.log("TASKS ERROR: ", err);
			}
		);

		const updateServicesData = dataGetter.getServices().then(
			(services) => {
				this.props.services = services;
				this.renderReportViewer(this.props);
			}, (err) => {
				// eslint-disable-next-line no-console
				console.log("SERVICES ERROR: ", err);
			}
		);

		const updateServiceInfo = dataGetter.getServiceInfo().then(
			(serviceInfo) => {
				this.props.serviceInfo = serviceInfo;
				this.renderReportViewer(this.props);
			}, (err) => {
				// eslint-disable-next-line no-console
				console.log("SERVICE INFO ERROR: ", err);
			}
		);

		return [updateBookingData, updateProductData, updateTasksData, updateServiceInfo, updateServicesData];
	}

	/**
	 * Renders the report with the new data passed through the props parameter.
	 * @param props props containing all of the data needed by the report.
	 * 				Modify the ReportViewerModel file to extend the data types supported.
	 */
	public renderReportViewer(props: ReportViewerProps): void {
		//Render the control
		const reportViewer = React.createElement(
			ReportViewer, props
		);

		ReactDOM.render(
			reportViewer,
			this._container
		);
	}

	/**
	 * Called when any value in the property bag has changed. This includes field values, data-sets, global values such as container height and width, offline status, control metadata values such as label, visible, etc.
	 * @param context The entire property bag available to control via Context Object; It contains values as set up by the customizer mapped to names defined in the manifest, as well as utility functions
	 */
	public updateView(context: ComponentFramework.Context<IInputs>): void {

		if (context.parameters?.Signature?.raw !== this.signature) {
			this.signature = context.parameters?.Signature?.raw;
			this.props.signature = this.signature;
			this.renderReportViewer(this.props);
		}

		const newEvent = context.parameters?.ReportView?.raw;
		if (newEvent && newEvent !== this.reportView && newEvent !== "") {
			if (this.bookingID) {
				printDocument(this.onSave)();
			}
		}
		this.reportView = newEvent;
	}

	public resetReportView(){
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		const xrmProvider = (window as any);
		xrmProvider?.Xrm?.Page?.getAttribute("o25fs_reportview").setValue("");
		xrmProvider?.Xrm?.Page?.data?.entity.save();
	}

	/**
	 * Callback to save report to timeline. This is called from pdfPrinter.
	 * @param data The pdf data as a base64 string
	 */
	private onSave = async (data: string) => {
		this.setSpinnerVisibility(true);
		const binaryIndex = data.indexOf("base64");
		const docBinary = data.substring(binaryIndex + 7);  // This is the pdf data in binary

		// define the data to create new annotation; This will show up on the booking's timeline
		const annotationCreateData = {
			subject: "Service Report",
			notetext: "",
			documentbody: docBinary,
			mimetype: "application/pdf",
			filename: "report.pdf",
			"objectid_bookableresourcebooking@odata.bind": `/bookableresourcebookings(${this.bookingID})`,
		};

		// create annotation record
		try {
			await this._context.webAPI.createRecord("annotation", annotationCreateData);
			await this._saveReportToastNotificationService.AddNotificationAsync();
		} catch (err) {
			// eslint-disable-next-line no-console
			console.log("Error saving report to timeline: ", err);
		} finally {
			this.setSpinnerVisibility(false);
		}
		this.resetReportView();
	};

	/**
	 * It is called by the framework prior to a control receiving new data.
	 * @returns an object based on nomenclature defined in manifest, expecting object[s] for property marked as “bound” or “output”
	 */
	public getOutputs(): IOutputs {
		return { ReportView: "" };
	}

	/**
	 * Called when the control is to be removed from the DOM tree. Controls should use this call for cleanup.
	 * i.e. cancelling any pending remote calls, removing listeners, etc.
	 */
	public destroy(): void {
		// Add code to cleanup control if necessary
	}

	/**
	 * Sets the loading spinner on/off.
	 * @param isVisible boolean determines spinner visibility
	 */
	private setSpinnerVisibility = (isVisible: boolean): void => {
		if (this.props.isSpinnerVisible === isVisible) {
			return;
		}

		this.props.isSpinnerVisible = isVisible;
		this.renderReportViewer(this.props);
	};
}
