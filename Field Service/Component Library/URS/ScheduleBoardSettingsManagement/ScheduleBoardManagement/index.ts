// Import the necessary libraries and types
import { IInputs, IOutputs } from "./generated/ManifestTypes";
import { InfoLabel, Tooltip, FluentProvider, webLightTheme } from "@fluentui/react-components";
import type { TooltipProps } from "@fluentui/react-components";

// Import React and ReactDOM for rendering UI components
import * as React from 'react';
import * as ReactDOM from 'react-dom/client';

// Define the interface for the Schedule Board Setting
interface ScheduleBoardSetting {
    msdyn_scheduleboardsettingid: string;
    msdyn_tabname: string;
    [key: string]: string | number | boolean | undefined;
}

interface WebApiError extends Error {
    message: string;
}

// Define the class for the Schedule Board Management component
export class ScheduleBoardManagement implements ComponentFramework.StandardControl<IInputs, IOutputs> {

    // Private variables to store the component's state and elements
    private _container: HTMLDivElement;
    private _context: ComponentFramework.Context<IInputs>;
    private _notifyOutputChanged: () => void;
    private _scheduleBoardSettingDropdown: HTMLSelectElement;
    private _selectedScheduleBoardSetting: string;
    private _copyButton: HTMLButtonElement;
    private _deleteButton: HTMLButtonElement;
    private _messageElement: HTMLDivElement;
    private _overlay: HTMLDivElement;
    private _deleteOverlay: HTMLDivElement;
    private _newNameInput: HTMLInputElement;
    private _submitButton: HTMLButtonElement;
    private _settingDetailsContainer: HTMLDivElement;
    private _disableEnableButton: HTMLButtonElement;
    private _disableEnableOverlay: HTMLDivElement;
    private _openInNewTabButton: HTMLButtonElement;

    constructor() { }

    // Initialize the component
    public init(context: ComponentFramework.Context<IInputs>, notifyOutputChanged: () => void, state: ComponentFramework.Dictionary, container: HTMLDivElement): void {
        this._context = context;
        this._container = container;
        this._notifyOutputChanged = notifyOutputChanged;

        // Set up the base wrapper for the control
        const wrapper = document.createElement("div");
        wrapper.className = "ms-Grid-SBS wrapper-SBS";
        wrapper.style.height = '100%';
        wrapper.style.display = 'flex';
        wrapper.style.flexDirection = 'column';

        // Add the h1 heading
        const heading = document.createElement("h1");
        heading.textContent = "Schedule Board Management";
        heading.className = "page-heading-SBS";
        wrapper.appendChild(heading);

        const row = document.createElement("div");
        row.className = "ms-Grid-row controls-row-SBS";
        wrapper.appendChild(row);

        // Schedule Board Setting dropdown with InfoLabel
        const settingColumn = this.createDropdownColumnWithInfoLabel("Schedule Board", "ms-Grid-col ms-sm6 ms-md6 ms-lg6");
        this._scheduleBoardSettingDropdown = settingColumn.querySelector('select') as HTMLSelectElement;
        this._scheduleBoardSettingDropdown.addEventListener("change", this.onScheduleBoardSettingChange.bind(this));
        row.appendChild(settingColumn);

        // Add Copy Board and Delete Board buttons
        const buttonColumn = this.createButtonColumn("ms-Grid-col ms-sm12 ms-md12 ms-lg12");
        this._copyButton = buttonColumn.querySelector('.copy-button') as HTMLButtonElement;
        this._copyButton.addEventListener("click", this.onCopyButtonClick.bind(this));
        this._deleteButton = buttonColumn.querySelector('.delete-button') as HTMLButtonElement;
        this._deleteButton.addEventListener("click", this.onDeleteButtonClick.bind(this));
        row.appendChild(buttonColumn);

        // Add Disable/Enable Board button
        this._disableEnableButton = document.createElement("button");
        this._disableEnableButton.className = "ms-Button-SBS ms-Button--default-SBS disable-enable-button";
        this._disableEnableButton.addEventListener("click", this.onDisableEnableButtonClick.bind(this));
        buttonColumn.appendChild(this._disableEnableButton);

        // Add message element
        this._messageElement = document.createElement("div");
        this._messageElement.className = "ms-MessageBar-SBS ms-MessageBar--success-SBS";
        this._messageElement.style.display = "none";
        wrapper.appendChild(this._messageElement);

        // Create copy overlay
        this._overlay = this.createOverlay();
        this._container.appendChild(this._overlay);

        // Create delete overlay
        this._deleteOverlay = this.createDeleteOverlay();
        this._container.appendChild(this._deleteOverlay);

        // Create disable/enable overlay
        this._disableEnableOverlay = this.createDisableEnableOverlay();
        this._container.appendChild(this._disableEnableOverlay);

        // Create a scrollable container for the setting details
        const scrollContainer = document.createElement("div");
        scrollContainer.className = "scroll-container-SBS";
        wrapper.appendChild(scrollContainer);

        // Move the setting details container inside the scroll container
        this._settingDetailsContainer = document.createElement("div");
        this._settingDetailsContainer.className = "setting-details-container-SBS";
        scrollContainer.appendChild(this._settingDetailsContainer);

        this._container.appendChild(wrapper);

        // Apply CSS
        this.applyStyles();

        // Load highlight.js and populate schedule board settings
        // Highlight.js is used to highlight the code in the setting details
        this.loadHighlightJS().then(() => {
            this.fetchAndPopulateScheduleBoardSettings();
        }).catch(error => {
            console.error("Failed to load highlight.js:", error);
            this.fetchAndPopulateScheduleBoardSettings();
        });

        // Ensure the container takes up the full height of its parent
        container.style.height = '100%';
        wrapper.style.height = '100%';
    }

