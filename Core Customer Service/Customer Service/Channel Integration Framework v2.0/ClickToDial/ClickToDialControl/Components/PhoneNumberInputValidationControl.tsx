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

export interface IPhoneNumberValidationInputControlProps {
    phone?: string;   
    disabled: boolean;
    onValueChanged: (newValue?: string) => void;  
    onCallClicked: () => void; 
    showButton: boolean;    
}

interface IPhoneNumberValidationInputControlState {
    selectedCountry?: CountrySetting;
    currentValue?: string;
    isValidPhoneNumber: boolean;
    phoneNumber?: string;   
}

interface IPhoneParsingResult {
    country?: CountrySetting,
    isValid: boolean
}

const unknownCountry: CountrySetting = {
    countryCode: "null",
    mask: "************",
    codeExtension: "+",
    country: "unknown"
};

const getCountryAndIsValid = (phone: string): IPhoneParsingResult => {
    let countryCode: CountrySetting | undefined;
    let isValidPhoneNumber: boolean = false;

    if (phone) {
        try {
            const phoneNumber = parsePhoneNumberWithError(phone);
            countryCode = CountrySettings.find(s => s.codeExtension.substring(1) === phoneNumber.countryCallingCode);
            isValidPhoneNumber = phoneNumber.isValid();
        } catch {
            console.log("Error Occured in Validation");
        }
    }

    return { country: countryCode, isValid: isValidPhoneNumber };
}

const getState = (phone: string): IPhoneNumberValidationInputControlState => {

    const parsingResult = getCountryAndIsValid(phone);

    let newState = {
        selectedCountry: parsingResult.country ?? unknownCountry,
        currentValue: phone,
        phoneNumber: '',
        isValidPhoneNumber: parsingResult.isValid,
      
    };

    return newState;
}

const TryFindCountryCode = (phone?: string): IPhoneParsingResult => {

    const parsingResult = getCountryAndIsValid(phone ?? '');

    if (!parsingResult.country) {
        parsingResult.country = CountrySettings.find(s => phone?.startsWith(s.codeExtension));
    }

    return { country: parsingResult.country ?? unknownCountry, isValid: parsingResult.isValid };
}


export class PhoneNumberValidationInputControl extends React.Component<IPhoneNumberValidationInputControlProps, IPhoneNumberValidationInputControlState> {

    constructor(props: IPhoneNumberValidationInputControlProps) {
        super(props);

        const { phone } = props;

        this.state = getState(phone ?? '')
    }

    render() {
        const { currentValue } = this.state;

        const maskFormat = {
            '*': /[0-9]/,
            '0': /0/,
            '1': /1/,
            '2': /2/,
            '3': /3/,
            '4': /4/,
            '5': /5/,
            '6': /6/,
            '7': /7/,
            '8': /8/,
            '9': /9/,
        };

        const outterStack: IStackStyles = {
            root: {
                flexWrap: "wrap",
            },
        };

        const isPhoneNumberValid = (): boolean => {
            const { phoneNumber, isValidPhoneNumber, selectedCountry, currentValue } = this.state

            if (!phoneNumber) return true;
            if (!selectedCountry && currentValue) return isValidPhoneNumber

            const phoneWithoutCountryCode = currentValue!.replace(((selectedCountry?.codeExtension) ?? ''), '').trim()

            return selectedCountry?.mask.length === phoneWithoutCountryCode.length ? true : isValidPhoneNumber
        }

        const compareCountries = (a: CountrySetting, b: CountrySetting): number => {
            if (a.default === true) return -1;
            if (b.default === true) return 1;
            
            if (a.country < b.country) {
                return -1;
            }

            if (a.country > b.country) {
                return 1;
            }

            return 0;
        }

        const numberWithoutMaskCharacters = (phone: string): string => {
           //// return phone.replace(/[\ \(\)_-]/g, '');
           return phone.replace(/[ ()_-]/g, '');
        }

        return (
            <Stack horizontal styles={outterStack} tokens={{ childrenGap: 5 }} >
                <MaskedTextField
                    defaultValue={currentValue}
                    value={currentValue}
                    disabled={this.props.disabled}
                    mask={`${this.state.selectedCountry?.codeExtension} ${this.state.selectedCountry?.mask}`}
                    maskChar={this.state.selectedCountry ? "_" : ''}
                    maskFormat={maskFormat}
                    styles={phoneFieldStyle}
                    errorMessage={isPhoneNumberValid() ? "" : 'Phone number is not correct.'}
                    onChange={(e: any, newValue?: string) => {
                        const safeValue = newValue?.replace(/[_]/g, '') ?? '';
                        const parseResult = TryFindCountryCode(numberWithoutMaskCharacters(safeValue!))

                        if (e.nativeEvent.inputType === "deleteContentBackward"
                            && numberWithoutMaskCharacters(safeValue!).length > 1) {
                            parseResult.country = this.state.selectedCountry;
                        }

                        this.setState({
                            currentValue: safeValue,
                            phoneNumber: numberWithoutMaskCharacters(safeValue).replace(parseResult.country?.codeExtension ?? '', ''),
                            isValidPhoneNumber: parseResult.isValid,
                            selectedCountry: parseResult.country
                        });
                    }}
                    onBlur={() => {
                        this.props.onValueChanged(this.state.phoneNumber === '' ? '' : numberWithoutMaskCharacters(currentValue!));
                    }}                    
                    onRenderPrefix={() => {
                        return (
                            <IconButton
                                iconProps={{
                                    imageProps: {
                                        className: this.state.selectedCountry ? `flag:${this.state.selectedCountry.countryCode}` : undefined
                                    }
                                }}
                                menuProps={{
                                    items: CountrySettings.sort(compareCountries).map(cs => {
                                        return {
                                            key: cs.countryCode,
                                            text: cs.country,
                                            iconProps: {
                                                imageProps: {
                                                    className: `flag:${cs.countryCode}`
                                                }
                                            },
                                            onClick: () => {
                                                this.setState({
                                                    selectedCountry: cs,
                                                    phoneNumber: cs.codeExtension,
                                                    currentValue: cs.codeExtension
                                                });

                                                this.props.onValueChanged(cs.codeExtension)
                                            }
                                        }
                                    })
                                }}
                            />);
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

    componentDidUpdate(prevProps: IPhoneNumberValidationInputControlProps, prevState: IPhoneNumberValidationInputControlState) {
        const { phone } = this.props;

        if (prevProps.phone !== phone) {
            if (this.props.phone !== this.state.currentValue) {

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