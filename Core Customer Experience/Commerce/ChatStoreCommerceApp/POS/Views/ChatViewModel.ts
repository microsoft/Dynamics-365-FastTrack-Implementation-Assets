/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import { IExtensionViewControllerContext } from "PosApi/Create/Views";
import { Entities } from "../DataService/DataServiceEntities.g";
import * as Messages from "../DataService/DataServiceRequests.g";
import {GetCurrentCartClientRequest,GetCurrentCartClientResponse}from "PosApi/Consume/Cart"
import { ClientEntities } from "PosApi/Entities";
import { ProxyEntities } from "PosApi/Entities";

export default class ChatViewModel {
    public title: string;
    private _context: IExtensionViewControllerContext;

    constructor(context: IExtensionViewControllerContext) {
        this._context = context;
        this.title = context.resources.getString("Chat");
    }

    public load(): Promise<void> {
        return Promise.resolve();
    }

    public OnSend(userPrompt: string): Promise<string> {
        return this._context.runtime.executeAsync(new GetCurrentCartClientRequest())
            .then((cartResponse: ClientEntities.ICancelableDataResult<GetCurrentCartClientResponse>) => {
                const currentCart = cartResponse.data?.result;
                if (currentCart) {
                    this._context.logger.logInformational("Current cart retrieved successfully.");
                    return this._context.runtime.executeAsync(
                        new Messages.StoreOperations.GetChatResponseRequest(currentCart.Id, userPrompt, "")
                    ).then((chatResponse: ClientEntities.ICancelableDataResult<any>) => {
                        const airesponse = chatResponse.data?.result ?? "";
                        this._context.logger.logInformational("Chat response processed successfully.");
                        return airesponse;
                    }).catch((error: any) => {
                        this._context.logger.logError("Failed to get chat response.", error);
                        return "";
                    });
                } else {
                    this._context.logger.logError("No current cart found.");
                    return Promise.resolve("");
                }
            })
            .catch((error: any) => {
                this._context.logger.logError("Failed to get current cart.", error);
                return "";
            });
    }
}
