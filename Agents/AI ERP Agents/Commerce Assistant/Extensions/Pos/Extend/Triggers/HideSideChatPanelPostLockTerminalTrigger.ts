/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import * as Triggers from "PosApi/Extend/Triggers/ApplicationTriggers";
import { hideSideChatPanel } from "./SideChatPanelHost";

/**
 * Removes the docked chat side panel when the terminal is locked. The panel is restored by the
 * PostLogOn trigger when someone signs back in, so a locked terminal never shows a conversation.
 */
export default class HideSideChatPanelPostLockTerminalTrigger extends Triggers.PostLockTerminalTrigger {
    /**
     * Executes the trigger functionality.
     * @param {Triggers.IPostLockTerminalTriggerOptions} options The options provided to the trigger.
     * @returns {Promise<void>} A promise resolved once the panel has been removed.
     */
    public execute(options: Triggers.IPostLockTerminalTriggerOptions): Promise<void> {
        void options;

        try {
            hideSideChatPanel();
        } catch (error) {
            this.context.logger.logError("Failed to remove the Copilot side panel: " + JSON.stringify(error));
        }

        return Promise.resolve();
    }
}
