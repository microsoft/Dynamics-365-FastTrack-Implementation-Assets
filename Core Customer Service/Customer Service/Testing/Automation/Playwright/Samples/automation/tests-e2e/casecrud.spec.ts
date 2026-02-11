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
// Name: END To END - CASE/INCIDENT CRUD TEST CASES 
// Description: Executes CRUD TEST CASES on CASE/INCIDENT IN SEQUENCE
// TEST COVER
// 0. NAVIGATING TO THE CUSTOMER SERVICE HUB
// 1. CREATE A NEW CASE
// 2. RETRIEVE THE CASE CREATED WITH CASE NUMBER
// 3. UPDATE CASE
// 4. RESOLVE CASE AFTER RETRIEVE
// =====================================================================
import { test, expect, type Page } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { subAreaMenuSelectors, viewSelectors, 
  advancedFilterSelectors, gridSelectors, FormControlSelectors, FormSelectors,
  CommandBarFormButtonsSelectors, ResolveCaseFormSelector } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';


const caseNumber = process.env.CASE_NUMBER?.toString();
  test.describe('E2E CASE CRUD OPERATIONS', () => {
    test.describe.configure({ mode: 'serial' });
    var caseNumber= '';
    let appId = process.env.CSH_APPID as string;
    test.beforeEach(async ({ page }) => {
      await navigateToApps(page, stringFormat(appId) ,'Customer Service Hub');
    });

  test('01.CREATE A CASE', async ({ page }) => {
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
    caseNumber = await caseNumberControl.evaluate(e => (e as HTMLInputElement).value);
    console.log(stringFormat('CREATED A NEW CASE: {0}',caseNumber));
  });
  
 /* test('02.RETRIEVE A CASE -BY CASE NUMBER', async ({ page, }) => {
    console.log('02.RETRIEVE A CASE -BY CASE NUMBER');
    console.log(stringFormat("CaseNumber:{0}",caseNumber));
    //Opening Sub Area - Cases
    await page.locator(stringFormat(subAreaMenuSelectors.ServiceCaseMenuSelector,"Service","Cases")).click();
    //End of Sub Area
    //Changing view to Active Cases
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
    await page.locator(advancedFilterSelectors.addRowSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.addRowSelector).click();
    console.log ('Adding a new filter expression');

    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().focus()
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().click();
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).waitFor({state:'visible'});
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).click();

    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();
    await page.locator(advancedFilterSelectors.filterOperatorSelector).first().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).first().click();

    await page.locator(advancedFilterSelectors.filterInputTextSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterInputTextSelector).fill(caseNumber);

    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
      //End of Filter add

    //Opening the first search result from the grid
    await page.locator(gridSelectors.gridFirstRowSelector).waitFor();
    await page.locator(gridSelectors.gridFirstRowSelector).click();
    await waitUntilAppIdle(page);
});  */

test('02 & 03.RETRIEVE CASE BY CASE NUMBER, UPDATE AN ACTIVE CASE', async ({ page, }) => {
    console.log('02.RETRIEVE A CASE -BY CASE NUMBER');  
    console.log('03.UPDATE AN ACTIVE CASE');
    console.log(stringFormat("CaseNumber:{0}",caseNumber));
    //Opening Sub Area - Cases
    await page.locator(stringFormat(subAreaMenuSelectors.ServiceCaseMenuSelector,"Service","Cases")).click();
    //End of Sub Area
    //Changing view to Active Cases
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
    await page.locator(advancedFilterSelectors.addRowSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.addRowSelector).click();
    console.log ('Adding a new filter expression');

    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().focus()
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().click();
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).waitFor({state:'visible'});
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).click();

    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();
    await page.locator(advancedFilterSelectors.filterOperatorSelector).first().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).first().click();

    await page.locator(advancedFilterSelectors.filterInputTextSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterInputTextSelector).fill(caseNumber);

    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
      //End of Filter add

    //Opening the first search result from the grid
    await page.locator(gridSelectors.gridFirstRowSelector).waitFor();
    await page.locator(gridSelectors.gridFirstRowSelector).click();
    await page.locator(stringFormat(FormSelectors.textAreaSelector,'Description')).waitFor();
    await page.locator(stringFormat(FormSelectors.textAreaSelector,'Description')).fill('We are having issue turning on the coffee machine. Updated:' + Date.now().toString());
    await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Save')).click();
    //await waitUntilAppIdle(page);
    console.log(stringFormat('UPDATED THE CASE: {0}',caseNumber));
});

  test('04.RESOLVE CASE AFTER RETRIEVE', async ({ page, }) => {
    console.log('04.RESOLVE CASE AFTER RETRIEVE');
    console.log(stringFormat("CaseNumber:{0}",caseNumber));
    //Opening Sub Area - Cases
    await page.locator(stringFormat(subAreaMenuSelectors.ServiceCaseMenuSelector,"Service","Cases")).click();
    //End of Sub Area
    //Changing view to Active Cases
    await page.locator(viewSelectors.DefaultViewSelector).click();
    const viewMenu = page.locator(stringFormat(viewSelectors.DynamicViewSelector,'Active Cases')).first();
    await viewMenu.waitFor();
    await viewMenu.click(); 
    console.log ('Switching the view to Active Cases');
    //End
    //Adding a new Filter expression to search by case number
    await page.locator(advancedFilterSelectors.openFilterSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.openFilterSelector).click();
    await page.locator(advancedFilterSelectors.addRowFilterMenuSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.addRowFilterMenuSelector).click();
    await page.locator(advancedFilterSelectors.addRowSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.addRowSelector).click();
    console.log ('Adding a new filter expression');

    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().waitFor();//""
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().focus()
    await page.locator(advancedFilterSelectors.filterFieldMenuSelector).last().click();

    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).waitFor({state:'attached'});
    await page.locator(stringFormat(advancedFilterSelectors.filterFieldSelector,'Case Number')).click();

    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).last().click();
    await page.locator(advancedFilterSelectors.filterOperatorSelector).first().waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterOperatorMenuSelector).first().click();

    await page.locator(advancedFilterSelectors.filterInputTextSelector).waitFor({state:'attached'});
    await page.locator(advancedFilterSelectors.filterInputTextSelector).fill(caseNumber);

    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
    await page.locator(advancedFilterSelectors.applyFilterButtonSelector).click();
      //End of Filter add

    //Opening the first search result from the grid
    await page.locator(gridSelectors.gridFirstRowSelector).waitFor();
    await page.locator(gridSelectors.gridFirstRowSelector).click();
    await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Resolve Case')).waitFor({state:'visible'});
    await page.locator(stringFormat(CommandBarFormButtonsSelectors.DynamicCommandBarButtonSelector,'Resolve Case')).click();

    await page.locator(stringFormat(ResolveCaseFormSelector.DynamicTextBoxSelector,'ResolveCase','Resolution')).click();
    await page.locator(stringFormat(ResolveCaseFormSelector.DynamicTextBoxSelector,'ResolveCase','Resolution')).fill('Case Resolved');
    // await page.locator(ResolveCaseFormSelector.BillableTimeSelector).click();
    // await page.locator(stringFormat(ResolveCaseFormSelector.DynamicTextBoxSelector,'ResolveCase','Remarks')).fill('Closing the Case');
    await page.locator(stringFormat(ResolveCaseFormSelector.DynamicFooterButtonSelector,'Resolve')).click();
    
    console.log(stringFormat('RESOLVED THE CASE: {0}',caseNumber));
    
  });

});


