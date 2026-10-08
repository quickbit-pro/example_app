import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import vm from 'node:vm';

const html = readFileSync(new URL('../../web/index.html', import.meta.url), 'utf8');
const source = html.match(/<script id="brand-boot-theme">([\s\S]*?)<\/script>/)[1];

function boot({saved = null, systemLight = true, storageBlocked = false, theme = 'system'} = {}) {
  const root = {dataset: {}};
  const meta = {};
  const localStorage = {
    getItem(key) {
      assert.equal(key, 'flutter.app.themeMode.v1');
      if (storageBlocked) throw new Error('Storage blocked');
      return saved;
    },
  };
  const context = {
    window: {}, localStorage,
    matchMedia: () => ({matches: systemLight}),
    document: {documentElement: root, querySelector: () => meta},
  };
  const script = source.replace(/"theme": "[^"]+"/, '"theme": ' + JSON.stringify(theme));
  vm.runInNewContext(script, context);
  return {theme: root.dataset.brandTheme, themeColor: meta.content, brand: context.window.APP_BRAND};
}

test('first visit follows the configured default theme', () => {
  for (const theme of ['light', 'dark', 'system']) {
    for (const systemLight of [true, false]) {
      const result = boot({theme, systemLight});
      const expected = theme === 'system' ? (systemLight ? 'light' : 'dark') : theme;
      assert.equal(result.theme, expected);
      assert.equal(result.themeColor, result.brand[expected === 'light' ? 'backgroundLight' : 'backgroundDark']);
    }
  }
});

test('saved explicit light and dark preferences override the config and device', () => {
  for (const saved of ['light', 'dark']) {
    for (const systemLight of [true, false]) {
      assert.equal(boot({saved: JSON.stringify(saved), systemLight}).theme, saved);
    }
  }
});

test('saved system preference follows device brightness', () => {
  for (const systemLight of [true, false]) {
    assert.equal(boot({saved: '"system"', theme: 'dark', systemLight}).theme,
      systemLight ? 'light' : 'dark');
  }
});

test('blocked storage and invalid preferences fall back to the configured default', () => {
  for (const options of [{storageBlocked: true}, {saved: 'invalid json'}, {saved: '"unknown"'}]) {
    assert.equal(boot({...options, theme: 'light', systemLight: false}).theme, 'light');
    assert.equal(boot({...options, theme: 'dark', systemLight: true}).theme, 'dark');
  }
});

test('the loading shell includes dark logo selection and reduced motion', () => {
  assert.match(html, /data-brand-theme="dark".*brand-logo-dark/);
  assert.match(html, /prefers-reduced-motion: reduce/);
  assert.match(html, /app_bridges\.js/);
  assert.match(html, /app_recovery\.js/);
  assert.doesNotMatch(html, /<title>Example|Example banking|ld-wordmark/);
});
