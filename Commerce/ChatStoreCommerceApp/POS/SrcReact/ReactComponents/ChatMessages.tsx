/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
import { Avatar } from "@fluentui/react-components";
import { Bot32Regular, Person32Regular } from "@fluentui/react-icons";
import { MarkdownRenderer } from "./MarkdownRenderer"; 
import React from "react";
import { chatStyles } from "./ChatStyles";
import { IMessage } from "./IMessage";

interface IChatMessagesProps {
  messages: IMessage[];
  messagesEndRef: React.RefObject<HTMLDivElement>;
};

export const ChatMessages: React.FC<IChatMessagesProps> = ({ messages, messagesEndRef }) => (
  <div style={{...chatStyles.messagesContainer}}>
    {messages.map(({ id, role, text }) => (
      <div
        key={id}
        style={{
          ...chatStyles.messageRow,
          justifyContent: role === "user" ? "flex-end" : "flex-start",
          alignItems: "flex-end",
        }}
      >
        {role === "assistant" && (
          <Avatar icon={<Bot32Regular />} color="colorful" size={32} style={{ marginRight: 8 }} />
        )}
        <div style={role === "user" ? chatStyles.messageSent : chatStyles.messageReceived}>
          <MarkdownRenderer content={text} />
        </div>
        {role === "user" && (
          <Avatar icon={<Person32Regular />} color="brand" size={32} style={{ marginLeft: 8 }} />
        )}
      </div>
    ))}
    <div ref={messagesEndRef} />
  </div>
);
