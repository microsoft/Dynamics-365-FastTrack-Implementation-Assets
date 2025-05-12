# Storage Management Data Cleanup 

This repository contains SQL scripts designed to manage and optimize storage consumption in the AXDB database of Dynamics 365 F&O. The scripts help clean up large tables  perform transaction-less copy operations based on the target sandbox usage use cases (This is primarily meant to be used with LCS Tier 2 + environments but can apply to any F&O environment allowing access to SQL AXDB database).

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [License](#License)

## Introduction

The **Storage management Data Cleanup** include two main SQL scripts:

1. **Large Tables Data Cleanup**: This script helps organizations manage their storage by cleaning up large tables containing data from a selected date in the AXDB database. This process helps maintain the storage consumption level over time

2. **Transaction-Less Copy SQL Script**: This script performs transaction-less copy operations in the AXDB database, ensuring efficient data management without the overhead of transactions.

## Prerequisites

Before using this script, ensure you have the following:

- Access to the Dynamics 365 F&O AXDB database.
- Appropriate permissions to execute SQL scripts.

## Usage
To use the script, follow these steps:

1. Open the SQL script files in your preferred text editor.
2. Review and modify the script parameters as needed to suit your environment.
3. Execute the script against your AXDB database using a SQL client.
4. Run the script in the order of the prefix from 0-Prerequisits to 4-MainScript

For a short video of how to use the script please [follow this link](https://youtu.be/_FnvbF8Vgrw)
 
## Configuration
The script includes several configurable parameters to tailor the cleanup process to your specific needs. Ensure you review and adjust these parameters before running the script.

## Contributing
We welcome contributions to improve this script. If you have suggestions or improvements, please submit a pull request or open an issue in the repository.
