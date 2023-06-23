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
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

//Refactoring based on selectors
test('CSW - Knowledge Search By Keyword', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    console.log('01.Open Customer Service Workspace App');
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
    console.log('02. Navigate to the Knowledge Search');
    await page.getByRole('button', { name: 'Site Map' }).click();
    await page.locator(stringFormat(subAreaMenuSelectors.ServiceKBMenuSelector,"Service","Knowledge Search")).click();
    console.log('03.Fill the search parameter');
    await page.locator(cswSelectors.knowledgeSearchInputSelector).fill("Water Filtration");
    await page.keyboard.down('Enter');
    console.log('04.Verify the KB search results')
    console.log('Navigation --> Verify the Search Results');
    await waitUntilAppIdle(page);
    const searchResultsCheck = await page.locator(cswSelectors.knowledgeSearchResultsSelector).count();
    console.log("KB Article found: " + searchResultsCheck.toString());
    if (searchResultsCheck > 0){
        await page.locator(cswSelectors.knowledgeSearchResultsSelector).first().click();
        await waitUntilAppIdle(page);
    }
    console.log("Test execution Status: SUCCESS");
    //End
});