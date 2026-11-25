/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import * as Triggers from "PosApi/Extend/Triggers/ApplicationTriggers";
import { showSideChatPanel } from "./SideChatPanelHost";

/**
 * Shows the docked chat side panel once an operator has signed in.
 *
 * PostLogOn rather than ApplicationStart on purpose. ApplicationStart runs during application load,
 * before the content host has rendered and before anyone has signed in, so mounting there would put
 * the panel on the activation and sign-in screens and would race the shell DOM. By the time this
 * trigger runs the shell exists and there is an operator, which is also when the panel is useful.
 *
 * The panel is collapsed to a small launcher button until the operator opens it, so it costs almost
 * no screen space on the views it now appears over.
 */
export default class ShowSideChatPanelPostLogOnTrigger extends Triggers.PostLogOnTrigger {
    /**
     * Executes the trigger functionality.
     * @param {Triggers.IPostLogOnTriggerOptions} options The options provided to the trigger.
     * @returns {Promise<void>} A promise resolved once the panel has been shown.
     */
    public execute(options: Triggers.IPostLogOnTriggerOptions): Promise<void> {
        void options;

        try {
            showSideChatPanel(this.context);
        } catch (error) {
            // Never let a decorative panel block sign-in.
            this.context.logger.logError("Failed to show the Copilot side panel: " + JSON.stringify(error));
        }

        return Promise.resolve();
    }
}
