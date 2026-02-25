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
// Name: Retrieve a case by Case Title
// Description: 
//      1. Open Customer Service Workspace
//      2. Switch the view to Active Cases
//      3. From the edit filters, add search criteria to search by Case Title
//      4. Open the Case from Search Results
// App: Customer Service Workspace 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, viewSelectors, 
    advancedFilterSelectors, gridSelectors, FormControlSelectors, FormSelectors,
    CommandBarFormButtonsSelectors, ResolveCaseFormSelector, cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat } from '../utils/common';

//Refactoring based on selectors
test('CSW - Search Case by Case Title', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
    console.log('01.Search a case by Title');
    console.log(stringFormat("Case Title:{0}",caseTitle));
    //await page.locator(stringFormat(cswSelectors.SiteMapButtonSelector,"Service list","Site Map")).click();
    await page.getByRole('button', { name: 'Site Map' }).click();
    //Opening Sub Area - Cases
    await page.locator(stringFormat(subAreaMenuSelectors.ServiceCaseMenuSelector,"Service","Cases")).click();
    //End of Sub Area
    //Changing view to Active Cases
    await page.locator(viewSelectors.DefaultViewSelector).waitFor({state:'attached'});
    await page.locator(viewSelectors.DefaultViewSelector).click();
    const viewMenu = page.locator(stringFormat(viewSelectors.DynamicViewSelector,'Active Cases')).first();
    await viewMenu.waitFor({state:'attached'});
    await viewMenu.click(); 
    console.log ('Switching the view to Active Cases');
    //End
    //Adding a new Filter expression to search by case number
    await page.locator(advancedFilterSelectors.openFilterSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.openFilterSelector).click();
    await page.locator(advancedFilterSelectors.addRowFilterMenuSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.addRowFilterMenuSelector).click();
    await page.locator(advancedFilterSelectors.addRowSelector).click();
    console.log ('Adding a new filter expression');
  
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().waitFor({state:'attached'});//""
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().focus()
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().click();
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Title')).waitFor({state:'attached'});
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Title')).click();

    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();
    await page.locator(advancedFilterSelectors.filterOperatorSelector).first().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterOperatorContainsSelect).click();
    //await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();

    await page.locator(advancedFilterSelectors.filterInputTextSelector).waitFor();
    await page.locator(advancedFilterSelectors.filterInputTextSelector).fill(caseTitle);
  
    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
    //End of Filter add
  
    //Opening the first search result from the grid
    await page.locator(gridSelectors.gridFirstRowSelector).waitFor();
    await page.locator(gridSelectors.gridFirstRowSelector).click();
    //await page.locator(gridSelectors.cswGridRowSelector).first().click();
    //await page.locator("//div[@data-id='entity_control-pcf_grid_control_container']//descendant::a[@role='link']").first().click();
    //End 
});