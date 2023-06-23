import * as React from 'react';
import { ITextFieldStyles, MaskedTextField, TextField } from '@fluentui/react/lib/TextField';
import { IStackStyles, Stack } from '@fluentui/react/lib/Stack';
import { ILabelStyles, Label } from '@fluentui/react/lib/Label';
import { IconButton } from '@fluentui/react/lib/Button';
import { initializeIcons } from '@fluentui/react/lib/Icons';
import { parsePhoneNumberWithError } from 'libphonenumber-js';
import { CountrySetting, CountrySettings } from '../Classes/CountrySetting';

initializeIcons();

const stackTokens = { childrenGap: 20 };

export interface IPhoneNumberInputControlProps {
    phone?: string;    
    disabled: boolean;
    onValueChanged: (newValue?: string) => void;
    formatPhoneNumber: (phone: string) => string;   
    onCallClicked: () => void;  
    showButton: boolean;   
}

interface IPhoneNumberInputControlState {
    phoneNumber?: string;   
}

const getState = (phone: string): IPhoneNumberInputControlState => {

    let newState = {
        phoneNumber: phone
       
    };

    return newState;
}

export class PhoneNumberInputControl extends React.Component<IPhoneNumberInputControlProps, IPhoneNumberInputControlState> {

    constructor(props: IPhoneNumberInputControlProps) {
        super(props);

        const { phone } = props;

        this.state = getState(phone ?? '')
    }

    render() {
        const { phoneNumber } = this.state;

        const outterStack: IStackStyles = {
            root: {
                flexWrap: "wrap",
            },
        };

        return (
            <Stack horizontal styles={outterStack} tokens={{ childrenGap: 5 }} >
                <TextField
                    defaultValue={phoneNumber}
                    value={phoneNumber}
                    disabled={this.props.disabled}
                    styles={phoneFieldStyle}
                    onChange={(e: any, newValue?: string) => {
                        const safeValue = newValue?.replace(/[_]/g, '') ?? '';

                        this.setState({
                            phoneNumber: this.props.formatPhoneNumber(safeValue)
                        });
                    }}
                    onBlur={() => {
                        this.props.onValueChanged(this.state.phoneNumber ?? '');
                    }}
                    onRenderSuffix={() => {
                        return (
                            !this.props.showButton ? null :
                                <Stack horizontal>
                                    <IconButton
                                        iconProps={{
                                            iconName: "Phone"
                                        }}
                                        onClick={this.props.onCallClicked}
                                    />                                   
                                </Stack>);
                    }}
                />
               
            </Stack>);
    }

    componentDidUpdate(prevProps: IPhoneNumberInputControlProps, prevState: IPhoneNumberInputControlState) {
        const { phone } = this.props;

        if (prevProps.phone !== phone) {
            if (this.props.phone !== this.state.phoneNumber) {

                const newState = getState(phone ?? '')

                this.setState(newState);
            }
        }
    }
}

const labelStyle: Partial<ILabelStyles> = {
    root: {
        marginTop: "3px"
    }
}

const phoneFieldStyle = (): Partial<ITextFieldStyles> => {
    return commonFieldStyles('150px')
}

const extensionFieldStyle = (): Partial<ITextFieldStyles> => {
    return commonFieldStyles('40px')
}

const commonFieldStyles = (minWidth: string): Partial<ITextFieldStyles> => {
    const defaultStyles = textFieldStyle();

    if (!minWidth) return defaultStyles;

    const { root } = defaultStyles;

    const safeRoot = {
        ...(typeof root === 'object' ? root : {}),
        minWidth
    };

    const newStyle = {
        ...defaultStyles,
        root: { ...safeRoot }
    };

    return (newStyle);
}

const textFieldStyle = (): Partial<ITextFieldStyles> => ({
    ...({
        fieldGroup: {
            border: "none",
            selectors: {
                ":after": {
                    border: "none"
                }
            }
        },
        field: {
            fontWeight: 600,
            fontFamily: "SegoeUI,'Segoe UI'"
        },
        suffix: {
            backgroundColor: "#FFFFFF",
            padding: "0px"
        },
        prefix: {
            backgroundColor: "#FFFFFF",
            padding: "0px"
        }
    })
});