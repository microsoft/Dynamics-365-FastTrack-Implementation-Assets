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
// Name: Retrieve a case by Case Number using advanced search
// Description: 
//      1. Open Customer Service Hub App
//      2. Switch the view to All Cases
//      3. From the edit filters, add search criteria to search by Case Number
//      4. Open the Case from Search Results
// App: Customer Service Hub 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, viewSelectors, 
  advancedFilterSelectors, gridSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat } from '../utils/common';

//Refactoring based on selectors
test('Search cases by Case Number', async ({ page, }) => {
  //Navigating to the CSH App 
  let appId = process.env.CSH_APPID as string;
  await navigateToApps(page, stringFormat(appId) ,'Customer Service Hub');
  //End of Navigation

  let caseNumberString = process.env.CASE_NUMBER?.toString(); 
  console.log(stringFormat("CaseNumber:{0}",caseNumberString));
  //Opening Sub Area - Cases
  await page.locator(stringFormat(subAreaMenuSelectors.ServiceCaseMenuSelector,"Service","Cases")).click();
  //End of Sub Area
  //Changing view to Active Cases
  await page.locator(viewSelectors.DefaultViewSelector).click();
  const viewMenu = page.locator(stringFormat(viewSelectors.DynamicViewSelector,'All Cases')).first();
  await viewMenu.waitFor();
  await viewMenu.click(); 
  console.log ('Switching the view to All Cases');
  //End
  //Adding a new Filter expression to search by case number
  await page.locator(advancedFilterSelectors.openFilterSelector).waitFor({state:'attached'});
  await page.locator(advancedFilterSelectors.openFilterSelector).click();
  await page.locator(advancedFilterSelectors.addRowFilterMenuSelector).waitFor({state:'attached'});
  await page.locator(advancedFilterSelectors.addRowFilterMenuSelector).click();
  await page.locator(advancedFilterSelectors.addRowSelector).click();
  console.log ('Adding a new filter expression');

  await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().waitFor();//""
  await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().focus()
  await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().click();

  await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).waitFor({state:'visible'});
  await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).click();

  await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();
  await page.locator(advancedFilterSelectors.filterOperatorSelector).first().waitFor({state:'attached'});
  await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).first().click();

  await page.locator(advancedFilterSelectors.filterInputTextSelector).waitFor();
  await page.locator(advancedFilterSelectors.filterInputTextSelector).fill(caseNumberString);

  await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
  await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
   //End of Filter add

  //Opening the first search result from the grid
  await page.locator(gridSelectors.gridFirstRowSelector).waitFor();
  await page.locator(gridSelectors.gridFirstRowSelector).click();
  //End
});

