# Storage Management Data Cleanup

This repository contains SQL scripts designed to manage and optimize storage consumption in the AXDB database of Dynamics 365 F&O. The scripts help clean up large tables from closed years or perform transaction-less copy operations based on the target sandbox usage use cases.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [License](#License)

## Introduction

The **Storage management Data Cleanup** include two main SQL scripts:

1. **Closed Years Large Tables Data Cleanup**: This script helps organizations manage their storage by cleaning up large tables containing data from closed years in the AXDB database. This process helps maintain the performance and efficiency of the Dynamics 365 system.

2. **Transaction-Less Copy SQL Script**: This script performs transaction-less copy operations in the AXDB database, ensuring efficient data management without the overhead of transactions.

## Prerequisites

Before using this script, ensure you have the following:

- Access to the Dynamics 365 F&O AXDB database.
- Appropriate permissions to execute SQL scripts.
- Backup of your data to prevent any accidental loss.

## Installation

To install and set up the script, follow these steps:

1. Clone the repository:
2. Navigate to the script directory:

## Usage
To use the script, follow these steps:

1. Open the SQL script file in your preferred text editor.
2. Review and modify the script parameters as needed to suit your environment.
3. Execute the script against your AXDB database using a SQL client.

## Configuration
The script includes several configurable parameters to tailor the cleanup process to your specific needs. Ensure you review and adjust these parameters before running the script.

## Contributing
We welcome contributions to improve this script. If you have suggestions or improvements, please submit a pull request or open an issue in the repository.

## License
This project is licensed under the MIT License. See the LICENSE file for details.   
   
   git clone https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets.git
