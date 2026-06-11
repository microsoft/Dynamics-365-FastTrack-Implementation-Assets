# Sample Inventory Fulfillment Agent

## Overview

Welcome to the Inventory Fulfillment Agent template. To get started, follow the instructions as described [here.](../README.md)

## Support

This solution is provided as-is. Bugs, feature addition/modification requests, and other changes are the responsibility of the end-user.

Always thoroughly test components in a non-prod environment.

## Changes

### Inventory Fulfillment Agent v1.0.0.7

* Fixed IVS token retrieval for environments that require the documented security service redirect flow.
* Added environment variable support for the default legal entity/company.
* Updated IVS tool calls to use the configured legal entity automatically.
* Fixed on-hand quantity mapping for current IVS response fields, including total on-hand, available to reserve, and total available.
* Improved handling for empty IVS/product search results so “no records found” is reported cleanly instead of as an error.
* Removed the previous helper flow for legal entity lookup and simplified the tool configuration.
* Kept solution import compatibility as an update to the existing Inventory Fulfillment Agent solution.
