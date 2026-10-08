import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

const script = readFileSync(new URL('../../web/app_bridges.js', import.meta.url), 'utf8')
  .split('// Sumsub WebSDK')[0];
function setup() {
  const saved = new Map([['hoppa.biometric.credential', btoa('credential')]]);
  const pending = [];
  const request = options => new Promise(resolve => pending.push({ options, resolve }));
  const window = { APP_BRAND: { id: 'hoppa', name: 'Hoppa' } };
  vm.runInNewContext(script, {
    window, AbortController, btoa, atob, Uint8Array, crypto: webcrypto,
    location: { hostname: 'hoppa.roks.dev' },
    navigator: { credentials: { create: request, get: request } },
    localStorage: {
      getItem: key => saved.get(key), setItem: (key, value) => saved.set(key, value),
      removeItem: key => saved.delete(key),
    },
  });
  return { gate: window.exampleBiometrics, pending, saved };
}

test('password fallback aborts a pending verification and ignores late success', async () => {
  const { gate, pending } = setup();
  const result = gate.verify();
  gate.cancel();
  assert.equal(pending[0].options.signal.aborted, true);
  pending[0].resolve({});
  assert.equal(await result, 'cancelled');
});

test('cancelled registration cannot replace the saved credential', async () => {
  const { gate, pending, saved } = setup();
  const result = gate.register('Tester');
  gate.cancel();
  assert.equal(pending[0].options.signal.aborted, true);
  pending[0].resolve({ rawId: new Uint8Array([1, 2, 3]).buffer });
  assert.equal(await result, false);
  assert.equal(saved.get('hoppa.biometric.credential'), btoa('credential'));
});

test('late completion of a cancelled prompt cannot cancel its replacement', async () => {
  const { gate, pending } = setup();
  const first = gate.verify();
  const second = gate.verify();
  assert.equal(pending[0].options.signal.aborted, true);
  pending[0].resolve({});
  assert.equal(await first, 'cancelled');
  gate.cancel();
  assert.equal(pending[1].options.signal.aborted, true);
  pending[1].resolve({});
  assert.equal(await second, 'cancelled');
});
