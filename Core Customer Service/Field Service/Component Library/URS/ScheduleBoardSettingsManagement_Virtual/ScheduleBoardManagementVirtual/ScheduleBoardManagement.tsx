import * as React from 'react';
import { InfoLabel, Tooltip, FluentProvider, webLightTheme } from "@fluentui/react-components";
import hljs from 'highlight.js';
import { IInputs } from "./generated/ManifestTypes";
import './ScheduleBoardManagement.css';

export interface ScheduleBoardSetting {
    msdyn_scheduleboardsettingid: string;
    msdyn_tabname: string;
    statecode?: number;
    [key: string]: string | number | boolean | undefined;
}

interface ScheduleBoardManagementProps {
    context: ComponentFramework.Context<IInputs>;
    notifyOutputChanged: () => void;
    onSettingSelected: (settingId: string) => void;
}

export const ScheduleBoardManagement: React.FC<ScheduleBoardManagementProps> = ({ context, notifyOutputChanged, onSettingSelected }) => {
    const [settings, setSettings] = React.useState<ScheduleBoardSetting[]>([]);
    const [selectedSetting, setSelectedSetting] = React.useState<string>("");
    const [settingDetails, setSettingDetails] = React.useState<ScheduleBoardSetting | null>(null);
    const [message, setMessage] = React.useState<{ text: string; isSuccess: boolean } | null>(null);
    const [isLoading, setIsLoading] = React.useState<boolean>(false);
    const [showCopyOverlay, setShowCopyOverlay] = React.useState<boolean>(false);
    const [showDeleteOverlay, setShowDeleteOverlay] = React.useState<boolean>(false);
    const [showDisableEnableOverlay, setShowDisableEnableOverlay] = React.useState<boolean>(false);
    const [newBoardName, setNewBoardName] = React.useState<string>("");

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

    React.useEffect(() => {
        fetchAndPopulateScheduleBoardSettings();
        loadHighlightJS();
    }, []);


    React.useEffect(() => {
        if (selectedSetting) {
            displaySettingDetails();
            loadHighlightJS();
        }
    }, [selectedSetting]);

    const fetchAndPopulateScheduleBoardSettings = async () => {
        setIsLoading(true);
        try {
            const fetchedSettings = await getScheduleBoardSettings();
            setSettings(fetchedSettings);
            if (fetchedSettings.length > 0) {
                setSelectedSetting(fetchedSettings[0].msdyn_scheduleboardsettingid);
                onSettingSelected(fetchedSettings[0].msdyn_scheduleboardsettingid);
            }
        } catch (error) {
            console.error("Error fetching schedule board settings:", error);
            showMessage("Error loading settings", false);
        }
        setIsLoading(false);
    };

    const getSystemViewName = async (viewId: string): Promise<string> => {
        try {
            const viewData = await context.webAPI.retrieveRecord("savedquery", viewId, "?$select=name");
            return viewData.name as string;
        } catch (error) {
            console.error("Error fetching view data: ", error);
            return "N/A";
        }
    };

    const getUserViewName = async (viewId: string): Promise<string> => {
        try {
            const viewData = await context.webAPI.retrieveRecord("userquery", viewId, "?$select=name");
            return viewData.name as string;
        } catch (error) {
            console.error("Error fetching view data: ", error);
            return "N/A";
        }
    };

    const getScheduleBoardSettings = async (): Promise<ScheduleBoardSetting[]> => {
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
            "msdyn_unscheduledwotooltipsviewid",
            "statecode",
            "statuscode"
        ].join(",");

        try {
            const response = await context.webAPI.retrieveMultipleRecords("msdyn_scheduleboardsetting", `?$select=${fields}&$orderby=msdyn_tabname asc`);
            return response.entities as ScheduleBoardSetting[];
        } catch (error) {
            console.error("Error fetching schedule board settings:", error);
            throw error;
        }
    };

    const displaySettingDetails = React.useCallback(async () => {
        if (!selectedSetting) {
            setSettingDetails(null);
            return;
        }

        try {
            const setting = await context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", selectedSetting);
            const settingWithViewNames = { ...setting };

            for (const { key } of fieldsToDisplay) {
                if ((key.includes('viewid') || key.includes('msdyn_scheduleralertsview') || key.includes('msdyn_schedulerresourcetooltipview') || key.includes('msdyn_schedulerresourcedetailsview')) && setting[key] != null) {
                    const viewId = setting[key] as string;
                    try {
                        let viewName = await getSystemViewName(viewId);
                        if (!viewName) {
                            viewName = await getUserViewName(viewId);
                        }
                        settingWithViewNames[key] = `${viewId} (${viewName})`;
                    } catch (error) {
                        console.error("Error fetching view data:", error);
                        settingWithViewNames[key] = `${viewId} (Error getting view name)`;
                    }
                }
            }

            setSettingDetails(settingWithViewNames as ScheduleBoardSetting);

            // Update the disable/enable button
            const disableEnableButton = document.querySelector('.disable-enable-button') as HTMLButtonElement;
            if (disableEnableButton) {
                if (setting.statecode === 0) {
                    disableEnableButton.textContent = "Disable Board";
                    disableEnableButton.setAttribute('data-state', 'active');
                } else {
                    disableEnableButton.textContent = "Enable Board";
                    disableEnableButton.setAttribute('data-state', 'inactive');
                }
            }

            // Remove previous highlighting
            document.querySelectorAll('pre code.json').forEach((block) => {
                block.textContent = block.textContent || '';
                block.removeAttribute('data-highlighted');
            });

            // Re-apply syntax highlighting
            setTimeout(() => {
                document.querySelectorAll('pre code.json').forEach((block) => {
                    hljs.highlightElement(block as HTMLElement);
                });
            }, 0);

        } catch (error) {
            console.error("Error fetching Schedule Board Setting details:", error);
            showMessage("Error loading Schedule Board Setting details.", false);
        }
    }, [selectedSetting, context.webAPI, fieldsToDisplay]);

    const onCopyButtonClick = () => {
        if (!selectedSetting) {
            showMessage("Please select a Schedule Board Setting to copy.", false);
            return;
        }
        setShowCopyOverlay(true);
    };

    const onDeleteButtonClick = () => {
        if (!selectedSetting) {
            showMessage("Please select a Schedule Board Setting to delete.", false);
            return;
        }
        setShowDeleteOverlay(true);
    };

    const onDisableEnableButtonClick = () => {
        if (!selectedSetting) {
            showMessage("Please select a Schedule Board Setting to disable/enable.", false);
            return;
        }
        setShowDisableEnableOverlay(true);
    };

    const onSubmitCopy = async () => {
        setShowCopyOverlay(false);
        setIsLoading(true);

        try {
            const originalSetting = await context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", selectedSetting) as ScheduleBoardSetting;
            const newSetting: Partial<ScheduleBoardSetting> = {};

            for (const key in originalSetting) {
                if (key.startsWith("msdyn_") && key !== "msdyn_scheduleboardsettingid") {
                    newSetting[key] = originalSetting[key];
                }
            }

            newSetting.msdyn_tabname = newBoardName;
            newSetting.msdyn_ordernumber = originalSetting.msdyn_ordernumber === null ? 0 : originalSetting.msdyn_ordernumber as number;
            newSetting.msdyn_sharetype = originalSetting.msdyn_sharetype === 192350003 ? 192350000 : originalSetting.msdyn_sharetype as number;

            await context.webAPI.createRecord("msdyn_scheduleboardsetting", newSetting);
            showMessage(`Schedule Board Setting "${newBoardName}" has been successfully created.`, true);
            fetchAndPopulateScheduleBoardSettings();
        } catch (error) {
            console.error("Error copying Schedule Board Setting:", error);
            showMessage("An error occurred while copying the Schedule Board Setting.", false);
        }

        setIsLoading(false);
    };

    const onSubmitDelete = async () => {
        setShowDeleteOverlay(false);
        setIsLoading(true);

        try {
            await context.webAPI.deleteRecord("msdyn_scheduleboardsetting", selectedSetting);
            showMessage("Schedule Board Setting has been successfully deleted.", true);
            fetchAndPopulateScheduleBoardSettings();
        } catch (error) {
            console.error("Error deleting Schedule Board Setting:", error);
            showMessage("An error occurred while deleting the Schedule Board Setting.", false);
        }

        setIsLoading(false);
    };

    const onSubmitDisableEnable = async () => {
        setShowDisableEnableOverlay(false);
        setIsLoading(true);

        try {
            const setting = await context.webAPI.retrieveRecord("msdyn_scheduleboardsetting", selectedSetting, "?$select=statecode");
            const currentStateCode = setting.statecode;

            const newState = {
                statecode: currentStateCode === 0 ? 1 : 0,
                statuscode: currentStateCode === 0 ? 2 : 1
            };

            await context.webAPI.updateRecord("msdyn_scheduleboardsetting", selectedSetting, newState);

            const action = currentStateCode === 0 ? "disabled" : "enabled";
            showMessage(`Schedule Board Setting has been successfully ${action}.`, true);
            fetchAndPopulateScheduleBoardSettings();
        } catch (error) {
            console.error("Error updating Schedule Board Setting:", error);
            showMessage("An error occurred while updating the Schedule Board Setting.", false);
        }

        setIsLoading(false);
    };

    const showMessage = (text: string, isSuccess: boolean) => {
        setMessage({ text, isSuccess });
        setTimeout(() => setMessage(null), 5000);
    };

    const loadHighlightJS = () => {
        const style = document.createElement('link');
        style.rel = 'stylesheet';
        style.href = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.7.0/styles/default.min.css';
        document.head.appendChild(style);

        const script = document.createElement('script');
        script.src = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.7.0/highlight.min.js';
        script.onload = () => {
            const jsonScript = document.createElement('script');
            jsonScript.src = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.7.0/languages/json.min.js';
            jsonScript.onload = () => {
                if (hljs && typeof hljs.highlightAll === 'function') {
                    hljs.highlightAll();
                }
            };
            document.head.appendChild(jsonScript);
        };
        document.head.appendChild(script);
    };

    React.useEffect(() => {
        if (settingDetails) {
            // Apply syntax highlighting to JSON fields
            loadHighlightJS();
            document.querySelectorAll('pre code.json').forEach((block) => {
                hljs.highlightElement(block as HTMLElement);
            });
        }
    }, [settingDetails]);

    const formatJSON = (value: string | number | boolean | null | undefined): string => {
        if (value === null || value === undefined) return 'N/A';
        if (typeof value === 'string') {
            try {
                const obj = JSON.parse(value);
                return JSON.stringify(obj, null, 2);
            } catch (e) {
                console.error("Error parsing JSON:", e);
                return value;
            }
        }
        return String(value);
    };

    return (
        <div className="wrapper-SBS">
            <h1 className="page-heading-SBS">Schedule Board Management</h1>
            <div className="controls-row-SBS">
                <div className="ms-TextField-SBS">
                    <h4 className="dropdown-label-SBS">
                        <InfoLabel
                            size="medium"
                            info={
                                React.createElement(React.Fragment, null,
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
                                )
                            }
                        >
                            Schedule Board
                        </InfoLabel>
                    </h4>

                    <div className="dropdown-wrapper-SBS">
                        <select
                            className="ms-Dropdown-SBS"
                            value={selectedSetting}
                            onChange={(e) => {
                                setSelectedSetting(e.target.value);
                                onSettingSelected(e.target.value);
                            }}
                        >
                            {settings.map((setting) => (
                                <option key={setting.msdyn_scheduleboardsettingid} value={setting.msdyn_scheduleboardsettingid}>
                                    {setting.msdyn_tabname}
                                </option>
                            ))}
                        </select>
                        <div className="button-container-SBS">
                            <FluentProvider theme={webLightTheme}>
                                <div className="open-in-new-tab-wrapper-SBS">
                                    <Tooltip content="Open Board form in new window" relationship="label" withArrow>
                                        <button
                                            className="open-in-new-tab-button-SBS"
                                            onClick={() => {
                                                if (selectedSetting) {
                                                    interface ContextWithPage extends ComponentFramework.Context<IInputs> {
                                                        page: {
                                                            getClientUrl(): string;
                                                        };
                                                    }
                                                    const baseUrl = (context as ContextWithPage).page.getClientUrl();
                                                    const url = `${baseUrl}/main.aspx?forceUCI=1&newWindow=true&pagetype=entityrecord&etn=msdyn_scheduleboardsetting&id=${selectedSetting}`;
                                                    window.open(url, "_blank");
                                                }
                                            }}
                                        >
                                            <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
                                                <path d="M9 2L13 2L13 6M13 2L7 8M6 3H3C2.44772 3 2 3.44772 2 4V13C2 13.5523 2.44772 14 3 14H12C12.5523 14 13 13.5523 13 13V10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                                            </svg>
                                        </button>
                                    </Tooltip>
                                </div>
                                <div className="refresh-button-wrapper-SBS">
                                    <Tooltip content="Refresh schedule board settings" relationship="label" withArrow>
                                        <button
                                            className="refresh-button-SBS"
                                            onClick={fetchAndPopulateScheduleBoardSettings}
                                        >
                                            <svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
                                                <path d="M14 8c0-3.31-2.69-6-6-6S2 4.69 2 8s2.69 6 6 6v-2c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4h-2l3 3 3-3h-2z" fill="currentColor" />
                                            </svg>
                                        </button>
                                    </Tooltip>
                                </div>
                            </FluentProvider>
                        </div>
                    </div>
                </div>
                <div>
                    <button className="ms-Button-SBS ms-Button--primary-SBS" onClick={onCopyButtonClick}>Copy Board</button>
                    <button className="ms-Button-SBS ms-Button--danger-SBS" onClick={onDeleteButtonClick}>Delete Board</button>
                    <button
                        className="ms-Button-SBS ms-Button--default-SBS disable-enable-button"
                        data-state={settingDetails?.statecode === 0 ? "active" : "inactive"}
                        onClick={onDisableEnableButtonClick}
                    >
                        {settingDetails?.statecode === 0 ? "Disable Board" : "Enable Board"}
                    </button>
                </div>
            </div>
            {message && (
                <div className={`ms-MessageBar-SBS ${message.isSuccess ? "ms-MessageBar--success-SBS" : "ms-MessageBar--error-SBS"}`}>
                    {message.text}
                </div>
            )}
            {settingDetails && (
                <div className="setting-details-container-SBS">
                    <h3>Schedule Board Setting Details</h3>
                    <p className="info-text-SBS">
                        Each Schedule Board Setting maps to a given field or JSON attribute within a given field.
                    </p>
                    <div className="setting-details-scroll-container-SBS">
                        <table className="setting-details-table-SBS">
                            <tbody>
                                {fieldsToDisplay.map(({ key, label }) => {
                                    const isDeprecated = label.toLowerCase().includes('deprecated');
                                    const rowClass = isDeprecated ? 'deprecated-field' : '';

                                    const value = settingDetails[key];
                                    let displayValue: React.ReactNode = value != null ? value : 'N/A';

                                    // Special handling for different field types
                                    if ((key.includes('msdyn_sharetype') || key.includes('_msdyn_filterlayout_value') || key.includes('msdyn_ispublic') || key.includes('msdyn_bookbasedon') || key.includes('msdyn_sapartiallyavailableicondefault') || key.includes('msdyn_mapviewtabplacement') || key.includes('msdyn_hidecancelled') || key.includes('msdyn_issynchronizeresources') || key.includes('msdyn_saunavailableicondefault') || key.includes('msdyn_saavailableicondefault')) && value != null) {
                                        const configurationData = `${key}@OData.Community.Display.V1.FormattedValue`;
                                        const configurationName = settingDetails[configurationData] || 'N/A';
                                        displayValue = `${value} (${configurationName})`;
                                    }

                                    else if (key === 'msdyn_settings' || key === 'msdyn_filtervalues') {
                                        displayValue = <pre><code className="json">{formatJSON(value)}</code></pre>;
                                    }

                                    else if (label.endsWith("Color") && typeof value === 'string') {

                                        const hexColor = value.startsWith('#') ? value : `#${value}`;

                                        if (/^#[0-9A-Fa-f]{6}$/.test(hexColor)) {
                                            displayValue = (
                                                <div style={{ display: 'flex', alignItems: 'center' }}>
                                                    <div style={{ width: '20px', height: '20px', backgroundColor: hexColor, border: '1px solid #ccc', marginRight: '10px' }}></div>
                                                    {value}
                                                </div>
                                            );
                                        }
                                    }

                                    return (
                                        <tr key={key} className={rowClass} style={{ display: isDeprecated ? 'none' : undefined }}>
                                            <td className="field-label-SBS">{label}:</td>
                                            <td className="field-value-SBS">{displayValue}</td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}
            {showCopyOverlay && (
                <div className="overlay-SBS" style={{ display: 'flex' }}>
                    <div className="overlay-content-SBS">
                        <div className="dialog-header-SBS">
                            <h2>Copy Schedule Board</h2>
                        </div>
                        <div className="dialog-body-SBS">
                            <div className="field-wrapper-SBS">
                                <label className="field-label-SBS" htmlFor="newBoardName">New Board Name:</label>
                                <input
                                    id="newBoardName"
                                    className="field-input-name-SBS"
                                    type="text"
                                    value={newBoardName}
                                    onChange={(e) => setNewBoardName(e.target.value)}
                                    placeholder="Enter new board name"
                                />
                            </div>
                        </div>
                        <div className="dialog-footer-SBS">
                            <button className="ms-Button-SBS ms-Button--default-SBS" onClick={() => setShowCopyOverlay(false)}>Cancel</button>
                            <button className="ms-Button-SBS ms-Button--primary-SBS" onClick={onSubmitCopy}>Submit</button>
                        </div>
                    </div>
                </div>
            )}
            {showDeleteOverlay && (
                <div className="overlay-SBS" style={{ display: 'flex' }}>
                    <div className="overlay-content-SBS">
                        <div className="dialog-header-SBS">
                            <h2>Confirm Deletion</h2>
                        </div>
                        <div className="dialog-body-SBS">
                            <p>Are you sure you want to delete this board?</p>
                        </div>
                        <div className="dialog-footer-SBS">
                            <button className="ms-Button-SBS ms-Button--default-SBS" onClick={() => setShowDeleteOverlay(false)}>Cancel</button>
                            <button className="ms-Button-SBS ms-Button--danger-SBS" onClick={onSubmitDelete}>Delete</button>
                        </div>
                    </div>
                </div>
            )}
            {showDisableEnableOverlay && (
                <div className="overlay-SBS" style={{ display: 'flex' }}>
                    <div className="overlay-content-SBS">
                        <div className="dialog-header-SBS">
                            <h2>Confirm Action</h2>
                        </div>
                        <div className="dialog-body-SBS">
                            <p>Are you sure you want to {settingDetails?.statecode === 0 ? "disable" : "enable"} this board?</p>
                        </div>
                        <div className="dialog-footer-SBS">
                            <button className="ms-Button-SBS ms-Button--default-SBS" onClick={() => setShowDisableEnableOverlay(false)}>Cancel</button>
                            <button className="ms-Button-SBS ms-Button--primary-SBS" onClick={onSubmitDisableEnable}>Confirm</button>
                        </div>
                    </div>
                </div>
            )}
            {isLoading && (
                <div className="spinner-container-SBS">
                    <div className="spinner-SBS"></div>
                    <div className="spinner-label-SBS">Processing...</div>
                </div>
            )}
        </div>
    );
};