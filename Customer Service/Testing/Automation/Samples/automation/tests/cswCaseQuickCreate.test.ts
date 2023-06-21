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
// Name: Create a Case from Quick Create
// Description: 
//      1. Open Customer Service Workspace
//      2. Navigate to Quick Create 
//      3. Open Quick Create Flyout and Select Case
//      4. Create Case by filling the required info
// App: Customer Service Workspace
// =====================================================================
import { test, expect } from '@playwright/test';
import dotenv from 'dotenv';
dotenv.config();
import { QuickCreateCaseFormSelectors } from "../selectors/caseCRUDSelectors.json";
import { navigateToApps, stringFormat, waitForQuickCreateFormLoad, openGlobalQuickCreateForm } from '../utils/common';

//Refactoring based on selectors
test('CSW - CREATE CASE FROM QUICK CREATE', async ({ page, }) => {
    //Navigating to the CSW App  - Multi-session App
    let appId = process.env.CSW_APPID as string;
    var caseTitle = process.env.CASE_TITLE as string;
    await navigateToApps(page, stringFormat(appId) ,'Customer Service Workspace');
	// Open the Case record from global quick create form
    console.log("Opening Quick Create Flyout Menu");
	await openGlobalQuickCreateForm(page, "incident");
	// Wait to load the quick create launcher flyout.
    console.log("Opening Case - Quick Create Form");
	await waitForQuickCreateFormLoad(page);
    console.log("Creating Case - Customer, Title and Description");
    await page.locator(QuickCreateCaseFormSelectors.CaseTitleSelector).click();
    await page.locator(QuickCreateCaseFormSelectors.CaseTitleSelector).fill('Quick Case Create Test '+ Math.floor((Math.random() * 100) + 1).toString());

    await page.locator(QuickCreateCaseFormSelectors.CustomerLookupSelector).click();
    await page.getByRole('button', { name: 'Search records for Customer, Lookup field' }).click();
    await page.getByRole('treeitem', { name: 'Fourth Coffee, claudia@pmgdemo.onmicrosoft.com' }).getByText('Fourth Coffee').click();
    
    await page.locator(QuickCreateCaseFormSelectors.DescriptionSelector).click();
    await page.locator(QuickCreateCaseFormSelectors.DescriptionSelector).fill('Quick Case Create: Having issues with Coffee machine.');
    await page.locator(QuickCreateCaseFormSelectors.SaveCloseButtonSelector).click();
    console.log("Creating Case using Quick Form");
});