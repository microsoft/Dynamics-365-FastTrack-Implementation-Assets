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
// Name: Create a Case 
// Description: Test to Create a new case from UI
//      1. Open Customer Service Hub App
//      2. Navigate to the Site Map and Select Cases
//      3. Click on the new case
//      4. Fill the Case details 
//      5. Save Case 
// App: Customer Service Hub 
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, viewSelectors, 
  advancedFilterSelectors, gridSelectors, FormControlSelectors,
  CommandBarFormButtonsSelectors, ResolveCaseFormSelector } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';

test('Create Case', async ({ page }) => {
  //Navigating to the CSH App 
  let appId = process.env.CSH_APPID as string;
  await navigateToApps(page, stringFormat(appId) ,'Customer Service Hub');
  //End of Navigation
  //Opening Sub Area - Cases
  await page.locator(stringFormat(subAreaMenuSelectors.ServiceCaseMenuSelector,"Service","Cases")).click();
  //End of Sub Area
  await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'New Case')).click();
  await page.locator(stringFormat(FormControlSelectors.TextBox,'title')).click();
  await page.locator(stringFormat(FormControlSelectors.TextBox,'title')).fill('TEST CASE AUTOMATION - SAMPLE '+ Math.floor((Math.random() * 100) + 1).toString());

  await page.locator(stringFormat(FormControlSelectors.LookupButton,'customerid')).click();
  await page.getByRole('button', { name: 'Search records for Customer, Lookup field' }).click();
  await page.getByRole('treeitem', { name: 'Fourth Coffee, claudia@pmgdemo.onmicrosoft.com' }).getByText('Fourth Coffee').click();
  
  await page.locator(stringFormat(FormControlSelectors.TextBox,'description')).click();
  await page.locator(stringFormat(FormControlSelectors.TextBox,'description')).fill('We are having issue turning on the coffee machine. ');
  await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Save')).click();

  await waitUntilAppIdle(page);

  await page.locator(stringFormat(FormControlSelectors.TextBoxValueSelector,'ticketnumber')).waitFor({state:'visible'});
  let caseNumberControl = await page.locator(stringFormat(FormControlSelectors.TextBoxValueSelector,'ticketnumber'));
  await caseNumberControl.waitFor({state:'attached'});
  let caseNumber = await caseNumberControl.evaluate(e => (e as HTMLInputElement).value);
  console.log(stringFormat('CREATED A NEW CASE: {0}',caseNumber));
});