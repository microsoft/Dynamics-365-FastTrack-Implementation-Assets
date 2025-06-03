# Overview

This is a sample project showing how to use the headless commerce engine for order ingestion.

# What is covered?

The example walks through a very simple transaction upload flow.

## Prerequisites

Before you can run the sample, the following criteria must be met:

1. You must have a working Commerce scale unit with data synchronized from CDX.
2. The data must be configured for e-commerce scenarios. If in doubt, use demo data.
3. Make the project as startup project

## Suggested demo script

To start, try the following scenario (assuming demo data is configured):

1. Select operating unit number

![Order](./data/tx.png)

To see the sales order created in HQ:

1. Go to Retail and Commerce > Retail and Commerce IT > Distribution schedule.
2. Run P-0001 job to pull the sales transaction from channels to HQ.
3. Go to Retail and Commerce > Retail and Commerce IT > Synchronize orders job.
4. Go to Retail and Commerce > Inquiries and reports > Online store transactions

![alt text](./data/order.png)
