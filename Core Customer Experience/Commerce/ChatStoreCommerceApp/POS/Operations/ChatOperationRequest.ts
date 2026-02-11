/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import { ExtensionOperationRequestBase } from "PosApi/Create/Operations";
import ChatOperationResponse from "./ChatOperationResponse";

/**
 * (Sample) Operation request for printing a message to console.
 */
export default class ChatOperationRequest<TResponse extends ChatOperationResponse> extends ExtensionOperationRequestBase<TResponse> {

    constructor(correlationId: string) {
        super(5000, correlationId);
    }
}