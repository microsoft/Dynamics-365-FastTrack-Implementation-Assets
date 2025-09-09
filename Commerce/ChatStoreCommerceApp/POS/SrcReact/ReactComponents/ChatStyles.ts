/**
 * SAMPLE CODE NOTICE
 *
 * THIS SAMPLE CODE IS MADE AVAILABLE AS IS.  MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
 * OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
 * THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
 * NO TECHNICAL SUPPORT IS PROVIDED.  YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.
 */
export const chatStyles: Record<string, React.CSSProperties> = {
  chatHeader: {
    textAlign: "center",
  },
  chatContainer: {
    border: "1px solid #ddd",
    borderRadius: 4,
    backgroundColor: "#fff",
    fontSize: "14px",
    padding: 4,
    marginTop: "20px",
  },
  messagesContainer: {
    flex: 1,
    padding: 4,
  },
  messageRow: {
    display: "flex",
    marginBottom: 12,
  },
  messageSent: {
    marginRight: "15px",
    marginLeft: "5px",
    backgroundColor: "#0078D4",
    color: "#fff",
    padding: "2px 2px",
    borderRadius: 4,
    maxWidth: "70%",
    wordBreak: "break-word",
  },
  messageReceived: {
    marginLeft: "15px",
    marginRight: "5px",
    backgroundColor: "#E1DFDD",
    padding: "2px 2px",
    borderRadius: 4,
    maxWidth: "70%",
    wordBreak: "break-word",
  },
  inputArea: {
    padding: 4,
    borderTop: "1px solid #ddd",
    display: "flex",
  },
  input: {
    flexGrow: 1,
    padding: 4,
    fontSize: 14,
    borderRadius: 4,
    border: "1px solid #ccc",
    resize: "none",
  },
  button: {
    marginLeft: 8,
    padding: "4px 4px",
    fontSize: "20px",
    borderRadius: 4,
    border: "none",
    backgroundColor: "#0078D4",
    color: "white",
    cursor: "pointer",
  },
};
