/*
*This is auto generated from the ControlManifest.Input.xml file
*/

// Define IInputs and IOutputs Type. They should match with ControlManifest.
export interface IInputs {
    ReportView: ComponentFramework.PropertyTypes.StringProperty;
    WorkOrder: ComponentFramework.PropertyTypes.LookupProperty;
    BookingId: ComponentFramework.PropertyTypes.StringProperty;
    Signature: ComponentFramework.PropertyTypes.StringProperty;
}
export interface IOutputs {
    ReportView?: string;
    WorkOrder?: ComponentFramework.LookupValue[];
    BookingId?: string;
    Signature?: string;
}
