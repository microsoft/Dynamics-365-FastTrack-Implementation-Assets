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
// Name: Navigate to Customer Service App
// Description: This test is validate the user can access and navigate 
// to Omnichannel for Customer Service App
// =====================================================================
import { expect, test } from '@playwright/test';
import { navigateToApps, stringFormat, waitUntilAppIdle } from '../utils/common';
test('Navigate to Customer Service Hub', async ({ page, }) => {
  let appId = process.env.CSW_APPID as string;
  await navigateToApps(page, stringFormat(appId) ,'Customer Service Hub');
});
