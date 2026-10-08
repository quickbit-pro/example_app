import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
async function load(file) {
  const source = readFileSync(new URL(`../src/lib/${file}`, import.meta.url), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 } }).outputText;
  return import('data:text/javascript;base64,' + Buffer.from(js).toString('base64'));
}
const { filterUsers, userLabel, debounce } = await load('userPicker.ts');
const users = [{ Id: 12, Name: 'Ada Lovelace', Email: 'ada@example.test' }, { Id: 7, Name: 'Grace Hopper', Email: 'grace@navy.mil' }, { Id: 99, Name: '', Email: 'nameless@example.test' }];

test('userLabel joins name and email and tolerates missing parts', () => {
  assert.equal(userLabel(users[0]), 'Ada Lovelace · ada@example.test');
  assert.equal(userLabel(users[2]), 'nameless@example.test');
  assert.equal(userLabel(null), '');
});

test('filterUsers matches name, email or #id case-insensitively; empty keeps all', () => {
  assert.equal(filterUsers(users, '').length, 3);
  assert.deepEqual(filterUsers(users, 'ADA').map(u => u.Id), [12]);
  assert.deepEqual(filterUsers(users, 'navy').map(u => u.Id), [7]);
  assert.deepEqual(filterUsers(users, '#99').map(u => u.Id), [99]);
  assert.deepEqual(filterUsers(users, 'nobody'), []);
});

test('debounce fires once after the delay and can be cancelled', async () => {
  let calls = 0; const d = debounce(() => { calls += 1; }, 20);
  d.call(); d.call(); d.call();
  await new Promise(r => setTimeout(r, 40));
  assert.equal(calls, 1);
  d.call(); d.cancel();
  await new Promise(r => setTimeout(r, 40));
  assert.equal(calls, 1);
});
