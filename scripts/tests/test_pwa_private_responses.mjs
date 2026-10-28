import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../mobile_flutter/web/example_service_worker.js', import.meta.url), 'utf8');
const origin = 'https://hoppa.roks.dev';

function worker() {
  const handlers = {};
  const entries = new Map();
  const deleted = [];
  let network = 0;
  let response = () => new Response('{}');
  const key = (request) => typeof request === 'string' ? request : request.url;
  const cache = {
    match: async (request) => entries.get(key(request))?.clone(),
    put: async (request, value) => entries.set(key(request), value),
    add: async (request) => entries.set(key(request), await fetch(request)),
  };
  const fetch = async () => { network++; return response(); };
  vm.runInNewContext(source, {
    URL,
    self: {
      location: { origin, href: `${origin}/example_service_worker.js` },
      addEventListener: (name, handler) => { handlers[name] = handler; },
      clients: { claim: async () => {} },
    },
    caches: {
      open: async () => cache,
      keys: async () => ['example-app-obsolete', 'example-app-v2'],
      delete: async (name) => { deleted.push(name); return true; },
    },
    fetch,
  });
  return {
    entries, deleted,
    get network() { return network; },
    respondWith: (fn) => { response = fn; },
    async read(path, options = {}) {
      const request = { url: origin + path, method: 'GET', mode: 'cors', headers: new Headers(), ...options };
      let intercepted;
      const pending = [];
      handlers.fetch({ request, respondWith: (promise) => { intercepted = promise; }, waitUntil: (promise) => pending.push(promise) });
      const result = await (intercepted ?? fetch(request));
      await Promise.all(pending);
      return result.json();
    },
    async event(name, data) {
      const pending = [];
      handlers[name]({ data, waitUntil: (promise) => pending.push(promise) });
      await Promise.all(pending);
    },
  };
}

test('invite request and admin approval always read fresh server state, ignoring old cached responses', async () => {
  const w = worker();
  const path = '/api/v1/mobile/onboarding/invite';
  w.entries.set(origin + path, new Response('{"inviteStatus":null}'));
  for (const status of [null, 'pending', 'approved', 'accepted']) {
    w.respondWith(() => Response.json({ inviteStatus: status }, { headers: { 'Cache-Control': 'no-store' } }));
    assert.equal((await w.read(path)).inviteStatus, status);
  }
  assert.equal(w.network, 4);
});

test('API navigation, account responses, deployment checks and authorized assets never use offline cache', async () => {
  const w = worker();
  for (const [path, options] of [
    ['/api/v1/mobile/onboarding/requirements', {}],
    ['/api/v1/mobile/banking/accounts', {}],
    ['/api/v1/mobile/onboarding/invite', { mode: 'navigate' }],
    ['/deployment.json', {}],
    ['/assets/private.json', { headers: new Headers({ Authorization: 'Bearer test-only' }) }],
  ]) {
    await w.read(path, options);
    await w.read(path, options);
  }
  assert.equal(w.network, 10);
  assert.equal(w.entries.size, 0);
});

test('public assets remain offline-capable, but private/no-store responses are never stored', async () => {
  const w = worker();
  await w.read('/assets/public.json');
  await w.read('/assets/public.json');
  assert.equal(w.network, 1);
  for (const control of ['no-store', 'private, max-age=300']) {
    w.respondWith(() => new Response('{}', { headers: { 'Cache-Control': control } }));
    await w.read('/assets/not-cached.json');
    await w.read('/assets/not-cached.json');
    assert.equal(w.entries.has(origin + '/assets/not-cached.json'), false);
  }
});

test('precache messages cannot add API/customer URLs; activation removes obsolete release caches', async () => {
  const w = worker();
  await w.event('message', { type: 'precache', urls: [
    origin + '/api/v1/mobile/onboarding/invite', origin + '/customer.json',
    origin + '/canvaskit-ab12/canvaskit.wasm',
  ] });
  assert.deepEqual([...w.entries.keys()], [origin + '/canvaskit-ab12/canvaskit.wasm']);
  await w.event('activate');
  assert.deepEqual(w.deleted, ['example-app-obsolete']);
});
