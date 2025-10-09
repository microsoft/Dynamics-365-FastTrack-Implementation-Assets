/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
import React, { useState, useRef, useEffect, KeyboardEvent, ChangeEvent } from "react";
import { chatStyles } from "./ChatStyles";
import { IViewModelChat } from "./IViewModelChat";
import { FluentProvider,webLightTheme } from "@fluentui/react-components";
import { IMessage } from "./IMessage";
import { ChatHeader } from "./ChatHeader";
import { ChatMessages } from "./ChatMessages";
import { ChatInput } from "./ChatInput";
import { v4 as uuidv4 } from "uuid";

export const ChatComponent: React.FC<IViewModelChat> = ({ OnSend } ) => {
  const [messages, setMessages] = useState<IMessage[]>([
    { id: uuidv4(), text: "Hello! Welcome to the chat.", role: "assistant" },
    { id: uuidv4(), text: "How can I assist you today?", role: "assistant" },
  ]);
  const [inputValue, setInputValue] = useState<string>("");
  const messagesEndRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const sendMessage = async (): Promise<void> => {
    const trimmed = inputValue.trim();
    if (!trimmed) return;

    const userMessage: IMessage = { id: uuidv4(), role: "user", text: trimmed };
    setMessages((prev) => [...prev, userMessage]);
    setInputValue("");

     // Add a loading message
    const loadingId = uuidv4();
    setMessages((prev) => [
        ...prev,
        { id: loadingId, role: "assistant", text: "..." },
      ]);

    try {
    if (OnSend) {
      const response = await OnSend(trimmed);
      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === loadingId
            ? { ...msg, text: response || "No response." }
            : msg
        )
      );
    }
    } catch (error) {
      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === loadingId
            ? { ...msg, text: "Error: Could not get response." }
            : msg
        )
      );
    }
  };

  const onInputKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>): void => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  const onInputChange = (e: ChangeEvent<HTMLTextAreaElement>): void => {
    setInputValue(e.target.value);
  };

  // Render the chat component
  return (
    <FluentProvider theme={webLightTheme}>
      <ChatHeader />
      <div style={chatStyles.chatContainer}>
        <ChatMessages messages={messages} messagesEndRef={messagesEndRef} />
        <ChatInput
          inputValue={inputValue}
          onInputChange={onInputChange}
          onInputKeyDown={onInputKeyDown}
          sendMessage={sendMessage}
        />
      </div>
    </FluentProvider>);
};

