import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
async function load(file) {
  const source = readFileSync(new URL(`../src/lib/${file}`, import.meta.url), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
  return import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}
const { activeDeviceLabels, describeUserAgent, hiddenCurrencies, messageStatusLabel, platformLabel, sessionActive, ticketStatusLabel } = await load('customerAccess.ts');
const now = Date.parse('2026-09-11T12:00:00Z');

test('describeUserAgent', () => {
  assert.equal(describeUserAgent('HoppaApp/1.6.0 (iPhone; iOS 18.1)'), 'Hoppa app 1.6.0');
  assert.equal(describeUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1'), 'iPhone');
  assert.equal(describeUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'), 'Chrome on Mac');
  assert.equal(describeUserAgent('Mozilla/5.0 (Linux; Android 14) Chrome/128.0 Mobile Safari/537.36'), 'Android');
  assert.equal(describeUserAgent(null), 'Unknown device');
});

test('sessionActive and activeDeviceLabels', () => {
  assert.equal(sessionActive({ expiresAt: '2026-10-01T00:00:00Z', revokedAt: null }, now), true);
  assert.equal(sessionActive({ expiresAt: '2026-01-01T00:00:00Z', revokedAt: null }, now), false);
  assert.equal(sessionActive({ expiresAt: '2026-10-01T00:00:00Z', revokedAt: '2026-09-01T00:00:00Z' }, now), false);
  assert.deepEqual(activeDeviceLabels([
    { deviceName: 'iPhone 15', userAgent: null, expiresAt: '2026-10-01T00:00:00Z', revokedAt: null },
    { deviceName: null, userAgent: 'Mozilla/5.0 (Macintosh) Chrome/128.0 Safari/537.36', expiresAt: '2026-10-01T00:00:00Z', revokedAt: null },
    { deviceName: 'iPhone 15', userAgent: null, expiresAt: '2026-10-01T00:00:00Z', revokedAt: null },
    { deviceName: 'Old', userAgent: null, expiresAt: '2026-01-01T00:00:00Z', revokedAt: null },
  ], now), ['iPhone 15', 'Chrome on Mac']);
});

test('labels', () => {
  assert.deepEqual(hiddenCurrencies([{ currency: 'eur' }, { currency: 'USD' }, { currency: 'aed' }, { currency: 'HUF' }]), ['AED', 'HUF']);
  assert.deepEqual(hiddenCurrencies([{ currency: 'EUR' }]), []);
  assert.deepEqual(ticketStatusLabel('awaiting_support'), { label: 'Awaiting support', tone: 'warning' });
  assert.deepEqual(ticketStatusLabel('awaiting_user'), { label: 'Awaiting customer', tone: 'neutral' });
  assert.deepEqual(messageStatusLabel('sent'), { label: 'Delivered', tone: 'success' });
  assert.deepEqual(messageStatusLabel('failed'), { label: 'Failed', tone: 'danger' });
  assert.deepEqual(messageStatusLabel('pending'), { label: 'Sending', tone: 'neutral' });
  assert.equal(platformLabel('ios'), 'iOS'); assert.equal(platformLabel('android'), 'Android'); assert.equal(platformLabel('huawei'), 'Huawei');
});
