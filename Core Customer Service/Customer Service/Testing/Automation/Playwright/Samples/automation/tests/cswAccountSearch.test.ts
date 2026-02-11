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
//      2. Navigate to Global Search
//      3. Search by account with name as parameter
//      4. Verify the search results and open the record
// App: Customer Service Workspace 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

//Refactoring based on selectors
test('CSW - Global Search by Account Name', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    console.log('01.Open Customer Service Workspace App');
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
    console.log('02.Navigate to Search Button and Click');
    await page.locator(cswSelectors.globalSearchButtonSelector).click();
    console.log('03.Fill the search parameter');
    await page.locator(cswSelectors.searchInputSelector).fill("Fourth Coffee");
    console.log('04.Change the Filter selector to Account')
    await page.locator(cswSelectors.searchFilterSelector).click();
    await page.getByRole('combobox', { name: 'Filter with' }).selectOption('1');
    await waitUntilAppIdle(page);
    console.log('Navigation --> Verify the Search Results');
    const searchResultsCheck = await page.locator(cswSelectors.searchGridSelector).count();
    console.log("Default Dashboard: Customer Service Agent Dashboard Count --> " + searchResultsCheck.toString());
    if (searchResultsCheck > 0){
        await page.getByRole('link', { name: 'Fourth Coffee 2020 ----' }).click();
        await waitUntilAppIdle(page);
    }
    console.log("Test execution Status: SUCCESS");
    //End
});