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
// Name: Navigation Test - Open a case from the Home --> Customer Service Agreement Dashboard
// Description: 
//      1. Open Customer Service Workspace
//      2. Navigate to Home Tab
//      3. Navigate to the Customer Service Agreement Dashboard
//      4. Open the First case
// App: Customer Service Workspace 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

//Refactoring based on selectors
test('CSW - Open a case from the Home tab default Dashboard', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
    console.log('Navigation --> Select the HomeTab');
    await page.locator(cswSelectors.homeTabSelector).click();
    await waitUntilAppIdle(page);
    console.log('Navigation --> Verify the default Dashboard is --> Customer Service Agent Dashboard');
    const dashboardCheck = await page.locator(cswSelectors.dashboardTabSelector).count();
    console.log("Default Dashboard: Customer Service Agent Dashboard Count --> " + dashboardCheck.toString());
    if (dashboardCheck > 0){
        await page.locator(cswSelectors.dashboardTabSelector).click();
        await waitUntilAppIdle(page);
    }
    console.log ('Switching the view to Active Cases');
    //Changing view to Active Cases
    await page.locator(cswSelectors.defaultCaseViewSelector).first().click();
    await page.getByText('Active Cases', { exact: true }).click();
    page.once('dialog', dialog => {
        console.log(`Dialog message: ${dialog.message()}`);
        dialog.dismiss().catch(() => {});
    });
    await waitUntilAppIdle(page);
    console.log("Verify Grid load");
    const gridLoadCheck = await page.locator(cswSelectors.gridSelector).count();
    console.log("Default Dashboard: Customer Service Agent Dashboard Count --> " + gridLoadCheck.toString());
    if (gridLoadCheck > 0){
        await waitUntilAppIdle(page);
    }
    console.log("Navigation --> Select the first row in the default view");
    await page.locator(cswSelectors.gridURLSelector).first().click();
    await waitUntilAppIdle(page);
    console.log("Test Completed --> Success");
});