    // Create the dropdown column with the info label for selecting the schedule board setting and showing the open in new tab and refresh buttons
    private createDropdownColumnWithInfoLabel(labelText: string, columnClass: string): HTMLDivElement {
        const column = document.createElement("div");
        column.className = columnClass;

        const fieldWrapper = document.createElement("div");
        fieldWrapper.className = "ms-TextField-SBS";

        const labelContainer = document.createElement("div");
        labelContainer.style.display = "flex";
        labelContainer.style.alignItems = "center";
        labelContainer.style.marginBottom = "4px";

        // Create the label for the dropdown column
        const label = document.createElement("h4");
        label.className = "ms-Label dropdown-label-SBS";
        label.textContent = labelText;
        label.style.marginRight = "8px";
        labelContainer.appendChild(label);

        const infoLabel = document.createElement("div");
        infoLabel.className = "info-label-container-SBS";
        labelContainer.appendChild(infoLabel);

        fieldWrapper.appendChild(labelContainer);

        // Create the dropdown wrapper so we can add the open in new tab and refresh buttons to the right of the dropdown
        const dropdownWrapper = document.createElement("div");
        dropdownWrapper.className = "dropdown-wrapper-SBS";

        // Create the dropdown element
        const dropdownElement = document.createElement("select");
        dropdownElement.className = "ms-Dropdown-SBS";
        dropdownWrapper.appendChild(dropdownElement);

        const buttonContainer = document.createElement("div");
        buttonContainer.className = "button-container-SBS";

        // Create the open in new tab button with an SVG icon
        this._openInNewTabButton = document.createElement("button");
        this._openInNewTabButton.className = "open-in-new-tab-button-SBS";
        this._openInNewTabButton.setAttribute("aria-label", "Open in new tab");
        this._openInNewTabButton.innerHTML = `
            <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
                <path d="M9 2L13 2L13 6M13 2L7 8M6 3H3C2.44772 3 2 3.44772 2 4V13C2 13.5523 2.44772 14 3 14H12C12.5523 14 13 13.5523 13 13V10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
        `;
        this._openInNewTabButton.addEventListener("click", (e) => this.onOpenInNewTabClick(e));

        // Create the refresh button with an SVG icon
        const refreshButton = document.createElement("button");
        refreshButton.className = "refresh-button-SBS";
        refreshButton.setAttribute("aria-label", "Refresh schedule board settings");
        refreshButton.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
            <path d="M14 8c0-3.31-2.69-6-6-6S2 4.69 2 8s2.69 6 6 6v-2c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4h-2l3 3 3-3h-2z" fill="currentColor"/>
            </svg>
        `;
        refreshButton.addEventListener("click", () => this.fetchAndPopulateScheduleBoardSettings());

        // Create the tooltip for the open in new tab button and the refresh button, then add them to the button container
        const tooltipRoot = ReactDOM.createRoot(buttonContainer);
        tooltipRoot.render(
            React.createElement(FluentProvider, { theme: webLightTheme },
                React.createElement(Tooltip, {
                    content: "Open Board form in new window",
                    relationship: "label",
                    withArrow: true
                } as TooltipProps,
                    React.createElement('div',
                        {
                            style: { float: 'left', marginRight: '8px' },
                            ref: (el: HTMLDivElement | null) => el && el.appendChild(this._openInNewTabButton)
                        })
                ),
                React.createElement(Tooltip, {
                    content: "Refresh schedule board settings",
                    relationship: "label",
                    withArrow: true
                } as TooltipProps,
                    React.createElement('div', {
                        style: { overflow: 'hidden' },
                        ref: (el: HTMLDivElement | null): void => { if (el) el.appendChild(refreshButton); }
                    })
                )
            )
        );

        dropdownWrapper.appendChild(buttonContainer);

        fieldWrapper.appendChild(dropdownWrapper);

        column.appendChild(fieldWrapper);

        // Create the info label for the dropdown column with formatted text that keeps the info label from being too wide
        const root = ReactDOM.createRoot(infoLabel);
        root.render(
            React.createElement(InfoLabel, {
                info: React.createElement(React.Fragment, null,
                    "Use the Copy Board button to make a copy of the",
                    React.createElement("br"),
                    "currently selected Schedule Board, allowing you",
                    React.createElement("br"),
                    "to set a new name for the copy. Changes can be",
                    React.createElement("br"),
                    "made to the copy via the Schedule Board link on",
                    React.createElement("br"),
                    "the left.",
                    React.createElement("br"),
                    React.createElement("br"),
                    "Use the Delete Board button to remove the",
                    React.createElement("br"),
                    "currently selected Schedule Board.",
                    React.createElement("br"),
                    React.createElement("br"),
                    "For enabled Schedule Boards, use Disable Board",
                    React.createElement("br"),
                    "to remove it from the tabs. For disabled boards,",
                    React.createElement("br"),
                    "use Enable Board to make it available again.",
                    React.createElement("br")
                ),
                size: "large"
            })
        );

        return column;
    }

    // Open the selected schedule board setting in a new tab
    private onOpenInNewTabClick(event: MouseEvent): void {
        event.preventDefault();
        if (this._selectedScheduleBoardSetting) {
            interface ContextWithPage extends ComponentFramework.Context<IInputs> {
                page: {
                    getClientUrl(): string;
                };
            }
            const contextWithPage = this._context as ContextWithPage;
            const baseUrl = contextWithPage.page.getClientUrl();
            const boardId = this._selectedScheduleBoardSetting;
            const url = `${baseUrl}/main.aspx?forceUCI=1&newWindow=true&pagetype=entityrecord&etn=msdyn_scheduleboardsetting&id=${boardId}`;
            window.open(url, "_blank");
        } else {
            console.warn("No schedule board setting selected");
            // Optionally, you can show a message to the user
            this.showMessage("Please select a Schedule Board Setting first.", false);
        }
    }

    // Create the button column with the copy and delete buttons
    private createButtonColumn(columnClass: string): HTMLDivElement {
        const column = document.createElement("div");
        column.className = columnClass;

        const copyButton = document.createElement("button");
        copyButton.className = "ms-Button-SBS ms-Button--primary-SBS copy-button";
        copyButton.style.marginRight = "8px";
        copyButton.textContent = "Copy Board";
        column.appendChild(copyButton);

        const deleteButton = document.createElement("button");
        deleteButton.className = "ms-Button-SBS ms-Button--danger-SBS delete-button";
        deleteButton.style.marginRight = "8px";
        deleteButton.textContent = "Delete Board";
        column.appendChild(deleteButton);

        return column;
    }

    // Create the overlay and confirmation dialogs for the copy and delete actions
    private createOverlay(): HTMLDivElement {
        const overlay = document.createElement("div");
        overlay.className = "overlay-SBS";
        overlay.setAttribute("role", "dialog");
        overlay.setAttribute("aria-modal", "true");
        overlay.style.display = "none";

        const content = document.createElement("div");
        content.className = "overlay-content-SBS";

        const header = document.createElement("div");
        header.className = "dialog-header-SBS";
        const title = document.createElement("h2");
        title.textContent = "Copy Schedule Board";
        title.id = "dialog-title";
        header.appendChild(title);
        content.appendChild(header);

        const body = document.createElement("div");
        body.className = "dialog-body-SBS";

        const fieldWrapper = document.createElement("div");
        fieldWrapper.className = "field-wrapper-SBS";

        // Create the input for the new board name
        this._newNameInput = document.createElement("input");
        this._newNameInput.type = "text";
        this._newNameInput.className = "field-input-name-SBS";
        this._newNameInput.id = "new-board-name";
        this._newNameInput.placeholder = "Enter new board name";
        this._newNameInput.setAttribute("aria-required", "true");
        fieldWrapper.appendChild(this._newNameInput);

        // Create the helper text for the new board name input
        const helperText = document.createElement("span");
        helperText.className = "field-helper-text-SBS";
        helperText.textContent = "Enter a unique name for the new Schedule Board";
        fieldWrapper.appendChild(helperText);

        body.appendChild(fieldWrapper);
        content.appendChild(body);

        const footer = document.createElement("div");
        footer.className = "dialog-footer-SBS";

        // Create the submit button
        this._submitButton = document.createElement("button");
        this._submitButton.textContent = "Submit";
        this._submitButton.className = "ms-Button-SBS ms-Button--primary-SBS";
        this._submitButton.disabled = true;
        this._submitButton.addEventListener("click", this.onSubmitButtonClick.bind(this));

        // Create the cancel button
        const cancelButton = document.createElement("button");
        cancelButton.textContent = "Cancel";
        cancelButton.className = "ms-Button-SBS ms-Button--default-SBS";
        cancelButton.addEventListener("click", this.onCancelButtonClick.bind(this));

        footer.appendChild(this._submitButton);
        footer.appendChild(cancelButton);
        content.appendChild(footer);

        this._newNameInput.addEventListener("input", this.onNewNameInput.bind(this));

        overlay.appendChild(content);
        overlay.setAttribute("aria-labelledby", "dialog-title");
        return overlay;
    }

    // Create the overlay and confirmation dialog for the delete action
    private createDeleteOverlay(): HTMLDivElement {
        const overlay = document.createElement("div");
        overlay.className = "overlay-SBS";
        overlay.setAttribute("role", "alertdialog");
        overlay.setAttribute("aria-modal", "true");
        overlay.style.display = "none";

        const content = document.createElement("div");
        content.className = "overlay-content-SBS";

        const header = document.createElement("div");
        header.className = "dialog-header-SBS";
        const title = document.createElement("h2");
        title.textContent = "Confirm Deletion";
        title.id = "delete-dialog-title";
        header.appendChild(title);
        content.appendChild(header);

        const body = document.createElement("div");
        body.className = "dialog-body-SBS";
        const prompt = document.createElement("p");
        prompt.textContent = "Are you sure you want to delete this board?";
        body.appendChild(prompt);
        content.appendChild(body);

        const footer = document.createElement("div");
        footer.className = "dialog-footer-SBS";

        // Create the submit button
        const submitButton = document.createElement("button");
        submitButton.textContent = "Submit";
        submitButton.className = "ms-Button-SBS ms-Button--danger-SBS";
        submitButton.addEventListener("click", this.onDeleteSubmitButtonClick.bind(this));

        // Create the cancel button
        const cancelButton = document.createElement("button");
        cancelButton.textContent = "Cancel";
        cancelButton.className = "ms-Button-SBS ms-Button--default-SBS";
        cancelButton.addEventListener("click", this.onDeleteCancelButtonClick.bind(this));

        footer.appendChild(submitButton);
        footer.appendChild(cancelButton);
        content.appendChild(footer);

        overlay.appendChild(content);
        overlay.setAttribute("aria-labelledby", "delete-dialog-title");
        return overlay;
    }

    // Create the overlay and confirmation dialog for the disable/enable action
    private createDisableEnableOverlay(): HTMLDivElement {
        const overlay = document.createElement("div");
        overlay.className = "overlay-SBS";
        overlay.setAttribute("role", "alertdialog");
        overlay.setAttribute("aria-modal", "true");
        overlay.style.display = "none";

        const content = document.createElement("div");
        content.className = "overlay-content-SBS";

        const header = document.createElement("div");
        header.className = "dialog-header-SBS";
        const title = document.createElement("h2");
        title.textContent = "Confirm Action";
        title.id = "disable-enable-dialog-title";
        header.appendChild(title);
        content.appendChild(header);

        const body = document.createElement("div");
        body.className = "dialog-body-SBS";
        const prompt = document.createElement("p");
        body.appendChild(prompt);
        content.appendChild(body);

        const footer = document.createElement("div");
        footer.className = "dialog-footer-SBS";

        // Create the submit button
        const yesButton = document.createElement("button");
        yesButton.textContent = "Submit";
        yesButton.className = "ms-Button-SBS ms-Button--primary-SBS";
        yesButton.addEventListener("click", this.onDisableEnableSubmitButtonClick.bind(this));

        // Create the cancel button
        const noButton = document.createElement("button");
        noButton.textContent = "Cancel";
        noButton.className = "ms-Button-SBS ms-Button--default-SBS";
        noButton.addEventListener("click", this.onDisableEnableCancelButtonClick.bind(this));

        footer.appendChild(yesButton);
        footer.appendChild(noButton);
        content.appendChild(footer);

        overlay.appendChild(content);
        overlay.setAttribute("aria-labelledby", "disable-enable-dialog-title");
        return overlay;
    }

    // Enable/disable the submit button based on the new board name input
    private onNewNameInput(): void {
        this._submitButton.disabled = this._newNameInput.value.trim() === "";
    }

    // Close the overlay on cancel
    private onCancelButtonClick(): void {
        this._overlay.style.display = "none";
    }

    // Fetch the schedule board settings and populate the dropdown
    private async fetchAndPopulateScheduleBoardSettings(): Promise<void> {
        try {
            const settings = await this.getScheduleBoardSettings();
            this.populateDropdown(this._scheduleBoardSettingDropdown, settings, 'msdyn_tabname', 'msdyn_scheduleboardsettingid');
            if (settings.length > 0) {
                this._selectedScheduleBoardSetting = settings[0].msdyn_scheduleboardsettingid;
                await this.displaySettingDetails();
            }
        } catch (error) {
            console.error("Error fetching schedule board settings:", error);
            this.addOption(this._scheduleBoardSettingDropdown, "Error loading settings", "error");
        }
        this._notifyOutputChanged();
    }

    // Fetch the schedule board settings from D365 ordered by the tab name
    private async getScheduleBoardSettings(): Promise<ScheduleBoardSetting[]> {
        const fields = [
            "msdyn_scheduleboardsettingid",
            "msdyn_tabname",
            "msdyn_bookbasedon",
            "msdyn_schedulerbusinessunittooltipview",
            "msdyn_schedulercoredetailsview",
            "msdyn_schedulercoreslottexttemplate",
            "msdyn_schedulercoretooltipview",
            "msdyn_customtabname",
            "msdyn_customtabwebresource",
            "msdyn_schedulerfieldservicedetailsview",
            "msdyn_schedulerfieldserviceslottexttemplate",
            "msdyn_schedulerfieldservicetooltipview",
            "_msdyn_filterlayout_value",
            "msdyn_filtervalues",
            "msdyn_fullybookedcolor",
            "msdyn_hidecancelled",
            "msdyn_ispublic",
            "msdyn_issynchronizeresources",
            "msdyn_mapviewtabplacement",
            "msdyn_workinghourscolor",
            "msdyn_notbookedcolor",
            "msdyn_ordernumber",
            "msdyn_organizationalunittooltipsviewid",
            "msdyn_organizationalunitviewid",
            "msdyn_overbookedcolor",
            "msdyn_partiallybookedcolor",
            "msdyn_unscheduledrequirementsviewid",
            "_msdyn_resourcecelltemplate_value",
            "msdyn_schedulerresourcedetailsview",
            "msdyn_unscheduledwopagereccount",
            "msdyn_schedulerresourcetooltipview",
            "_msdyn_retrieveresourcesquery_value",
            "msdyn_saavailablecolor",
            "msdyn_saavailableicon",
            "msdyn_saavailableicondefault",
            "msdyn_sapartiallyavailablecolor",
            "msdyn_sapartiallyavailableicon",
            "msdyn_sapartiallyavailableicondefault",
            "msdyn_saunavailablecolor",
            "msdyn_saunavailableicon",
            "msdyn_saunavailableicondefault",
            "msdyn_scheduleralertsview",
            "msdyn_settings",
            "msdyn_sharetype",
            "msdyn_schedulerbusinessunitdetailsview",
            "msdyn_unscheduledviewid",
            "msdyn_unscheduledwotooltipsviewid"
        ].join(",");

        try {
            const response = await this._context.webAPI.retrieveMultipleRecords("msdyn_scheduleboardsetting", `?$select=${fields}&$orderby=msdyn_tabname asc`);
            return response.entities as ScheduleBoardSetting[];
        } catch (error) {
            console.error("Error fetching schedule board settings:", error);
            throw error;
        }
    }

    // Populate the dropdown with the schedule board settings
    private populateDropdown<T>(dropdown: HTMLSelectElement, items: T[], textField: keyof T, valueField: keyof T): void {
        dropdown.innerHTML = '';
        if (items.length === 0) {
            this.addOption(dropdown, "No items available", "");
            return;
        }

        items.forEach(item => {
            this.addOption(dropdown, item[textField] as string, item[valueField] as string);
        });
    }

    // Method to add an option to the dropdown
    private addOption(dropdown: HTMLSelectElement, text: string, value: string): void {
        const option = document.createElement("option");
        option.value = value;
        option.text = text;
        dropdown.appendChild(option);
    }

    // Method to handle the copy button click which opens the overlay to create a new board
    private async onCopyButtonClick(): Promise<void> {
        if (!this._selectedScheduleBoardSetting) {
            this.showMessage("Please select a Schedule Board Setting to copy.", false);
            return;
        }

        try {
            this._overlay.style.display = "flex";
            this._newNameInput.value = "";
            this._submitButton.disabled = true;
        } catch (error) {
            console.error("Error retrieving Schedule Board Setting:", error);
            this.showMessage("An error occurred while retrieving the Schedule Board Setting.", false);
        }
    }

    // Method to handle the delete button click
    private async onDeleteButtonClick(): Promise<void> {
        if (!this._selectedScheduleBoardSetting) {
            this.showMessage("Please select a Schedule Board Setting to delete.", false);
            return;
        }

        try {
            const originalSetting = await this._context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", this._selectedScheduleBoardSetting, "?$select=msdyn_tabname");
            const tabName = originalSetting.msdyn_tabname;

            // Handle restricted system boards that cannot be deleted
            const restrictedNames = ["Default", "Initial public view", "Resource utilization view"];
            if (restrictedNames.includes(tabName)) {
                this.showMessage(`Cannot delete the "${tabName}" Schedule Board Setting. This is a system board.`, false);
                return;
            }

            this._deleteOverlay.style.display = "flex";
        } catch (error) {
            console.error("Error retrieving Schedule Board Setting:", error);
            this.showMessage("An error occurred while retrieving the Schedule Board Setting.", false);
        }
    }

    // Method to handle the disable/enable button click which opens the overlay to disable/enable a board
    private async onDisableEnableButtonClick(): Promise<void> {
        if (!this._selectedScheduleBoardSetting) {
            this.showMessage("Please select a Schedule Board Setting to disable/enable.", false);
            return;
        }

        try {
            const setting = await this._context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", this._selectedScheduleBoardSetting, "?$select=msdyn_tabname,statecode");
            const tabName = setting.msdyn_tabname;
            const currentStateCode = setting.statecode;

            // Handle restricted system boards that cannot be disabled
            const restrictedNames = ["Default", "Resource utilization view"];
            if (restrictedNames.includes(tabName)) {
                this.showMessage(`Cannot disable/enable the "${tabName}" Schedule Board Setting. This is a system board.`, false);
                return;
            }

            // Set the prompt message based on the current state of the board
            const prompt = this._disableEnableOverlay.querySelector("p");
            if (currentStateCode === 0) {
                prompt!.textContent = "Are you sure you want to disable this Schedule Board?";
            } else {
                prompt!.textContent = "Are you sure you want to enable this Schedule Board?";
            }

            this._disableEnableOverlay.style.display = "flex";
        } catch (error) {
            console.error("Error retrieving Schedule Board Setting:", error);
            this.showMessage("An error occurred while retrieving the Schedule Board Setting.", false);
        }
    }

    // Method to handle the cancel button click for the delete overlay
    private onDeleteCancelButtonClick(): void {
        this._deleteOverlay.style.display = "none";
    }

    // Method to handle the cancel button click for the disable/enable overlay
    private onDisableEnableCancelButtonClick(): void {
        this._disableEnableOverlay.style.display = "none";
    }

    // Method to handle the submit button click for the delete overlay
    private async onDeleteSubmitButtonClick(): Promise<void> {
        this._deleteOverlay.style.display = "none";
        const spinner = this.showSpinner();

        try {
            // Delete the selected schedule board setting from D365 and refresh the dropdown
            await this._context.webAPI.deleteRecord("msdyn_scheduleboardsetting", this._selectedScheduleBoardSetting);
            this.hideSpinner(spinner);
            this.showMessage("Schedule Board Setting has been successfully deleted.", true);
            this.fetchAndPopulateScheduleBoardSettings();
        } catch (error) {
            this.hideSpinner(spinner);
            console.error("Error deleting Schedule Board Setting:", error);
            this.showMessage("An error occurred while deleting the Schedule Board Setting.", false);
        }
    }

    // Method to handle the submit button click for the disable/enable overlay
    private async onDisableEnableSubmitButtonClick(): Promise<void> {
        this._disableEnableOverlay.style.display = "none";
        const spinner = this.showSpinner();

        try {
            // Update the state of the selected schedule board setting in D365 and refresh the dropdown
            const setting = await this._context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", this._selectedScheduleBoardSetting, "?$select=statecode");
            const currentStateCode = setting.statecode;

            const newState = {
                statecode: currentStateCode === 0 ? 1 : 0,
                statuscode: currentStateCode === 0 ? 2 : 1
            };

            await this._context.webAPI.updateRecord("msdyn_scheduleboardsetting", this._selectedScheduleBoardSetting, newState);

            const action = currentStateCode === 0 ? "disabled" : "enabled";
            this.hideSpinner(spinner);
            this.showMessage(`Schedule Board Setting has been successfully ${action}.`, true);
            this.fetchAndPopulateScheduleBoardSettings();
        } catch (error) {
            this.hideSpinner(spinner);
            console.error("Error updating Schedule Board Setting:", error);
            this.showMessage("An error occurred while updating the Schedule Board Setting.", false);
        }
    }

    // Method to handle the submit button click for the copy overlay
    private async onSubmitButtonClick(): Promise<void> {
        const newName = this._newNameInput.value.trim();
        this._overlay.style.display = "none";
        const spinner = this.showSpinner();

        try {
            // Retrieve the original schedule board setting and create a new one with the same values
            const originalSetting = await this._context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", this._selectedScheduleBoardSetting) as ScheduleBoardSetting;

            const newSetting: Partial<ScheduleBoardSetting> = {};

            for (const key in originalSetting) {
                if (key.startsWith("msdyn_") && key !== "msdyn_scheduleboardsettingid") {
                    newSetting[key] = originalSetting[key];
                }
            }

            // Set the new tab name from the input field
            newSetting.msdyn_tabname = newName;

            // Handle msdyn_ordernumber when copying a system board
            if (originalSetting.msdyn_ordernumber === null) {
                newSetting.msdyn_ordernumber = 0;
            } else {
                newSetting.msdyn_ordernumber = originalSetting.msdyn_ordernumber;
            }

            // Handle msdyn_sharetype when copying a system board
            if (originalSetting.msdyn_sharetype === 192350003) {
                newSetting.msdyn_sharetype = 192350000;
            } else {
                newSetting.msdyn_sharetype = originalSetting.msdyn_sharetype;
            }

            // Create the new schedule board setting in D365 and refresh the dropdown
            await this._context.webAPI.createRecord("msdyn_scheduleboardsetting", newSetting);
            this.hideSpinner(spinner);
            this.showMessage(`Schedule Board Setting "${newName}" has been successfully created.`, true);
            this.fetchAndPopulateScheduleBoardSettings();
        } catch (error) {
            this.hideSpinner(spinner);
            console.error("Error copying Schedule Board Setting:", error);
            this.showMessage("An error occurred while copying the Schedule Board Setting.", false);
        }
    }

    // Method to handle the change event for the schedule board setting dropdown
    private async onScheduleBoardSettingChange(event: Event): Promise<void> {
        this._selectedScheduleBoardSetting = (event.target as HTMLSelectElement).value;
        this._notifyOutputChanged();
        await this.displaySettingDetails();
    }

    // Method to display the details of the selected schedule board setting
    private async displaySettingDetails(): Promise<void> {
        if (!this._selectedScheduleBoardSetting) {
            this._settingDetailsContainer.innerHTML = '';
            return;
        }

        try {
            // Retrieve the details of the selected schedule board setting from D365
            const setting = await this._context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", this._selectedScheduleBoardSetting);

            // Build the HTML for the setting details container
            let detailsHTML = `
                <div class="setting-details-scroll-container-SBS">
                    <h3>Schedule Board Setting Details</h3>
                    <p class="info-text-SBS">
                        Each Schedule Board Setting maps to a given field or JSON attribute within a given field.
                    </p>
                    <div class="table-container-SBS">
                        <table class="setting-details-table-SBS">
            `;

            // Only display the fields that are not deprecated
            const fieldsToDisplay = [
                { key: 'msdyn_tabname', label: 'Tab name' },
                { key: 'msdyn_bookbasedon', label: 'Book Based On' },
                { key: 'msdyn_schedulerbusinessunittooltipview', label: 'Business Unit Tooltips View (Deprecated)' },
                { key: 'msdyn_schedulercoredetailsview', label: 'Core Details View (Deprecated)' },
                { key: 'msdyn_schedulercoreslottexttemplate', label: 'Core Slot Text Template (Deprecated)' },
                { key: 'msdyn_schedulercoretooltipview', label: 'Core Tooltip View (Deprecated)' },
                { key: 'msdyn_customtabname', label: 'Custom Tab Name' },
                { key: 'msdyn_customtabwebresource', label: 'Custom Tab Web Resource' },
                { key: 'msdyn_schedulerfieldservicedetailsview', label: 'Field Service Details View (Deprecated)' },
                { key: 'msdyn_schedulerfieldserviceslottexttemplate', label: 'Field Service Slot Text Template (Deprecated)' },
                { key: 'msdyn_schedulerfieldservicetooltipview', label: 'Field Service Tooltip View (Deprecated)' },
                { key: '_msdyn_filterlayout_value', label: 'Filter Layout' },
                { key: 'msdyn_filtervalues', label: 'Filter Values' },
                { key: 'msdyn_fullybookedcolor', label: 'Fully Booked Color' },
                { key: 'msdyn_hidecancelled', label: 'Hide Canceled' },
                { key: 'msdyn_ispublic', label: 'Is Public (Deprecated)' },
                { key: 'msdyn_issynchronizeresources', label: 'Is Synchronize Resources' },
                { key: 'msdyn_mapviewtabplacement', label: 'Map View Tab Placement' },
                { key: 'msdyn_workinghourscolor', label: 'Non-Working Hours Color' },
                { key: 'msdyn_notbookedcolor', label: 'Not Booked Color' },
                { key: 'msdyn_ordernumber', label: 'Order Number' },
                { key: 'msdyn_organizationalunittooltipsviewid', label: 'Organizational Unit Tooltips View Id' },
                { key: 'msdyn_organizationalunitviewid', label: 'Organizational Unit View Id' },
                { key: 'msdyn_overbookedcolor', label: 'Overbooked Color' },
                { key: 'msdyn_partiallybookedcolor', label: 'Partially Booked Color' },
                { key: 'msdyn_unscheduledrequirementsviewid', label: 'Requirements View Id' },
                { key: '_msdyn_resourcecelltemplate_value', label: 'Resource Cell Template' },
                { key: '_msdyn_schedulerresourcedetailsview_value', label: 'Resource Details View' },
                { key: 'msdyn_unscheduledwopagereccount', label: 'Resource Requirement View Page Record Count' },
                { key: 'msdyn_schedulerresourcetooltipview', label: 'Resource Tooltips View' },
                { key: '_msdyn_retrieveresourcesquery_value', label: 'Retrieve Resources Query' },
                { key: 'msdyn_saavailablecolor', label: 'SA Available Color' },
                { key: 'msdyn_saavailableicon', label: 'SA Available Icon' },
                { key: 'msdyn_saavailableicondefault', label: 'SA Available Icon Default' },
                { key: 'msdyn_sapartiallyavailablecolor', label: 'SA Partially Available Color' },
                { key: 'msdyn_sapartiallyavailableicon', label: 'SA Partially Available Icon' },
                { key: 'msdyn_sapartiallyavailableicondefault', label: 'SA Partially Available Icon Default' },
                { key: 'msdyn_saunavailablecolor', label: 'SA Unavailable Color' },
                { key: 'msdyn_saunavailableicon', label: 'SA Unavailable Icon' },
                { key: 'msdyn_saunavailableicondefault', label: 'SA Unavailable Icon Default' },
                { key: 'msdyn_scheduleralertsview', label: 'Scheduler Alerts View' },
                { key: 'msdyn_settings', label: 'Settings' },
                { key: 'msdyn_sharetype', label: 'Share Type' },
                { key: 'msdyn_schedulerbusinessunitdetailsview', label: 'Unit Details View (Deprecated)' },
                { key: 'msdyn_unscheduledviewid', label: 'Unscheduled View (Deprecated)' },
                { key: 'msdyn_unscheduledwotooltipsviewid', label: 'Unscheduled WO Tooltips View (Deprecated)' }
            ];

            for (const field of fieldsToDisplay) {
                const isDeprecated = field.label.toLowerCase().includes('deprecated');
                const rowClass = isDeprecated ? 'deprecated-field' : '';

                // Check if the field is a view and display the name using the savedqueryid
                if ((field.key.includes('viewid') || field.key.includes('msdyn_scheduleralertsview') || field.key.includes('msdyn_schedulerresourcetooltipview') || field.key.includes('msdyn_schedulerresourcedetailsview'))
                    && setting[field.key] != null) {
                    //Query the view and display the name using the savedqueryid
                    const viewId = setting[field.key] as string;
                    let viewName = 'N/A';

                    try {
                        let viewData;
                        try {
                            viewData = await this._context.webAPI.retrieveRecord("savedquery", viewId, "?$select=name");
                        } catch (error) {
                            if (error instanceof Error && error.message.includes("Does Not Exist")) {
                                // If savedquery doesn't exist, try userquery
                                viewData = await this._context.webAPI.retrieveRecord("userquery", viewId, "?$select=name");
                            } else {
                                throw error; // Re-throw if it's not a "Does Not Exist" error
                            }
                        }
                        viewName = viewData.name;
                    } catch (error) {
                        console.error("Error fetching view data:", error);
                        viewName = '<span style="color: red;">Error getting view name - check browser console for errors</span>';
                    }

                    detailsHTML += `
                        <tr class="${rowClass}">
                            <td class="field-label-SBS">${field.label}:</td>
                            <td class="field-value-SBS">${viewId} (${viewName})</td>
                        </tr>
                    `;
                }

                // Check if the field has a formatted value and display the name using the formatted value
                else if ((field.key.includes('msdyn_sharetype') || field.key.includes('_msdyn_resourcecelltemplate_value') || field.key.includes('_msdyn_retrieveresourcesquery_value') || field.key.includes('_msdyn_filterlayout_value') || field.key.includes('msdyn_ispublic') || field.key.includes('msdyn_bookbasedon') || field.key.includes('msdyn_sapartiallyavailableicondefault') || field.key.includes('msdyn_mapviewtabplacement') || field.key.includes('msdyn_hidecancelled') || field.key.includes('msdyn_issynchronizeresources') || field.key.includes('msdyn_saunavailableicondefault') || field.key.includes('msdyn_saavailableicondefault'))
                    && setting[field.key] != null) {

                    const configurationId = setting[field.key] as string;
                    const configurationData = field.key.toString() + '@OData.Community.Display.V1.FormattedValue';
                    const configurationName = setting[configurationData] || 'N/A';

                    detailsHTML += `
                        <tr class="${rowClass}">
                            <td class="field-label-SBS">${field.label}:</td>
                            <td class="field-value-SBS">${configurationId} (${configurationName})</td>
                        </tr>
                    `;
                }

                // Check if the field is a JSON field and display the formatted JSON
                else if (field.key === 'msdyn_settings' || field.key === 'msdyn_filtervalues') {
                    detailsHTML += `
                        <tr class="${rowClass}">
                            <td class="field-label-SBS">${field.label}:</td>
                            <td class="field-value-SBS">
                                <pre><code class="json">${this.formatJSON(setting[field.key])}</code></pre>
                            </td>
                        </tr>
                    `;
                }

                // Check if the field is a color field and display the color as a div with a colored square otherwise display the value
                else {
                    const value = setting[field.key] != null ? setting[field.key] : 'N/A';
                    let displayValue = value;


                    // Check if the field label ends with "Color" and the value is a valid hex color (with or without #)
                    if (field.label.endsWith("Color") && typeof value === 'string') {
                        const hexColor = value.startsWith('#') ? value : `#${value}`;
                        if (/^#[0-9A-Fa-f]{6}$/.test(hexColor)) {
                            displayValue = `
                                <div style="display: flex; align-items: center;">
                                    <div style="width: 20px; height: 20px; background-color: ${hexColor}; border: 1px solid #ccc; margin-right: 10px;"></div>
                                    ${value}
                                </div>
                            `;
                        }
                    }

