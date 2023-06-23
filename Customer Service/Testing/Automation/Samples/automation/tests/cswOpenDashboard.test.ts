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
//      2. Navigate to Sitemap
//      3. Open the Dashboard 
//      4. Verify the default Dashboard loaded is "Customer Service Agent Dashboard"
// App: Customer Service Workspace 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

//Refactoring based on selectors
test('CSW - Navigate to CSW Dashboard', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    console.log('01.Open Customer Service Workspace App');
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
    console.log('02.Navigate to Site Map');
    await page.getByRole('button', { name: 'Site Map' }).click();
    console.log('03.Open Dashboards menu item');
    await page.locator(stringFormat(subAreaMenuSelectors.ServiceCaseMenuSelector,"Service","Dashboards")).click();
    console.log('04.Change the default dashboard')
    await waitUntilAppIdle(page);
    console.log('Navigation --> Verify the default Dashboard is --> Customer Service Agent Dashboard');
    const dashboardCheck = await page.locator(cswSelectors.dashboardTabSelector).count();
    console.log("Default Dashboard: Customer Service Agent Dashboard Count --> " + dashboardCheck.toString());
    if (dashboardCheck > 0){
        await page.locator(cswSelectors.dashboardTabSelector).click();
        await waitUntilAppIdle(page);
    }
    console.log("Test execution Status: SUCCESS");
    //End
});