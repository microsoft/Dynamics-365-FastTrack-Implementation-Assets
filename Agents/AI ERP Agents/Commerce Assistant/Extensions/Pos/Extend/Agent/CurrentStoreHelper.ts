/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

/**
 * Reads the associate's store: its number, name and channel, and where it is.
 *
 * The agent is told which store the associate is in, so that it checks stock there and looks for the
 * closest other store around it rather than guessing, and POS labels the stock the agent reports with
 * the store's own name.
 */

import { IExtensionContext } from "PosApi/Framework/ExtensionContext";
import { ClientEntities, ProxyEntities } from "PosApi/Entities";
import {
    GetDeviceConfigurationClientRequest,
    GetDeviceConfigurationClientResponse
} from "PosApi/Consume/Device";
import {
    GetCurrentProductCatalogStoreClientRequest,
    GetCurrentProductCatalogStoreClientResponse
} from "PosApi/Consume/Products";
import { IAgentStoreContext } from "ContosoSideChat";

/** Coordinates are sent to four decimal places, about 11 metres, which is plenty to find nearby stores. */
const COORDINATE_SCALE: number = 10000;

/**
 * Reads the associate's store.
 * @param context The POS extension context.
 * @param correlationId The correlation identifier for logging.
 * @returns The store, or undefined when POS cannot say which store it is.
 */
export async function getCurrentStoreAsync(
    context: IExtensionContext,
    correlationId?: string
): Promise<IAgentStoreContext | undefined> {
    try {
        const deviceResult: ClientEntities.ICancelableDataResult<GetDeviceConfigurationClientResponse> =
            await context.runtime.executeAsync(
                new GetDeviceConfigurationClientRequest<GetDeviceConfigurationClientResponse>(correlationId));
        const device: ProxyEntities.DeviceConfiguration | undefined =
            deviceResult.canceled ? undefined : deviceResult.data?.result;
        const storeNumber: string = readText(device?.StoreNumber);
        if (storeNumber.length === 0) {
            return undefined;
        }

        const store: IAgentStoreContext = { number: storeNumber, name: storeNumber };
        const channelId: number | undefined = device?.ChannelId;
        if (isPositiveNumber(channelId)) {
            store.channelId = channelId;
        }

        // The product catalog store is the associate's own store unless they are browsing another
        // store's catalog, in which case its record belongs to that store and is not used.
        const catalogResult: ClientEntities.ICancelableDataResult<GetCurrentProductCatalogStoreClientResponse> =
            await context.runtime.executeAsync(
                new GetCurrentProductCatalogStoreClientRequest<GetCurrentProductCatalogStoreClientResponse>(correlationId));
        const orgUnit: ProxyEntities.OrgUnit | undefined = catalogResult.canceled ? undefined : catalogResult.data?.store;
        if (orgUnit && isSameStore(orgUnit, storeNumber, store.channelId)) {
            const name: string = readText(orgUnit.OrgUnitName);
            if (name.length > 0) {
                store.name = name;
            }

            // Commerce stores 0, 0 for a store without a location.
            if (isCoordinate(orgUnit.Latitude, 90) && isCoordinate(orgUnit.Longitude, 180)
                && (orgUnit.Latitude !== 0 || orgUnit.Longitude !== 0)) {
                store.latitude = Math.round(orgUnit.Latitude * COORDINATE_SCALE) / COORDINATE_SCALE;
                store.longitude = Math.round(orgUnit.Longitude * COORDINATE_SCALE) / COORDINATE_SCALE;
            }
        }

        return store;
    } catch (error) {
        context.logger.logInformational(
            `CurrentStoreHelper could not read the current store: ${JSON.stringify(error)}`, correlationId);
        return undefined;
    }
}

function isSameStore(orgUnit: ProxyEntities.OrgUnit, storeNumber: string, channelId: number | undefined): boolean {
    return readText(orgUnit.OrgUnitNumber).toLowerCase() === storeNumber.toLowerCase()
        || (channelId !== undefined && orgUnit.RecordId === channelId);
}

function readText(value: string | undefined): string {
    return typeof value === "string" ? value.trim() : "";
}

function isPositiveNumber(value: number | undefined): value is number {
    return typeof value === "number" && isFinite(value) && value > 0;
}

function isCoordinate(value: number | undefined, limit: number): value is number {
    return typeof value === "number" && isFinite(value) && Math.abs(value) <= limit;
}
