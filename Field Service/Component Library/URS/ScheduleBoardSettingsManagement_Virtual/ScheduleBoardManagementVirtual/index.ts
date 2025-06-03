import { IInputs, IOutputs } from "./generated/ManifestTypes";
import * as React from 'react';
import { ScheduleBoardManagement } from "./ScheduleBoardManagement";

export class ScheduleBoardManagementVirtual implements ComponentFramework.ReactControl<IInputs, IOutputs> {
    private context: ComponentFramework.Context<IInputs>;
    private notifyOutputChanged: () => void;
    private selectedScheduleBoardSetting: string = "";

    public init(
        context: ComponentFramework.Context<IInputs>,
        notifyOutputChanged: () => void,
        state: ComponentFramework.Dictionary
    ): void {
        this.context = context;
        this.notifyOutputChanged = notifyOutputChanged;
    }

    public updateView(context: ComponentFramework.Context<IInputs>): React.ReactElement {
        return React.createElement(
            ScheduleBoardManagement,
            {
                context: this.context,
                notifyOutputChanged: this.notifyOutputChanged,
                onSettingSelected: (settingId: string) => {
                    this.selectedScheduleBoardSetting = settingId;
                    this.notifyOutputChanged();
                }
            }
        );
    }

    public getOutputs(): IOutputs {
        return {
            ScheduleBoardSetting: this.selectedScheduleBoardSetting
        };
    }

    public destroy(): void {
        // No cleanup required
    }
}