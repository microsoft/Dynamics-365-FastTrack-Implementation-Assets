import { BookableResourceBookingFormIds, BookableResourceBookingQueryParameters, BookableResourceBookingTabNames, LocalizeConstants } from "../common/Constants";
import { LogType, ReportPreviewUtils } from "../common/ReportPreviewUtils";

import { Localization } from "./Localization";

/**
 * The options for app notification types.
 */
const enum AppNotificationType {
    /**
     * Toast notification type.
     */
    toast = 1,
    /**
     * Persistent Message Bar notification type.
     */
    messageBar = 2,
}

export class SaveReportToastNotificationService {
    private readonly localization: Localization;
    private currentNotificationId: string = null;

    /**
     * @param resources control resources.
     * @param bookingId id of the related booking record.
     */
    constructor(resources: ComponentFramework.Resources, private readonly bookingId: string) {
        this.localization = new Localization(resources);
    }

    /**
     * Clears notification
     */
    public async ClearNotificationAsync(): Promise<void> {
        if (this.currentNotificationId) {
            await Xrm.App.clearGlobalNotification(this.currentNotificationId);
            this.currentNotificationId = null;
        }
    }

    /**
     * Adds toast notification
     */
    public async AddNotificationAsync(): Promise<void> {
        await this.ClearNotificationAsync();

        const successfullySavedNotificationOptions: Xrm.App.Notification = {
            type: AppNotificationType.toast,
            level: XrmEnum.AppNotificationLevel.Success,
            message: this.localization.getString(LocalizeConstants.reportWasSuccessfullySaved),
            action: {
                actionLabel: this.localization.getString(LocalizeConstants.goToTimeline),
                eventHandler: () => this.handleNotificationActionAsync(),
            }
        };

        this.currentNotificationId = await Xrm.App.addGlobalNotification(successfullySavedNotificationOptions);
    }

    private async handleNotificationActionAsync(): Promise<void> {
        try {
            await Xrm.Navigation.openForm({
                entityName: "bookableresourcebooking",
                entityId: this.bookingId,
                formId: BookableResourceBookingFormIds.BookingAndWorkOrder,
            }, {[BookableResourceBookingQueryParameters.focusTabName]: BookableResourceBookingTabNames.notes});
        } catch (error) {
            ReportPreviewUtils.LogMessageInConsole(error, LogType.Error);
            return;
        }

        await this.ClearNotificationAsync();
    }
}
