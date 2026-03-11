import { IInputs } from "../generated/ManifestTypes";
import { Booking, Product, Service, ServiceInfo, ServiceTask } from "../models/ReportViewerModel";

/**
 * Provides methods to fetch various data. You can add your own data fetches here and call them from index.ts
 */
export class GetReportData {
    private bookingID: string;
    private workOrderID: string;

    constructor(private context: ComponentFramework.Context<IInputs>) {
        this.bookingID = context.parameters?.BookingId?.formatted;
        const workOrder = context.parameters?.WorkOrder?.raw;
        this.workOrderID = workOrder ? workOrder[0]?.id : undefined;
    }

    public getBookingData = async (): Promise<Booking> => {
        let booking;
        const data = await this.context.webAPI.retrieveRecord(
            "bookableresourcebooking",
            this.bookingID,
            "?$expand=Resource($select=name)"
        );

        if (data) {
            booking = {
                name: data.name,
                starttime: data.starttime,
                endtime: data.endtime,
                duration: data.duration,
                resourcename: data?.Resource?.name,
                formattedStarttime: data["starttime@OData.Community.Display.V1.FormattedValue"],
                formattedEndtime: data["endtime@OData.Community.Display.V1.FormattedValue"]
            };
        }

        return booking;
    };

    public getProducts = async (): Promise<Array<Product>> => {
        let products = [];
        if (!this.workOrderID) {
return products;
}

        const productData = await this.context.webAPI.retrieveRecord(
            "msdyn_workorder",
            this.workOrderID,
            "?$select=msdyn_workorderid&$expand=msdyn_msdyn_workorder_msdyn_workorderproduct_WorkOrder($select=msdyn_name,msdyn_description,msdyn_quantity,msdyn_estimatequantity,msdyn_workorderproductid)"
        );

        if (productData && productData.msdyn_msdyn_workorder_msdyn_workorderproduct_WorkOrder) {
            products = productData.msdyn_msdyn_workorder_msdyn_workorderproduct_WorkOrder;
            products = products.map((product) => ({
                msdyn_name: product.msdyn_name,
                msdyn_description: product.msdyn_description,
                msdyn_estimatequantity: product.msdyn_estimatequantity,
                msdyn_quantity: product.msdyn_quantity,
                msdyn_workorderproductid: product.msdyn_workorderproductid,
                msdyn_totalamount: product.msdyn_totalamount
            }));
        }
        return products;
    };

    public getServiceTasks = async (): Promise<Array<ServiceTask>> => {
        let tasks = [];
        if (!this.workOrderID) {
return tasks;
}

        const tasksData = await this.context.webAPI.retrieveRecord(
            "msdyn_workorder",
            this.workOrderID,
            "?$select=msdyn_workorderid&$expand=msdyn_msdyn_workorder_msdyn_workorderservicetask_WorkOrder($select=msdyn_name,msdyn_description,msdyn_workorderservicetaskid,msdyn_actualduration)"
        );

        if (tasksData && tasksData.msdyn_msdyn_workorder_msdyn_workorderservicetask_WorkOrder) {
            tasks = tasksData.msdyn_msdyn_workorder_msdyn_workorderservicetask_WorkOrder;
            tasks = tasks.map((task) => ({
                msdyn_name: task.msdyn_name,
                msdyn_description: task.msdyn_description,
                msdyn_workorderservicetaskid: task.msdyn_workorderservicetaskid,
                msdyn_actualduration: task.msdyn_actualduration
            }));
        }
        return tasks;
    };

    public getServices = async (): Promise<Array<Service>> => {
        let services = [];
        if (!this.workOrderID) {
return services;
}

        const serviceData = await this.context.webAPI.retrieveRecord(
            "msdyn_workorder",
            this.workOrderID,
            "?$select=msdyn_workorderid&$expand=msdyn_msdyn_workorder_msdyn_workorderservice_WorkOrder($select=msdyn_name,msdyn_description,msdyn_workorderserviceid)"
            // List any other fields you may want from the Work Order Service entity.
        );

        if (serviceData && serviceData.msdyn_msdyn_workorder_msdyn_workorderservice_WorkOrder) {
            services = serviceData.msdyn_msdyn_workorder_msdyn_workorderservice_WorkOrder;
            services = services.map((service) => ({

                // These names (e.g. msdyn_description) need to match the names you defined in ReportViewerModel
                msdyn_name: service.msdyn_name,
                msdyn_description: service.msdyn_description,
                msdyn_workorderserviceid: service.msdyn_workorderserviceid,
            }));
        }
        return services;
    };

    public getServiceInfo = async (): Promise<ServiceInfo> => {
        let serviceInfo;
        if (!this.workOrderID) {
return serviceInfo;
}
        const data = await this.context.webAPI.retrieveRecord(
            "msdyn_workorder",
            this.workOrderID,
            "?$select=msdyn_workorderid,msdyn_address1,_msdyn_serviceaccount_value,_msdyn_primaryincidenttype_value,modifiedon&$expand=msdyn_serviceaccount($select=accountid,name,address1_composite,telephone1)"
        );

        if (data && data.msdyn_serviceaccount) {
            const account = data.msdyn_serviceaccount;
            serviceInfo = {
                name: account.name,
                accountid: account.accountid,
                address1_composite: account.address1_composite,
                telephone1: account.telephone1,
                incident: data["_msdyn_primaryincidenttype_value@OData.Community.Display.V1.FormattedValue"]
            };
        }
        return serviceInfo;
    };
}
