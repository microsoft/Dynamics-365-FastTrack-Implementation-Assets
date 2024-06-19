import { chromium, FullConfig } from '@playwright/test';
import login from '../utils/login';
import * as dotenv from 'dotenv';
dotenv.config();

const authFile ='/storage-state/storageState.json';
const username = process.env.DYN365_USERNAME ?? '';
const password = process.env.DYN365_PASSWORD ?? '';
const orgurl = process.env.DYN365_ORGURL ?? '';

async function globalSetup(config: FullConfig): Promise<void> {
  const { storageState } = config.projects[0].use;
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();
  await login(page, orgurl as string, username, password);
  await page.context().storageState({
    path: authFile,
  });
  //await browser.close();
}

export default globalSetup;