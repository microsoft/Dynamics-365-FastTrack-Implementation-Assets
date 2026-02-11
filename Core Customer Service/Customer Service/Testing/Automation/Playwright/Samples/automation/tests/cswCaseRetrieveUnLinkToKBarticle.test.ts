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
// Name: Retrieve a case by Case Title and filter the KB articles and link
// Description: 
//      1. Open Customer Service Workspace
//      2. Switch the view to Active Cases
//      3. From the edit filters, add search criteria to search by Case Title
//      4. Open the Case from Search Results
//      5. Search for KB articles on the Smart Assist Pane
//      6. Unlink to the KB article
// App: Customer Service Workspace 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, viewSelectors, 
    advancedFilterSelectors, gridSelectors, FormControlSelectors, FormSelectors,
    CommandBarFormButtonsSelectors, ResolveCaseFormSelector, cswSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

//Refactoring based on selectors
test('CSW - Search Case by Case Title, Filter KB article and unlink to Case', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
    console.log('01.Search a case by Title');
    console.log(stringFormat("Case Title:{0}",caseTitle));
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
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().waitFor({state:'visible'});
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().click();
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Title')).waitFor({state:'attached'});
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Title')).click();
    console.log('...Selecting the Filter Field - Case Title');
    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();
    await page.locator(advancedFilterSelectors.filterOperatorSelector).first().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterOperatorContainsSelect).waitFor({state:"visible"});
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
    await waitUntilAppIdle(page);
    const kbArticleLinkedCheck = await page.locator(cswSelectors.smartAssistKBArticleUnlinktoCaseSelector).count();
    console.log("Case Linked to KB Article Check:" + kbArticleLinkedCheck.toString());
    if (kbArticleLinkedCheck > 0){
        console.log ('Case linked to KB Article. Now unlinking...');
        await page.locator(cswSelectors.smartAssistKBArticleUnlinktoCaseSelector).first().click();
        console.log ('Unlinked KB article from the case');
        await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Save')).click();
    }
    //End
});