variable "RESOURCE_GROUP_NAME" {
  type    = string
  default = "jmeter"
}

variable "LOCATION" {
  type    = string
  default = "eastus"
}

variable "PREFIX" {
  type    = string
  default = "jmeter"
}

variable "VNET_ADDRESS_SPACE" {
  type    = string
  default = "10.0.0.0/16"
}

variable "SUBNET_ADDRESS_PREFIX" {
  type    = string
  default = "10.0.0.0/24"
}

variable "JMETER_WORKERS_COUNT" {
  type    = number
  default = 1
}

variable "JMETER_WORKER_CPU" {
  type    = string
  default = "2.0"
}

variable "JMETER_WORKER_MEMORY" {
  type    = string
  default = "8.0"
}

variable "JMETER_CONTROLLER_CPU" {
  type    = string
  default = "2.0"
}

variable "JMETER_CONTROLLER_MEMORY" {
  type    = string
  default = "8.0"
}

variable "JMETER_DOCKER_IMAGE" {
  type    = string
  default = "justb4/jmeter:5.1.1"
}

variable "JMETER_DOCKER_PORT" {
  type    = number
  default = 1099
}

variable "JMETER_ACR_NAME" {
  type    = string
  default = ""
}

variable "JMETER_ACR_RESOURCE_GROUP_NAME" {
  type    = string
  default = ""
}

variable "JMETER_STORAGE_QUOTA_GIGABYTES" {
  type    = number
  default = 1
}

variable "JMETER_JMX_FILE" {
  type        = string
  description = "JMX file"
}

variable "JMETER_RESULTS_FILE" {
  type    = string
  default = "results.jtl"
}

variable "JMETER_DASHBOARD_FOLDER" {
  type    = string
  default = "dashboard"
}

variable "JMETER_EXTRA_CLI_ARGUMENTS" {
  type    = string
  default = ""
}
