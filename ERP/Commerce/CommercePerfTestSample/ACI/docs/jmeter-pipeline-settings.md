# JMeter Pipeline Settings

The pipeline uses Terraform 0.13.x to provision JMeter and its infrastructure on Azure.

All environment variables that start with the prefix `TF_VAR` can be used by Terraform to fill the template. According to the [official docs](https://www.terraform.io/docs/commands/environment-variables.html#tf_var_name):

> Environment variables can be used to set variables. The environment variables must be in the format TF_VAR_name and this will be checked last for a value.

There are 2 variables that can be set directly on the JMeter pipeline. Those are:

| Environment Variable        | Terraform Variable   | Default Value |
|-----------------------------|----------------------|---------------|
| TF_VAR_JMETER_JMX_FILE      | JMETER_JMX_FILE      |               |
| TF_VAR_JMETER_WORKERS_COUNT | JMETER_WORKERS_COUNT |       1       |

All the other variables can be set on a library group called `JMETER_TERRAFORM_SETTINGS`. If a variable is not present on that library, a default value will be used, as the following table shows:

| Environment Variable                  | Terraform Variable             | Default Value       |
|---------------------------------------|--------------------------------|---------------------|
| TF_VAR_RESOURCE_GROUP_NAME            | RESOURCE_GROUP_NAME            |        jmeter       |
| TF_VAR_LOCATION                       | LOCATION                       |        eastus       |
| TF_VAR_PREFIX                         | PREFIX                         |        jmeter       |
| TF_VAR_VNET_ADDRESS_SPACE             | VNET_ADDRESS_SPACE             |     10.0.0.0/16     |
| TF_VAR_SUBNET_ADDRESS_PREFIX          | SUBNET_ADDRESS_PREFIX          |     10.0.0.0/24     |
| TF_VAR_JMETER_WORKER_CPU              | JMETER_WORKER_CPU              |         2.0         |
| TF_VAR_JMETER_WORKER_MEMORY           | JMETER_WORKER_MEMORY           |         8.0         |
| TF_VAR_JMETER_CONTROLLER_CPU          | JMETER_CONTROLLER_CPU          |         2.0         |
| TF_VAR_JMETER_CONTROLLER_MEMORY       | JMETER_CONTROLLER_MEMORY       |         8.0         |
| TF_VAR_JMETER_DOCKER_IMAGE            | JMETER_DOCKER_IMAGE            | justb4/jmeter:5.1.1 |
| TF_VAR_JMETER_DOCKER_PORT             | JMETER_DOCKER_PORT             |         1099        |
| TF_VAR_JMETER_ACR_NAME                | JMETER_ACR_NAME                |                     |
| TF_VAR_JMETER_ACR_RESOURCE_GROUP_NAME | JMETER_ACR_RESOURCE_GROUP_NAME |                     |
| TF_VAR_JMETER_STORAGE_QUOTA_GIGABYTES | JMETER_STORAGE_QUOTA_GIGABYTES |          1          |
| TF_VAR_JMETER_RESULTS_FILE            | JMETER_RESULTS_FILE            |     results.jtl     |
| TF_VAR_JMETER_DASHBOARD_FOLDER        | JMETER_DASHBOARD_FOLDER        |      dashboard      |
| TF_VAR_JMETER_EXTRA_CLI_ARGUMENTS     | JMETER_EXTRA_CLI_ARGUMENTS     |                     |