                    detailsHTML += `
                        <tr class="${rowClass}">
                            <td class="field-label-SBS">${field.label}:</td>
                            <td class="field-value-SBS">${displayValue}</td>
                        </tr>
                    `;
                }
            }

            detailsHTML += `
                        </table>
                    </div>
                </div>
            `;
            this._settingDetailsContainer.innerHTML = detailsHTML;

            // Apply syntax highlighting if hljs is available
            if (window.hljs && typeof window.hljs.highlightAll === 'function') {
                window.hljs.highlightAll();
            } else {
                console.warn('highlight.js is not available. Syntax highlighting will not be applied.');
            }

            // Check the statecode and set the disable/enable button text and data-state attribute
            const stateCode = setting.statecode;
            if (stateCode === 0) {
                this._disableEnableButton.textContent = "Disable Board";
                this._disableEnableButton.setAttribute('data-state', 'active');
            } else {
                this._disableEnableButton.textContent = "Enable Board";
                this._disableEnableButton.setAttribute('data-state', 'inactive');
            }

            // Hide deprecated fields
            const deprecatedFields = this._settingDetailsContainer.querySelectorAll('.deprecated-field');
            deprecatedFields.forEach((field) => {
                (field as HTMLElement).style.display = 'none';
            });
        } catch (error) {
            console.error("Error fetching Schedule Board Setting details:", error);
            this._settingDetailsContainer.innerHTML = '<p class="error-message-SBS">Error loading Schedule Board Setting details.</p>';
        }
    }

    // Method to format JSON fields
    private formatJSON(value: string | number | boolean | null | undefined): string {
        if (value === null || value === undefined) return 'N/A';
        if (typeof value === 'string') {
            try {
                const obj = JSON.parse(value);
                return JSON.stringify(obj, null, 2);
            } catch (e) {
                console.error("Error parsing JSON:", e);
                return value; // Return original string if parsing fails
            }
        }
        // For numbers and booleans, we'll just convert them to a string
        return String(value);
    }

    // Method to show a message to the user after an action has been performed
    private showMessage(message: string, isSuccess: boolean): void {
        this._messageElement.textContent = message;
        this._messageElement.className = isSuccess ? "ms-MessageBar-SBS ms-MessageBar--success-SBS" : "ms-MessageBar-SBS ms-MessageBar--error-SBS";
        this._messageElement.style.display = "block";
        setTimeout(() => {
            this._messageElement.style.display = "none";
        }, 5000);
    }

    // Method to show a spinner to the user while an action is being performed
    private showSpinner(): HTMLDivElement {
        const spinnerContainer = document.createElement("div");
        spinnerContainer.className = "spinner-container-SBS";

        const spinner = document.createElement("div");
        spinner.className = "spinner-SBS";
        spinner.setAttribute("role", "progressbar");
        spinner.setAttribute("aria-label", "Operation in progress");

        const label = document.createElement("div");
        label.className = "spinner-label-SBS";
        label.textContent = "Processing...";

        spinnerContainer.appendChild(spinner);
        spinnerContainer.appendChild(label);

        document.body.appendChild(spinnerContainer);

        // Force a reflow to ensure the spinner is displayed immediately
        spinnerContainer.offsetHeight;

        return spinnerContainer;
    }

    // Method to hide a spinner from the user after an action has been performed
    private hideSpinner(spinnerContainer: HTMLDivElement): void {
        document.body.removeChild(spinnerContainer);
    }

    // Method to apply CSS to the page
    private applyStyles(): void {
        const style = document.createElement("style");
        style.textContent = `
            :root {
                --colorNeutralBackground1: #ffffff;
                --colorNeutralBackground1Hover: #f5f5f5;
                --colorNeutralBackground1Pressed: #e0e0e0;
                --colorNeutralForeground1: #242424;
                --colorBrandBackground: #0078d4;
                --colorBrandBackgroundHover: #106ebe;
                --colorBrandBackgroundPressed: #005a9e;
                --colorNeutralStroke1: #d1d1d1;
                --colorNeutralStrokeAccessible: #737373;
                --colorNeutralBackgroundDisabled: #f3f3f3;
                --colorNeutralForegroundDisabled: #a6a6a6;
                --colorDangerBackground: #a4262c;
                --colorDangerBackgroundHover: #8e1b22;
                --colorDangerBackgroundPressed: #78191f;
                --fontFamily: 'Segoe UI', sans-serif;
                --fontSizeBase100: 12px;
                --fontSizeBase200: 14px;
                --fontSizeBase300: 16px;
                --fontSizeBase400: 18px;
                --fontSizeBase500: 20px;
                --fontWeightRegular: 400;
                --fontWeightSemibold: 600;
                --lineHeightBase100: 16px;
                --lineHeightBase200: 20px;
                --lineHeightBase300: 24px;
                --lineHeightBase400: 28px;
                --lineHeightBase500: 32px;
            }

            .wrapper-SBS {
                font-family: var(--fontFamily);
                color: var(--colorNeutralForeground1);
                background-color: var(--colorNeutralBackground1);
                padding: 20px;
                max-height: 100vh; /* Set maximum height to viewport height */
                overflow-y: auto; /* Add vertical scrollbar when content exceeds height */
            }

            .ms-TextField-SBS {
                margin-bottom: 16px;
                max-width: 356px;
            }

            .dropdown-label-SBS {
                padding: 5px 0px;
                color: rgba(36, 36, 36, 1);
                font-family: "Segoe UI", "Segoe UI Web (West European)", -apple-system, BlinkMacSystemFont, Roboto, "Helvetica Neue", sans-serif;
                font-size: 14px;
                font-weight: 600;
                -webkit-font-smoothing: antialiased;
                margin: 0px;
                box-sizing: border-box;
                box-shadow: none;
                display: inline-block;
                overflow-wrap: break-word;
            }

            .ms-Dropdown-SBS {
                width: 100%;
                height: 32px;
                padding: 0 32px 0 12px;
                background-color: var(--colorNeutralBackground1);
                border: 1px solid var(--colorNeutralStroke1);
                border-radius: 4px;
                font-size: var(--fontSizeBase200);
                color: var(--colorNeutralForeground1);
                appearance: none;
                -webkit-appearance: none;
                background-image: url("data:image/svg+xml;charset=US-ASCII,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2212%22%20height%3D%2212%22%20viewBox%3D%220%200%2012%2012%22%3E%3Cpath%20fill%3D%22%23333%22%20d%3D%22M6%208L0%202h12z%22%2F%3E%3C%2Fsvg%3E");
                background-repeat: no-repeat;
                background-position: right 12px center;
                flex-grow: 1;
                margin-right: 8px;
            }

            .dropdown-wrapper-SBS {
                display: flex;
                align-items: center;
            }

            .open-in-new-tab-button-SBS,
            .refresh-button-SBS {
                width: 32px;
                height: 32px;
                padding: 0;
                background-color: var(--colorNeutralBackground1);
                border: 1px solid var(--colorNeutralStroke1);
                border-radius: 4px;
                cursor: pointer;
                display: flex;
                justify-content: center;
                align-items: center;
                transition: all 0.1s ease;
            }

            .open-in-new-tab-button-SBS:hover,
            .refresh-button-SBS:hover {
                background-color: var(--colorNeutralBackground1Hover);
                border-color: var(--colorNeutralStrokeAccessible);
            }

            .open-in-new-tab-button-SBS:active,
            .refresh-button-SBS:active {
                background-color: var(--colorNeutralBackground1Pressed);
            }

            .open-in-new-tab-button-SBS svg,
            .refresh-button-SBS svg {
                width: 16px;
                height: 16px;
                fill: none;
                stroke: var(--colorNeutralForeground1);
            }

            .refresh-button-SBS svg {
                fill: var(--colorNeutralForeground1);
                stroke: none;
            }

            .button-container-SBS {
                display: flex;
                gap: 8px;
                width: 97px;
            }

            .ms-Dropdown-SBS:hover {
                border-color: var(--colorNeutralStrokeAccessible);
            }

            .ms-Dropdown-SBS:focus {
                border-color: var(--colorBrandBackground);
                outline: none;
            }

            .ms-Button-SBS {
                min-width: 80px;
                padding: 0 16px;
                height: 32px;
                background-color: var(--colorBrandBackground);
                color: var(--colorNeutralBackground1);
                border: none;
                border-radius: 4px;
                cursor: pointer;
                font-family: "Segoe UI", "Segoe UI Web (West European)", -apple-system, BlinkMacSystemFont, Roboto, "Helvetica Neue", sans-serif;
                font-size: 14px;
                font-weight: 600;
                -webkit-font-smoothing: antialiased;
                margin-top: 0px;
                transition: background-color 0.1s ease;
            }

            .ms-Button-SBS:hover {
                background-color: var(--colorBrandBackgroundHover);
            }

            .ms-Button-SBS:active {
                background-color: var(--colorBrandBackgroundPressed);
            }

            .ms-Button--default-SBS {
                background-color: var(--colorNeutralBackground1);
                color: var(--colorNeutralForeground1);
                border: 1px solid var(--colorNeutralStroke1);
            }

            .ms-Button--default-SBS:hover {
                background-color: var(--colorNeutralBackground1Hover);
            }

            .ms-Button--default-SBS:active {
                background-color: var(--colorNeutralBackground1Pressed);
            }

            .ms-Button--danger-SBS {
                background-color: var(--colorDangerBackground);
                color: var(--colorNeutralBackground1);
            }

            .ms-Button--danger-SBS:hover {
                background-color: var(--colorDangerBackgroundHover);
            }

            .ms-Button--danger-SBS:active {
                background-color: var(--colorDangerBackgroundPressed);
            }

            .ms-MessageBar-SBS {
                padding: 8px 12px;
                margin-top: 16px;
                font-size: var(--fontSizeBase200);
                display: flex;
                align-items: center;
                border-radius: 4px;
            }

            .ms-MessageBar--success-SBS {
                background-color: #dff6dd;
                color: #107c10;
                border: 1px solid #107c10;
            }

            .ms-MessageBar--error-SBS {
                background-color: #fde7e9;
                color: #a80000;
                border: 1px solid #a80000;
            }

            .overlay-SBS {
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(0, 0, 0, 0.4);
                display: none;
                justify-content: center;
                align-items: center;
                z-index: 1000;
            }

            .overlay-content-SBS {
                background-color: var(--colorNeutralBackground1);
                border-radius: 4px;
                box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
                max-width: 400px;
                width: 90%;
                display: flex;
                flex-direction: column;
            }

            .dialog-header-SBS {
                padding: 24px 24px 0;
            }

            .dialog-header-SBS h2 {
                margin: 0;
                font-size: var(--fontSizeBase500);
                font-weight: var(--fontWeightSemibold);
            }

            .dialog-body-SBS {
                padding: 24px;
                flex-grow: 1;
            }

            .dialog-footer-SBS {
                padding: 24px;
                display: flex;
                justify-content: flex-end;
                gap: 8px;
            }

            .setting-details-container-SBS {
                margin-top: 24px;
                padding: 20px;
                background-color: var(--colorNeutralBackground1);
                border-radius: 4px;
                box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
            }

            .setting-details-container-SBS h3 {
                margin-top: 0;
                margin-bottom: 16px;
                font-size: var(--fontSizeBase400);
                font-weight: var(--fontWeightSemibold);
                color: var(--colorNeutralForeground1);
            }

            .setting-details-table-SBS {
                width: 100%;
                border-collapse: separate;
                border-spacing: 0;
                background-color: var(--colorNeutralBackground1);
            }

            .setting-details-table-SBS td {
                padding: 12px;
                border-bottom: 1px solid var(--colorNeutralStroke1);
            }

            .setting-details-table-SBS tr:last-child td {
                border-bottom: none;
            }

            .field-label-SBS {
                font-weight: var(--fontWeightSemibold);
                color: var(--colorNeutralForeground1);
                width: 30%;
            }

            .field-value-SBS {
                color: var(--colorNeutralForeground1);
            }

            .error-message-SBS {
                color: var(--colorDangerBackground);
                font-style: italic;
            }

            .setting-details-table-SBS pre {
                margin: 0;
                white-space: pre-wrap;
                word-wrap: break-word;
            }

            .setting-details-table-SBS code {
                display: block;
                padding: 12px;
                border-radius: 4px;
                max-height: 300px;
                overflow-y: auto;
                background-color: #f4f4f4;
            }

            .info-text-SBS {
                font-family: 'Segoe UI', sans-serif;
                font-size: 14px;
                color: var(--colorNeutralForeground1);
                margin-bottom: 16px;
                line-height: 20px;
            }

            .info-link-SBS {
                color: var(--colorBrandBackground);
                text-decoration: none;
            }

            .info-link-SBS:hover {
                text-decoration: underline;
            }

            .setting-details-scroll-container-SBS {
                max-height: 600px;
                overflow-y: auto;
                padding-right: 16px;
            }

            .info-text-SBS h4 {
                color: var(--colorNeutralForeground1);
                margin-top: 16px;
                margin-bottom: 8px;
                font-size: 14px;
                font-weight: var(--fontWeightSemibold);
            }

            .info-text-SBS p {
                margin-bottom: 12px;
                font-size: 14px;
            }

            .page-heading-SBS {
                font-family: 'Segoe UI', sans-serif;
                font-size: 24px;
                font-weight: 600;
                color: var(--colorNeutralForeground1);
                padding: 0;
                max-width: fit-content;
            }

            .controls-row-SBS {
                margin-top: 24px;
                max-width: fit-content;
            }

            .disable-enable-button {
                min-width: 80px;
                padding: 0 16px;
                height: 32px;
                color: var(--colorNeutralBackground1);
                border: none;
                border-radius: 4px;
                cursor: pointer;
                font-family: "Segoe UI", "Segoe UI Web (West European)", -apple-system, BlinkMacSystemFont, Roboto, "Helvetica Neue", sans-serif;
                font-size: 14px;
                font-weight: 600;
                -webkit-font-smoothing: antialiased;
                margin-top: 0px;
                transition: background-color 0.1s ease;
            }

            .disable-enable-button[data-state="active"] {
                background-color: #605e5c;
            }

            .disable-enable-button[data-state="active"]:hover {
                background-color: #4d4b49;
            }

            .disable-enable-button[data-state="inactive"] {
                background-color: #107c10;
            }

            .disable-enable-button[data-state="inactive"]:hover {
                background-color: #0b5a0b;
            }

            .field-wrapper-SBS {
                display: flex;
                flex-direction: column;
                margin-bottom: 20px;
            }

            .field-label-SBS {
                font-size: 14px;
                font-weight: var(--fontWeightSemibold);
                color: var(--colorNeutralForeground1);
                margin-bottom: 4px;
            }

            .field-input-name-SBS {
                height: 32px;
                padding: 0 8px;
                border: 1px solid var(--colorNeutralStroke1);
                border-radius: 4px;
                font-size: var(--fontSizeBase200);
                color: var(--colorNeutralForeground1);
                background-color: var(--colorNeutralBackground1);
                transition: all 0.1s ease;
            }

            .field-input-SBS:hover {
                border-color: var(--colorNeutralStrokeAccessible);
            }

            .field-input-SBS:focus {
                outline: none;
                border-color: var(--colorBrandStroke1);
                box-shadow: 0 0 0 1px var(--colorBrandStroke1);
            }

            .field-helper-text-SBS {
                font-size: var(--fontSizeBase100);
                color: var(--colorNeutralForeground3);
                margin-top: 4px;
            }

            .spinner-container-SBS {
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(255, 255, 255, 0.7);
                display: flex;
                justify-content: center;
                align-items: center;
                z-index: 9999;
            }

            .spinner-SBS {
                border: 4px solid rgba(0, 0, 0, 0.1);
                border-left-color: var(--colorBrandBackground);
                border-radius: 50%;
                width: 40px;
                height: 40px;
                animation: spin 1s linear infinite;
            }

            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }

            .spinner-label-SBS {
                margin-top: 10px;
                font-size: 16px;
                color: var(--colorNeutralForeground1);
                text-align: center;
            }

            .spinner-container-SBS {
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
            }
        `;
        document.head.appendChild(style);
    }

    // Method to load HighlightJS for syntax highlighting of JSON
    private loadHighlightJS(): Promise<void> {
        return new Promise((resolve, reject) => {
            const style = document.createElement('link');
            style.rel = 'stylesheet';
            style.href = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.7.0/styles/default.min.css';
            document.head.appendChild(style);

            const script = document.createElement('script');
            script.src = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.7.0/highlight.min.js';
            script.onload = () => {
                const jsonScript = document.createElement('script');
                jsonScript.src = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.7.0/languages/json.min.js';
                jsonScript.onload = () => resolve();
                jsonScript.onerror = reject;
                document.head.appendChild(jsonScript);
            };
            script.onerror = reject;
            document.head.appendChild(script);
        });
    }

    // Method to update the view
    public updateView(context: ComponentFramework.Context<IInputs>): void {
        // Existing update logic if any
        this.displaySettingDetails();
    }

    // Method to get the outputs
    public getOutputs(): IOutputs {
        return {
            ScheduleBoardSetting: this._selectedScheduleBoardSetting
        };
    }

    // Method to destroy the component
    public destroy(): void {
        this._scheduleBoardSettingDropdown.removeEventListener("change", this.onScheduleBoardSettingChange.bind(this));
    }
}