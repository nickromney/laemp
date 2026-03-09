import { test, expect, type Page } from '@playwright/test';
import * as dotenv from 'dotenv';
import * as path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../../.env.test') });

const MOODLE_URL = process.env.MOODLE_URL || 'https://moodle.slicer.test.127.0.0.1.sslip.io';
const ADMIN_USERNAME = process.env.MOODLE_ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD = process.env.MOODLE_ADMIN_PASSWORD;

test.skip(!ADMIN_PASSWORD || ADMIN_PASSWORD === 'CHANGE_ME_FROM_CREDENTIALS_FILE',
  'Admin password not configured for Slicer smoke tests');

async function submitLoginForm(page: Page) {
  await page.locator('form#login').evaluate((form) => {
    (form as HTMLFormElement).requestSubmit();
  });
}

test.describe('Slicer Moodle Smoke', () => {
  test('loads homepage over HTTPS', async ({ page }) => {
    const response = await page.goto(MOODLE_URL);

    expect(response?.status()).toBe(200);
    await expect(page).toHaveTitle(/moodle\.test|Moodle/i);

    const bodyText = await page.textContent('body');
    expect(bodyText).not.toContain('Fatal error');
    expect(bodyText).not.toContain('database connection');
  });

  test('renders login page', async ({ page }) => {
    const response = await page.goto(`${MOODLE_URL}/login/index.php`);

    expect(response?.status()).toBe(200);
    await expect(page.locator('input#username')).toBeVisible();
    await expect(page.locator('input#password')).toBeVisible();
    await expect(page.locator('button#loginbtn')).toBeVisible();
  });

  test('allows admin login and access to site administration', async ({ page }) => {
    await page.goto(`${MOODLE_URL}/login/index.php`);
    await page.locator('form#login').evaluate((form, credentials) => {
      const username = form.querySelector('#username');
      const password = form.querySelector('#password');

      if (!(username instanceof HTMLInputElement) || !(password instanceof HTMLInputElement)) {
        throw new Error('Moodle login inputs not found.');
      }

      username.value = credentials.username;
      password.value = credentials.password;
    }, { username: ADMIN_USERNAME, password: ADMIN_PASSWORD! });
    await submitLoginForm(page);
    await page.waitForLoadState('networkidle');

    expect(page.url()).not.toContain('/login/index.php');

    await page.goto(`${MOODLE_URL}/admin/index.php`);
    await page.waitForLoadState('networkidle');

    const bodyText = await page.textContent('body');
    expect(bodyText).toContain('Site administration');
    expect(bodyText).toContain('General');
  });
});
