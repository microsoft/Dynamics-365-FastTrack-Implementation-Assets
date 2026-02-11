/*! WARNING! Do not update this file manually! Manual update of this file is not supported and will likely lead to issues. In addition, future solution upgrades wont apply to manually edited files. */

module FieldServiceReporting {
    "use strict"
    export class BookableResourceBookingLibrary {
        private FormContext: Xrm.FormContext = null;
        private IsOnLoadExecuted: boolean = false;
        private reportingFormId: string = "32a79486-b187-4ab6-a6fe-f22a88b63261";
        private reportingFormName: string = "reporting";
        private static TelemetryComponentName = "FSReportingLibrary";

        public Load(executionContext: Xrm.Events.EventContext): void {
            // Since OnLoad will be fired after first saving without page reloading we should check this
            if (!this.IsOnLoadExecuted) {
                this.FormContext = executionContext.getFormContext();
                this.OnLoad();
                this.IsOnLoadExecuted = true;
            }
        }

        private OnLoad(): void {
            this.handleTabFocus();
        }

        /**
         * Gets tab name from query parameters and sets focus on it.
         * Handles changing tab focus if there is a parameter passed from navigateTo or openForm method.
         */
        private handleTabFocus(): void {
            const formContext = this.FormContext as any;
            const queryParameters = formContext && formContext.context && formContext.context.getQueryStringParameters();
            const focusTabName: string = queryParameters && queryParameters[BookableResourceBookingQueryParameters.focusTabName];
            if (focusTabName) {
                const tab = this.FormContext.ui.tabs.get(focusTabName);
                if (tab) {
                    tab.setFocus();
                }
            }
        }

        public ReportLoad(executionContext: Xrm.Events.EventContext): void {
            let formContext = executionContext.getFormContext();
            formContext && (formContext.ui.headerSection as any).setTabNavigatorVisible(false);
            let reportview = Xrm.Page.getAttribute("o25fs_reportview");
            if (reportview && reportview.getValue()) {
                reportview.setValue("");
            }
        }

        public open() {
            const bookingID = Xrm.Page.data.entity.getId();
            const pageInput = {
                pageType: "entityrecord",
                entityName: "bookableresourcebooking",
                formId: this.reportingFormId,
                entityId: bookingID,
            };

            Xrm.Navigation.openForm(pageInput).then(
                function success() {
                    console.log("Loaded Report View");
                },
                function error(err) {
                    console.log("Error loading Report View ", err);
                }
            );
        }

        public isReportForm() {
            const currentItem = Xrm.Page.ui.formSelector.getCurrentItem();
            // const formName = currentItem.getLabel().toLowerCase();
            const formId = currentItem.getId().toLowerCase();
            return formId === this.reportingFormId;
        }

        public saveReport(executionContext: Xrm.Events.EventContext) {
            let formContext: any = executionContext;
            if (typeof executionContext.getFormContext === "function") {
                formContext = executionContext.getFormContext();
            }
            if (formContext && formContext.data) {
                formContext.data.save().then(() => {
                    formContext.getAttribute("o25fs_reportview").setValue("save");
                }).catch((error: any) => {
                    console.error("Error saving report", error);
                });
            }
        }

    }

    enum BookableResourceBookingQueryParameters {
        focusTabName = "parameter_focusTabName"
    }
}
