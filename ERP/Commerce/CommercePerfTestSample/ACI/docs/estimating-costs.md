# Estimating Costs

It's recommended the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) to estimate the monthly costs.

> The costs may change depending on your contracts with Microsoft.

### Example

* 1 Basic Container Registry
* 1 Standard Storage Account (General Purpose)
* `N` Container Instance groups running in `M` seconds with `X` vCPUs; where:
  * `N` is the estimated number of instances in the load test (1 controller + `N'` workers)
  * `M` is the test duration in seconds
  * `X` is the number of vCPUs for each instance group
