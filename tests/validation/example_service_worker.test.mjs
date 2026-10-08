import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../mobile_flutter/web/example_service_worker.js', import.meta.url), 'utf8');
function handler() {
  const handlers = {};
  vm.runInNewContext(source, {
    URL,
    self: { location: { origin: 'https://my.example.com' }, addEventListener: (type, fn) => { handlers[type] = fn; } },
    caches: { open: async () => ({ match: async () => 'app shell' }) },
  });
  return handlers.fetch;
}

test('PDF navigation reaches the document server, not the cached app shell', () => {
  for (const path of ['/example-e-sign-consent.pdf', '/example-general-terms-us.pdf?v=1', '/legal/TERMS.PDF']) {
    let intercepted = false;
    handler()({ request: { method: 'GET', url: `https://my.example.com${path}`, mode: 'navigate' }, respondWith: () => { intercepted = true; } });
    assert.equal(intercepted, false);
  }
});

test('app navigation still uses the current release shell', async () => {
  let response;
  handler()({ request: { method: 'GET', url: 'https://my.example.com/signup', mode: 'navigate' }, respondWith: value => { response = value; } });
  assert.equal(await response, 'app shell');
});
