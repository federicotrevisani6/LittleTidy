// Renders every screen in source/screens.html to PNG, light and dark (2x).
// Needs playwright-core and an installed Chrome. Run from this folder:
//   NODE_PATH=<dir with playwright-core>/node_modules node tools/render.mjs [screen ...]
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');

const here = path.dirname(fileURLToPath(import.meta.url));
const page_url = pathToFileURL(path.join(here, '..', 'source', 'screens.html')).href;
const out = path.join(here, '..', 'screens');
const all = ['home-ready', 'home-min-window', 'home-scanning', 'home-before-scan', 'card-states',
  'confirm-clean-safely', 'cleanup-result', 'empty-trash-confirm', 'empty-trash-done'];
const only = process.argv.slice(2);
const screens = only.length ? only : all;

const browser = await chromium.launch({ channel: 'chrome' });
const ctx = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 1500, height: 1200 } });
import fs from 'node:fs';
const symDir = path.join(here, '..', 'source', 'symbols');
const SYMBOLS = {};
for (const f of fs.readdirSync(symDir)) if (f.endsWith('.png')) SYMBOLS[f.slice(0, -4)] = 'data:image/png;base64,' + fs.readFileSync(path.join(symDir, f)).toString('base64');
const page = await ctx.newPage();
await page.addInitScript((m) => { window.SYMBOLS = m; }, SYMBOLS);
for (const s of screens) {
  for (const theme of ['light', 'dark']) {
    await page.goto(`${page_url}?screen=${s}&theme=${theme}`);
    await page.waitForTimeout(250);
    await page.locator('#shot').screenshot({ path: path.join(out, `${s}-${theme}.png`) });
  }
}
await page.goto(`${page_url}?screen=home-ready&theme=light&contrast=1`);
await page.waitForTimeout(250);
await page.locator('#shot').screenshot({ path: path.join(out, 'home-ready-increased-contrast-light.png') });
await browser.close();
console.log('done');
