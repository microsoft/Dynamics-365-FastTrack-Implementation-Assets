/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */

import { Button } from "@fluentui/react-components";
import { Send16Regular } from "@fluentui/react-icons";
import React from "react";
import { chatStyles } from "./ChatStyles";

interface IChatInputProps{
  inputValue: string;
  onInputChange: React.ChangeEventHandler<HTMLTextAreaElement>;
  onInputKeyDown: React.KeyboardEventHandler<HTMLTextAreaElement>;
  sendMessage: () => void;
};

export const ChatInput: React.FC<IChatInputProps> = ({ inputValue, onInputChange, onInputKeyDown, sendMessage }) => (
  <div style={chatStyles.inputArea}>
    <textarea
      rows={1}
      style={chatStyles.input}
      placeholder="Type a message..."
      value={inputValue}
      onChange={onInputChange}
      onKeyDown={onInputKeyDown}
    />
    <Button onClick={sendMessage} appearance="primary">
      <Send16Regular />
    </Button>
  </div>
);
