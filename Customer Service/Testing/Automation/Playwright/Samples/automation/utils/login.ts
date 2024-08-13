import { Page } from '@playwright/test';

async function login(
  page: Page,
  orgurl: string,
  username: string,
  password: string,

): Promise<void> {
  await page.goto(orgurl);
  await page.getByPlaceholder('Email, phone, or Skype').click();
  await page.getByPlaceholder('Email, phone, or Skype').fill(username);
  await page.getByRole('button', { name: 'Next' }).click();
  await page.getByPlaceholder('Password').click();
  await page.getByPlaceholder('Password').fill(password);
  await Promise.all([
    page.waitForNavigation(),
    await page.getByRole('button', { name: 'Sign in' }).click(),
    await page.getByRole('button', { name: 'Yes' }).click(),
  ]);
}

export default login;