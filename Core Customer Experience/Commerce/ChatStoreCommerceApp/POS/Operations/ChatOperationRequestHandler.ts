/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import { ExtensionOperationRequestType, ExtensionOperationRequestHandlerBase } from "PosApi/Create/Operations";
import ChatOperationResponse from "./ChatOperationResponse";
import ChatOperationRequest from "./ChatOperationRequest";
import { ClientEntities } from "PosApi/Entities";

/**
 * (Sample) Request handler for the ChatOperationRequest class.
 */
export default class ChatOperationRequestHandler extends ExtensionOperationRequestHandlerBase<ChatOperationResponse> {
    /**
     * Gets the supported request type.
     * @return {RequestType<TResponse>} The supported request type.
     */
    public supportedRequestType(): ExtensionOperationRequestType<ChatOperationResponse> {
        return ChatOperationRequest;
    }

    /**
     * Executes the request handler asynchronously.
     * @param {ChatOperationRequest<TResponse>} request The request.
     * @return {Promise<ICancelableDataResult<TResponse>>} The cancelable async result containing the response.
     */
    public async executeAsync(request: ChatOperationRequest<ChatOperationResponse>): Promise<ClientEntities.ICancelableDataResult<ChatOperationResponse>> {

        this.context.logger.logInformational("Log message from ChatOperationRequestHandler executeAsync().", this.context.logger.getNewCorrelationId());

        let response: ChatOperationResponse = new ChatOperationResponse();
        this.context.navigator.navigate("ChatView");
        return {
            canceled: false,
            data: response
        };
    }
}