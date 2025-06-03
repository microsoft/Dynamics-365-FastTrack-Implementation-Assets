import { IInputs } from "../generated/ManifestTypes";

/**
 * Definitions for the data types being used in the report.
 * You can create your own types here and add them to ReportViewerProps to include them in your custom report.
 */
export class Booking {
    name: string;
    starttime: string;
    endtime: string;
    duration: number;
    resourcename: string;
    formattedStarttime: string;
    formattedEndtime: string;
}

export class ServiceInfo{
    name: string;
    accountid: string;
    address1_composite: string;
    telephone1: string;
    incident: string;
}

export class Product {
    msdyn_workorderproductid: string;
    msdyn_name: string;
    msdyn_description: string;
    msdyn_estimatequantity: number;
    msdyn_quantity: number;
    msdyn_totalamount: number;
}

export class ServiceTask {
    msdyn_workorderservicetaskid: string;
    msdyn_name: string;
    msdyn_description: string;
    msdyn_actualduration: number;
}

export class Service {
    msdyn_workorderserviceid: string;
    msdyn_name: string;
    msdyn_description: string;
}

export interface ReportViewerProps {
    booking: Booking;
    serviceInfo: ServiceInfo;
    context: ComponentFramework.Context<IInputs>;
    products: Array<Product>;                       // If multiple records will be fetched, you can create an Array of that type.
                                                    // The sample report displays a list of products so I create an Array of Products
    servicetasks: Array<ServiceTask>;
    services: Array<Service>;
    signature: string;
    isSpinnerVisible: boolean;
}
