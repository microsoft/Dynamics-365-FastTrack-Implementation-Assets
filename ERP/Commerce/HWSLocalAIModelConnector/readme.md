# Connecting Store Commerce App to a Local AI Model(Ollama-phi3:mini model) via Hardware Station

This guide explains how to connect the Dynamics 365 Store Commerce App to a local AI model Ollama(phi3:mini) using hardware station.

**phi3:mini** is a compact, efficient AI language model that can run locally on your hardware, enabling private and fast inference with offline. Local AI models like phi3:mini are hosted and executed on your own machine, providing greater control over data privacy and reducing latency. In this guide, we use [Ollama](https://ollama.com/) to manage and serve the phi3:mini model locally, allowing seamless integration with the Store Commerce App through Hardware Station.

## Why Use a Local AI Model?

Running an AI model locally offers several advantages:

- **Data Privacy:** All data stays on your machine, reducing exposure to external services and enhancing privacy.
- **Low Latency:** Local inference eliminates network delays, resulting in faster responses.
- **Offline Capability:** The model works even without an internet connection, ensuring reliability.
- **Customization:** You have full control over model updates, configurations, and integration with your environment.

---

## Mobile Compatibility

The phi3:mini model, when served via Ollama, can also be accessed from mobile platforms such as Android and iOS. By ensuring your mobile device is on the same network as the machine running Ollama, you can send requests to the local AI model using standard HTTP calls. This enables Store Commerce App scenarios on mobile devices to leverage local AI inference for privacy and low-latency responses, just as on desktop.

- Ensure network connectivity between your mobile device and the Ollama host.
- Use the host machine's IP address and Ollama port (e.g., `http://<host-ip>:11434`) in your mobile app's API requests.
- Both Android and iOS apps can integrate with the local AI model using standard HTTP libraries.

---

## Prerequisites

- **Dynamics 365 Commerce Store Commerce App** installed and configured.
- **Hardware Station** set up in your Store Commerce App.
- **Ollama**.
- **phi3:mini model** available in Ollama.

---

## Steps

### 1. Install Ollama

Download and install Ollama:

[Install Ollama](https://ollama.com/download)

### 2. Pull the phi3:mini Model

Open a terminal and run:

```sh
ollama pull phi3:mini
```

### 4. Run the Model Locally

You can Run the model with:

```sh
ollama run phi3:mini
```

By default, Ollama listens on `http://localhost:11434`.

### 5. Validate the Connection

- Ensure using command prompt the requests to `localhost:11434`.
- Example API call:

```sh
curl -Uri http://localhost:11434/api/chat `
  -Method POST `
  -Body '{ "model": "phi3:mini", "messages": [ {"role": "system", "content": "You are a helpful assistant."}, {"role": "user", "content": "Tell me a joke."} ] }' `
  -ContentType "application/json"

```

### 6. Add the Hardware Station Extension in Store Commerce App

Install the hardware station extension in StoreCommerce App. For more details on integrating a new hardware station extension and generating a installer please refer to

[Learn how to create and integrate a new hardware device extension in Dynamics 365 Commerce Hardware Station.](https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/hardware-device-extension)

### 7. Call the hardware station extension from Store Commerce App for Windows

```typescript
let aiRequest: { Message: string } = {
  Message: "Hello from another AI model!",
};
let localAIModelHWSRequest: HardwareStationDeviceActionRequest<HardwareStationDeviceActionResponse> =
  new HardwareStationDeviceActionRequest(
    "LocalAIModel",
    "SendMessage",
    aiRequest
  );

this.context.runtime
  .executeAsync(localAIModelHWSRequest)
  .then((airesponse) => {
    if (airesponse.data.response) {
      console.log(airesponse.data.response);
    }
    return Promise.resolve({
      canceled: false,
    });
  })
  .catch((reason: any) => {
    console.error("Error executing AI model:", reason);
    return Promise.reject(reason);
  });
```

---

## Troubleshooting

- **Port Issues:** Ensure port `11434` is open and not blocked by firewall.
- **Model Not Found:** Make sure `phi3:mini` is pulled and available in Ollama.
- **API Errors:** Check Ollama logs for error messages.

---

## References

- [Ollama Documentation](https://ollama.com/docs)
- [Dynamics 365 Commerce Documentation](https://learn.microsoft.com/dynamics365/commerce/)
- [Hardware Station Integration](https://learn.microsoft.com/en-us/dynamics365/commerce/dev-itpro/hardware-device-extension)
