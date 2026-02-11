# Implementation Notes

## Repository structure

| Folder    | Description                                    |
|-----------|------------------------------------------------|
| docker    | JMeter custom image                            |
| docs      | Documentation and images                       |
| jmeter    | Contains JMX files used by JMeter agents       |
| pipelines | Docker and JMeter pipeline definitions         |
| scripts   | Scripts that support pipeline execution        |
| terraform | Terraform template for infrastructure creation |

## Possible Modifications

This sample only shows how to manually trigger a JMeter Pipeline. You can easily adapt its content and incorporate it on other pipelines, apply continuous integration or other improvements.

This sample uses static JMX files on [jmeter](./jmeter/) directory. You can use many techniques to parameterize JMX files. Some of them are:
* [CSV files](https://guide.blazemeter.com/hc/en-us/articles/206733689-Using-CSV-DATA-SET-CONFIG)
* [Properties](http://jmeter.apache.org/usermanual/functions.html#__P)
* [Environment Variables](https://jmeter-plugins.org/wiki/Functions/#envsupfont-color-gray-size-1-since-1-2-0-font-sup)

Also, you can dynamically generate JMX files from Swagger/Open API using [swagger-codegen](https://github.com/swagger-api/swagger-codegen) or other similar projects.

Current Terraform template creates a new VNET to host JMeter installation. Instead you can modify the template to deploy agents in an existing VNET or you can apply VNET peering to connect them into an existing infrastructure.