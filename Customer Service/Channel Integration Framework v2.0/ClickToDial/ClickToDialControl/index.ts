import {IInputs, IOutputs} from "./generated/ManifestTypes";
import * as React from 'react';
import * as ReactDOM from 'react-dom';
import { PhoneNumberInputControl } from './Components/PhoneNumberInputControl';
import { PhoneNumberValidationInputControl } from './Components/PhoneNumberInputValidationControl'
import { strict } from "assert";

export class ClickToDialControl implements ComponentFramework.StandardControl<IInputs, IOutputs> {

    private container: HTMLDivElement;
	private notifyOutputChanged: () => void;
	private phoneValue?: string;
    private showButton: boolean;

    /**
     * Empty constructor.
     */
    constructor()
    {

    }

    /**
     * Used to initialize the control instance. Controls can kick off remote server calls and other initialization actions here.
     * Data-set values are not initialized here, use updateView.
     * @param context The entire property bag available to control via Context Object; It contains values as set up by the customizer mapped to property names defined in the manifest, as well as utility functions.
     * @param notifyOutputChanged A callback method to alert the framework that the control has new outputs ready to be retrieved asynchronously.
     * @param state A piece of data that persists in one session for a single user. Can be set at any point in a controls life cycle by calling 'setControlState' in the Mode interface.
     * @param container If a control is marked control-type='standard', it will receive an empty div element within which it can render its content.
     */
    public async init(context: ComponentFramework.Context<IInputs>, notifyOutputChanged: () => void, state: ComponentFramework.Dictionary, container:HTMLDivElement)
    {
        // Add control initialization code
        this.container = container;
		this.notifyOutputChanged = notifyOutputChanged;
        this.phoneValue = context.parameters.phoneNumber.raw === null ? '' : context.parameters.phoneNumber.raw;
        this.showButton = false;
        this.showButton = context.parameters.showButton.raw ? context.parameters.showButton.raw === "Yes": false;
        this.renderControl(context);
    }


    /**
     * Called when any value in the property bag has changed. This includes field values, data-sets, global values such as container height and width, offline status, control metadata values such as label, visible, etc.
     * @param context The entire property bag available to control via Context Object; It contains values as set up by the customizer mapped to names defined in the manifest, as well as utility functions
     */
    public updateView(context: ComponentFramework.Context<IInputs>): void
    {       
        this.renderControl(context);
    }

    private formatPhoneNumber(phone: string): string {
		if (/^\d/.test(phone)) {
			return `+${phone}`;
		}

		return phone;
	}

	private preparePhoneInput(valueFromCrm: ComponentFramework.PropertyTypes.StringProperty): string | undefined {
		if (!valueFromCrm.raw) return '';

		this.phoneValue = this.formatPhoneNumber(valueFromCrm.raw);

		return this.phoneValue;
	}

	private prepareOutputPhoneNumber(newValue?: string): string {
		return !newValue ? '' : newValue;
	}

	private isPhoneEmpty(phone: string): string {
		const onlyDigits = phone.replace(/[_()-]/g, '').trim();

		if (!onlyDigits) return '';

		return phone;
	}

	private renderControl(context: ComponentFramework.Context<IInputs>) {

		context.parameters.validatePhoneNumber.raw === "Yes" ?
			ReactDOM.render(React.createElement(PhoneNumberValidationInputControl, {
				phone: this.preparePhoneInput(context.parameters.phoneNumber),
				disabled: context.mode.isControlDisabled,
				onValueChanged: (newValue?: string) => {
					this.phoneValue = this.isPhoneEmpty(this.prepareOutputPhoneNumber(newValue));
					this.notifyOutputChanged();
				},
				onCallClicked: async () => {
					const currentRecord = {
						id: (<any>context.mode).contextInfo.entityId,
						entityType: (<any>context.mode).contextInfo.entityTypeName,
						name: (<any>context.mode).contextInfo.entityRecordName
					};

					////let serviceLayout = await FetchServiceLayout(context);

					try {

						let phone = this.phoneValue!.replace(/[_()-]/g, '').trim();
						
						let eventInput = {
							"value": phone,
							"name": "mobilephone",
							"format": "Text",
							"entityLogicalName": "contact",
							"entityId": currentRecord.id
						};

						var event = new CustomEvent("CIClickToAct", { detail: eventInput });

						//@ts-ignore
						window.top.dispatchEvent(event);
					} catch(error) {
						context.navigation.openErrorDialog({ message: "Something went wrong. Please contact administrator." });
					}
				},				
				showButton: context.parameters.showButton.raw ? context.parameters.showButton.raw === "Yes" : false				
			}), this.container)
			: ReactDOM.render(React.createElement(PhoneNumberInputControl, {
				phone: this.preparePhoneInput(context.parameters.phoneNumber),
				disabled: context.mode.isControlDisabled,
				formatPhoneNumber: this.formatPhoneNumber,
				onValueChanged: (newValue?: string) => {
					this.phoneValue = this.isPhoneEmpty(this.prepareOutputPhoneNumber(newValue));
					this.notifyOutputChanged();
				},							
				onCallClicked: async () => {
					const currentRecord = {
						id: (<any>context.mode).contextInfo.entityId,
						entityType: (<any>context.mode).contextInfo.entityTypeName,
						name: (<any>context.mode).contextInfo.entityRecordName
					};

					////let serviceLayout = await FetchServiceLayout(context);

					try {

						let phone = this.phoneValue!.replace(/[_()-]/g, '').trim();
						
						let eventInput = {
							"value": phone,
							"name": "mobilephone",
							"format": "Text",
							"entityLogicalName": "contact",
							"entityId": currentRecord.id
						};

						var event = new CustomEvent("CIClickToAct", { detail: eventInput });

						//@ts-ignore
						window.top.dispatchEvent(event);
					} catch(error) {
						context.navigation.openErrorDialog({ message: "Something went wrong. Please contact administrator." });
					}
				},				
				showButton: context.parameters.showButton.raw ? context.parameters.showButton.raw === "Yes" : false				
			}), this.container)
	}

	public getOutputs(): IOutputs {
		this.phoneValue = this.formatPhoneNumber(this.phoneValue || '');

		return {
			phoneNumber: this.phoneValue			
		};
	}

	public destroy(): void {
		ReactDOM.unmountComponentAtNode(this.container);
	}

}