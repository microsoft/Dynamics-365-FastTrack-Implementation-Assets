/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
 


import * as React from 'react';
import { ICaptchaViewProps } from './captcha';
import ReCAPTCHA from 'react-google-recaptcha';
import { CommerceProperty, CommercePropertyValue } from '@msdyn365-commerce/retail-proxy/dist/Entities/CommerceTypes.g';

export default (props: ICaptchaViewProps) => {
    // Add with your site key below.
    const captchaSiteKey = '';
    const handleCaptchaChange = async (token: string | null) => {
        if (token) {
            if (props.data.checkout?.result) {
                // save the token to cartState extension property
                const cartState = props.data.checkout.result.checkoutCart;
                const extensionProperties = cartState.extensionProperties ?? [];
                const allExtensionProperties = mergeExtensionProperty(extensionProperties, 'captchaToken', { StringValue: token });
                cartState.updateExtensionProperties({ newExtensionProperties: allExtensionProperties }).catch((error: string) => {
                    props.telemetry.error(error);
                });

                props.moduleState.onReady();
            } else {
                console.error('empty checkout result.');
            }
        }
    };

    return (
        <div className='captcha-module'>
            <ReCAPTCHA sitekey={captchaSiteKey} onChange={handleCaptchaChange} />
        </div>
    );
};

function mergeExtensionProperty(extensionProperties: CommerceProperty[], key: string, value: CommercePropertyValue): CommerceProperty[] {
    const index = extensionProperties.findIndex(prop => prop.Key === key);
    if (index >= 0) {
        extensionProperties[index].Value = value;
    } else {
        extensionProperties.push({ Key: key, Value: value });
    }
    return extensionProperties;
}
