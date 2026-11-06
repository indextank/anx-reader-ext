/*
 * Playwright driver for the TTS highlight-sync browser evidence.
 * Run from the repository root:
 *
 *   npx --yes --package @playwright/cli playwright-cli run-code --filename assets/foliate-js/debug-books/run-evidence.js
 *
 * The CLI invokes this function with a Playwright `page` object. Every scenario
 * runs on a freshly reloaded synthetic book (debug-books/sync-test.epub) so the
 * reader state is deterministic. Screenshots land in docs/tts-round2/assets/.
 */

async (page) => {
  const HARNESS_URL = 'http://127.0.0.1:3000/debug-books/harness.html';
  const SHOT_DIR = 'docs/tts-round2/assets';
  const SHOT_TIMEOUT = 30000;

  const shot = async (name) => {
    await page.screenshot({
      path: `${SHOT_DIR}/${name}.png`,
      timeout: SHOT_TIMEOUT,
    });
  };

  const prepare = async () => {
    await page.goto(HARNESS_URL, { waitUntil: 'load' });
    await page.waitForFunction(
      () => !!(window.reader && window.reader.view &&
        window.reader.view.lastLocation && window.reader.view.renderer),
      undefined,
      { timeout: SHOT_TIMEOUT },
    );
    await page.addScriptTag({
      path: 'assets/foliate-js/debug-books/sync-tests.js',
    });
    await page.evaluate(() => window.__anxSync.waitReady());
    // The initial renderer page turn holds the paginator lock for a few frames;
    // programmatic navigation would be ignored during that window.
    await page.evaluate(() => window.__anxSync.waitUnlocked());
    await page.waitForTimeout(150);
  };

  const results = {};

  // (a) same-section manual page turn -> highlight pulls the page back
  await prepare();
  const sameSection = await page.evaluate(
    () => window.__anxSync.sameSectionPhase1());
  await shot('01-user-paged-away-same-section');
  results.sameSection = await page.evaluate(
    (state) => window.__anxSync.sameSectionPhase2(state), sameSection);
  await shot('02-highlight-pulled-back-same-section');

  // (b) annotation / footnote link exclusion
  await prepare();
  results.annotation = await page.evaluate(
    () => window.__anxSync.annotationExclusion());
  await shot('03-annotation-excluded');

  // (c) repeated highlight does not leave the previous sentence behind
  await prepare();
  results.repeated = await page.evaluate(
    () => window.__anxSync.repeatedHighlight());
  await shot('04-repeated-highlight-no-stale');

  // (c) page-split sentence: .a page then .b page
  await prepare();
  results.pageSplit = await page.evaluate(
    () => window.__anxSync.pageSplit());
  await shot('05-page-split-b-half');

  // (d) cross-section manual navigation -> pull back + iterator preserved
  await prepare();
  const cross = await page.evaluate(
    () => window.__anxSync.crossSectionPhase1());
  await shot('06-user-away-cross-section');
  results.crossSection = await page.evaluate(
    (state) => window.__anxSync.crossSectionPhase2(state), cross);
  await shot('07-highlight-pulled-back-cross-section');

  // (e) ttsStop clears the overlay
  await prepare();
  results.stop = await page.evaluate(() => window.__anxSync.stopClears());
  await shot('08-ttsstop-cleared');

  // (f) bridge latency against the Dart-side 800 ms bound
  await prepare();
  results.latency = await page.evaluate(() => window.__anxSync.latencyProbe());

  const pass = Object.keys(results).every((key) => results[key].pass);
  const report = { pass, results };
  try {
    const fs = require('fs');
    fs.writeFileSync(
      'docs/tts-round2/assets/browser-evidence.json',
      JSON.stringify(report, null, 2),
    );
  } catch (e) {
    // The CLI sandbox may not expose fs; the return value still carries the
    // complete report.
  }
  return report;
}
