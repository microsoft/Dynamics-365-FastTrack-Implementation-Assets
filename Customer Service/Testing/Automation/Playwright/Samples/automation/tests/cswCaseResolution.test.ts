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
// Name: Retrieve a case, attach KB article and Resolve. 
// Description: 
//      1. Open Customer Service Workspace
//      2. Switch the view to Active Cases
//      3. From the edit filters, add search criteria to search by Case Title
//      4. Open the Case from Search Results
//      5. Search for KB articles on the Smart Assist Pane
//      6. Link to the KB article
//      7. Resolve Case 
// App: Customer Service Workspace 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, viewSelectors, 
    advancedFilterSelectors, gridSelectors, FormControlSelectors, FormSelectors, ReactivateCaseDialogSelector,
    CommandBarFormButtonsSelectors, ResolveCaseFormSelector, cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

test('CSW - Search Case by Case Title, Filter KB article and Link to Case and Resolve', async ({ page, }) => {
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
    console.log('...Selecting the Filter Field - Case Title');
    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();
    await page.locator(advancedFilterSelectors.filterOperatorSelector).first().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterOperatorContainsSelect).click();
    console.log('...Selecting the Filter Operator  - Contains');
    await page.locator(advancedFilterSelectors.filterInputTextSelector).waitFor();
    await page.locator(advancedFilterSelectors.filterInputTextSelector).fill(caseTitle);
    console.log('...Entering the search text - {0}', caseTitle);
    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
    console.log ('Searching for records');
    await waitUntilAppIdle(page);
    //End of Filter add
    //Opening the first search result from the grid
    //await page.locator(gridSelectors.gridFirstRowSelector).waitFor();
    //await page.locator(gridSelectors.gridFirstRowSelector).click();
    console.log ('Selecting the returned case from the grid');
    await page.locator(gridSelectors.cswGridRowSelector).first().click();
  
    //Searching KB articles through SMART ASSIST
    console.log ('Opening the KB Search from Smart Assist');
    await page.locator(cswSelectors.smartAssistKBSearchSelector).click();
    await page.locator(cswSelectors.smartAssistKBSearchTextboxSelector).clear();
    console.log ('...Searching by a keyword - Coffee');
    await page.locator(cswSelectors.smartAssistKBSearchTextboxSelector).fill('Coffee');
    await page.locator(cswSelectors.smartAssistKBSearchTextboxSelector).press('Enter');
    console.log ('...Retrieving KB Articles - matching keyword');
    await page.locator(cswSelectors.smartAssistKBSearchResultsSelector).first().click();
    console.log ('Linked KB article to the case');
    await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Save')).click();
    await waitUntilAppIdle(page);
    const resolveButtonCheck = await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Resolve Case')).count();
    console.log("Resolve Button Count:" + resolveButtonCheck.toString());
    if (resolveButtonCheck == 0){
        await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Reactivate Case')).click();
        await page.locator(ReactivateCaseDialogSelector.ReactivateButtonSelector).click();
        await waitUntilAppIdle(page);
    }

    const resolveButton = await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Resolve Case'));
    await resolveButton.click();

    await page.locator(stringFormat(ResolveCaseFormSelector.DynamicTextBoxSelector,'ResolveCase','Resolution')).click();
    await page.locator(stringFormat(ResolveCaseFormSelector.DynamicTextBoxSelector,'ResolveCase','Resolution')).fill('Case Resolved');
    await page.locator(stringFormat(ResolveCaseFormSelector.DynamicFooterButtonSelector,'Resolve')).click();
    console.log(stringFormat('CSW - Resolved the case: {0}',caseTitle));
    //End
});