# Logging JMeter Test Results Into Azure App Insights

1. Make the plugin `Azure backend Listener` available by updating the [Dockerfile](../docker/Dockerfile) with code snippet below:

```docker
# Azure backend Listener plugin
 ENV AZURE_BACKEND_LISTENER_PLUGIN_VERSION=0.2.2
 RUN wget https://jmeter-plugins.org/files/packages/jmeter.backendlistener.azure-${AZURE_BACKEND_LISTENER_PLUGIN_VERSION}.zip
 RUN unzip -o jmeter.backendlistener.azure-${AZURE_BACKEND_LISTENER_PLUGIN_VERSION}.zip -d ${JMETER_HOME}
```

2. Update [sample.jmx](../jmeter/sample.jmx) by adding the required Azure backend listener plugin  and providing required application insights instrumentation key. The instructions on how to do that can be found [here](https://techcommunity.microsoft.com/t5/azure-global/send-your-jmeter-test-results-to-azure-application-insights/ba-p/1195320).

> Turning on Live Metrics within this plugin has serious performance impact on controller instance if the solution is being used for larger infrastructures. 
