import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const bridges = readFileSync(new URL('../../web/app_bridges.js', import.meta.url), 'utf8');
const script = bridges.match(/\/\/ BEGIN startup-handoff([\s\S]*?)\/\/ END startup-handoff/)[1];
const html = readFileSync(new URL('../../web/index.html', import.meta.url), 'utf8');
const template = readFileSync(new URL('../../../scripts/branding/index.template.html', import.meta.url), 'utf8');

function startup({ present = true } = {}) {
  const listeners = new Map();
  const timers = [];
  let removed = false;
  const element = { remove() { removed = true; } };
  vm.runInNewContext(script, {
    window: { addEventListener(name, callback) { listeners.set(name, callback); } },
    document: { getElementById(id) {
      assert.equal(id, 'example-loading');
      return present && !removed ? element : null;
    } },
    setTimeout(callback) { timers.push(callback); },
  });
  return { listeners, timers, get removed() { return removed; } };
}

test('HTML loader stays until Flutter paints, then disappears in the same event', () => {
  const app = startup();
  assert.equal(app.removed, false, 'keep the loading view during engine startup');
  app.listeners.get('flutter-first-frame')();
  assert.equal(app.removed, true, 'never fade HTML over the Flutter loader');
  assert.equal(app.timers.length, 0, 'no delayed removal or loader overlap');
});

test('handoff tolerates an already removed HTML loader', () => {
  const app = startup({ present: false });
  assert.doesNotThrow(() => app.listeners.get('flutter-first-frame')());
});

test('generated and template loaders no longer fade over Flutter', () => {
  for (const source of [html, template]) {
    assert.doesNotMatch(source, /example-loading\.is-done/);
    assert.doesNotMatch(source, /#example-loading \{[^}]*transition:/);
  }
});
