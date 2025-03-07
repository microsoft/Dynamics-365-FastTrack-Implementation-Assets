import { ISpinnerStyleProps, ISpinnerStyles } from "@fluentui/react";

export const SpinnerHelper = {
    spinnerStyles: (_spinnerStyleProps: ISpinnerStyleProps): ISpinnerStyles => {
        return {
            root: {
                height: "148px",
                width: "148px",
                backgroundColor: "rgba(51, 51, 51, 0.9)",
                position: "absolute",
                top: "50%",
                left: "50%",
                marginRight: "-50%",
                transform: "translate(-50%, -50%)",
                borderRadius: "4px"
            }
        };
    }
};
