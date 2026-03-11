/**
 * SAMPLE CODE NOTICE
 * 
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import * as Views from "PosApi/Create/Views";
import ChatViewModel from "./ChatViewModel";
import { ObjectExtensions } from "PosApi/TypeExtensions";
import { renderChatComponent} from "reactcomponents";

export default class ChatView extends Views.CustomViewControllerBase {
    public readonly viewModel: ChatViewModel;

    constructor(context: Views.ICustomViewControllerContext) {
        let config: Views.ICustomViewControllerConfiguration = {
            title: context.resources.getString("Chat"),
           
        };

        super(context, config);
        this.viewModel = new ChatViewModel(context);
    }

    public dispose(): void {
        ObjectExtensions.disposeAllProperties(this);
    }

    public onReady(element: HTMLElement): void {
        let chatSideCarElem: HTMLDivElement = document.getElementById("chatcomponent") as HTMLDivElement;
        renderChatComponent(chatSideCarElem, { OnSend: this.viewModel.OnSend.bind(this.viewModel) });

    }
}
