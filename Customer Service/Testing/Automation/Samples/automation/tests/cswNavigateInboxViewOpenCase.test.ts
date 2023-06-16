// =====================================================================
// Copyright (c) Microsoft Corporation. All rights reserved. 
//
//
//  THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY
//  KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
//  PARTICULAR PURPOSE.
// =====================================================================
//
// Name: Navigate to CSW Dashboard
// Description: 
//      1. Open Customer Service Workspace
//      2. Navigate to Knowledge Search from Sitemap
//      3. Search by a keyword "Water Filtration" with name as parameter
//      4. Verify the search results and open the record
// App: Customer Service Workspace 
// Pre-requisite: Configure Inbox View (https://learn.microsoft.com/en-us/dynamics365/customer-service/configure-inbox)
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

//Refactoring based on selectors
test('CSW - Open Case from  Inbox View', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    console.log('01.Open Customer Service Workspace App');
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
    console.log('02.Verify if the Inbox View is enabled or not');
    const inboxViewEnabledCheck = await page.locator(cswSelectors.inboxViewTabSelector).count();
    console.log("Inbox View Enabled: " + (inboxViewEnabledCheck > 0 ? "Enabled":"Disabled"));
    if (inboxViewEnabledCheck > 0){
        await page.locator(cswSelectors.inboxViewTabSelector).click();
        await waitUntilAppIdle(page);
    }
    console.log('Inbox View not enabled: Configure Inbox view for agents');
    console.log("Test execution Status: SUCCESS");
    //End
});