import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import vm from 'node:vm';
import '../customer-guide/file-tools.js';

const { makeZip, readZip, safeAssetName, bytesToBase64, base64ToBytes } = globalThis.BrandGuideFiles;
const decoder = new TextDecoder();

test('standalone script installs an immutable API without DOM, Node, or network APIs', () => {
  const context = vm.createContext({ TextEncoder, TextDecoder, Uint8Array, Uint32Array, DataView });
  vm.runInContext(readFileSync(new URL('../customer-guide/file-tools.js', import.meta.url), 'utf8'), context);
  assert.deepEqual(Object.keys(context.BrandGuideFiles).sort(), [
    'base64ToBytes', 'bytesToBase64', 'makeZip', 'readZip', 'safeAssetName',
  ]);
  assert.equal(Object.isFrozen(context.BrandGuideFiles), true);
  assert.equal(context.BrandGuideFiles.bytesToBase64(new Uint8Array([0, 255])), 'AP8=');
});

test('ZIP headers contain a correct known CRC, UTF-8 flag, STORE mode, and directory offsets', () => {
  const bytes = makeZip([{ name: 'config.json', bytes: '123456789' }]);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const central = 30 + 'config.json'.length + 9;
  const end = central + 46 + 'config.json'.length;
  assert.equal(view.getUint32(0, true), 0x04034b50);
  assert.equal(view.getUint16(6, true), 0x0800);
  assert.equal(view.getUint16(8, true), 0);
  assert.equal(view.getUint16(12, true), 0x0021);
  assert.equal(view.getUint32(14, true), 0xcbf43926);
  assert.equal(view.getUint32(18, true), 9);
  assert.equal(view.getUint32(22, true), 9);
  assert.equal(view.getUint16(26, true), 'config.json'.length);
  assert.equal(decoder.decode(bytes.subarray(30, 41)), 'config.json');
  assert.equal(decoder.decode(bytes.subarray(41, 50)), '123456789');
  assert.equal(view.getUint32(central, true), 0x02014b50);
  assert.equal(view.getUint32(central + 16, true), 0xcbf43926);
  assert.equal(view.getUint32(central + 42, true), 0);
  assert.equal(view.getUint32(end, true), 0x06054b50);
  assert.equal(view.getUint16(end + 8, true), 1);
  assert.equal(view.getUint16(end + 10, true), 1);
  assert.equal(view.getUint32(end + 12, true), 46 + 'config.json'.length);
  assert.equal(view.getUint32(end + 16, true), central);
  assert.equal(bytes.length, end + 22);
  assert.deepEqual(makeZip([{ name: 'config.json', bytes: '123456789' }]), bytes);
});

test('ZIP round-trips UTF-8 paths, text, binary data, empty files, and byte-array views through Python zipfile', () => {
  const temporary = mkdtempSync(join(tmpdir(), 'customer-guide-zip-'));
  try {
    const input = new Uint8Array([99, 0, 255, 1, 2, 3, 88]);
    const entries = [
      { name: 'config.json', bytes: '{"name":"Hoppá 🚀"}\n' },
      { name: 'assets/čebelica 🐝.png', bytes: input.subarray(1, 6) },
      { name: 'assets/empty.txt', bytes: '' },
      { name: 'README.txt', bytes: 'First line\nSecond line\n' },
    ];
    const archivePath = join(temporary, 'handoff.zip');
    writeFileSync(archivePath, makeZip(entries));
    const check = spawnSync('python3', ['-c', `
import base64, json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None
    result = []
    for info in archive.infolist():
        assert info.compress_type == zipfile.ZIP_STORED
        assert info.flag_bits & 0x800
        assert info.date_time == (1980, 1, 1, 0, 0, 0)
        assert not info.is_dir()
        result.append({"name": info.filename, "base64": base64.b64encode(archive.read(info)).decode("ascii")})
print(json.dumps(result))
`, archivePath], { encoding: 'utf8' });
    assert.equal(check.error, undefined, `Python zipfile validation could not start: ${check.error}`);
    assert.equal(check.status, 0, check.stderr);
    assert.deepEqual(JSON.parse(check.stdout), entries.map(({ name, bytes }) => ({
      name,
      base64: Buffer.from(bytes).toString('base64'),
    })));
    assert.deepEqual(input, new Uint8Array([99, 0, 255, 1, 2, 3, 88]));
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('empty ZIP archives contain only a valid end-of-central-directory record', () => {
  const archive = makeZip([]);
  assert.equal(archive.length, 22);
  const view = new DataView(archive.buffer);
  assert.equal(view.getUint32(0, true), 0x06054b50);
  assert.equal(view.getUint16(10, true), 0);
  assert.equal(view.getUint32(12, true), 0);
  assert.equal(view.getUint32(16, true), 0);
});

test('unsafe, ambiguous, and malformed ZIP paths are rejected before archive creation', () => {
  const invalid = [
    '', '/', '/root/file', '\\root\\file', 'C:/file', 'C:file', 'a\\b',
    '../file', 'a/../file', './file', 'a/./file', 'a//file', 'a/', '.', '..',
    'a\0b', 'a\nb', 'a\tb', 'a\u007fb', 'a\ud800b', 'a\udc00b',
  ];
  for (const name of invalid) {
    assert.throws(() => makeZip([{ name, bytes: '' }]), /path|Unicode/i, JSON.stringify(name));
  }
  assert.throws(() => makeZip([{ name: 123, bytes: '' }]), /path/i);
  assert.doesNotThrow(() => makeZip([{ name: 'assets/../not-a-path.txt'.replace('../', 'dots-'), bytes: '' }]));
});

test('duplicate files and file-versus-directory collisions are rejected in either order', () => {
  assert.throws(() => makeZip([
    { name: 'config.json', bytes: 'one' }, { name: 'config.json', bytes: 'two' },
  ]), /Duplicate ZIP entry/);
  for (const names of [['assets', 'assets/logo.png'], ['assets/logo.png', 'assets']]) {
    assert.throws(() => makeZip(names.map((name) => ({ name, bytes: '' }))), /both a file and a directory/);
  }
});

test('ZIP validates input types and rejects ZIP64 size, count, and name requirements', () => {
  for (const entries of [null, {}, 'file']) assert.throws(() => makeZip(entries), /array/);
  assert.throws(() => makeZip(new Array(1)), /entry/);
  for (const entry of [null, 123, {}]) assert.throws(() => makeZip([entry]), /entry|path/);
  for (const bytes of [null, undefined, [1, 2], new ArrayBuffer(3), new Uint16Array(3)]) {
    assert.throws(() => makeZip([{ name: 'file', bytes }]), /Uint8Array/);
  }
  assert.throws(() => makeZip(new Array(0xffff)), /65,534 files/);
  assert.throws(() => makeZip([{ name: 'é'.repeat(32768), bytes: '' }]), /65,535 UTF-8 bytes/);
  class FileTooLarge extends Uint8Array { get byteLength() { return 0xffffffff; } }
  class HalfArchive extends Uint8Array { get byteLength() { return 0x80000000; } }
  assert.throws(() => makeZip([{ name: 'huge.bin', bytes: new FileTooLarge(0) }]), /32-bit size/);
  assert.throws(() => makeZip([
    { name: 'one.bin', bytes: new HalfArchive(0) },
    { name: 'two.bin', bytes: new HalfArchive(0) },
  ]), /32-bit size/);
});

test('asset names become predictable portable ASCII filenames with approved extensions', () => {
  const cases = [
    ['My Customer Logo.PNG', 'my-customer-logo.png'],
    ['Crème brûlée.jpeg', 'creme-brulee.jpeg'],
    ['../../logo..final.WebP', 'logo-final.webp'],
    ['C:\\fakepath\\Splash Screen.GIF', 'splash-screen.gif'],
    ['Inter_Bold.TTF', 'inter_bold.ttf'],
    ['Brand Font.OTF', 'brand-font.otf'],
    ['License.TXT', 'license.txt'],
    ['GoogleService-Info.PLIST', 'googleservice-info.plist'],
    ['Config.JSON', 'config.json'],
    ['.hidden.png', 'hidden.png'],
    ['紫色.png', 'asset.png'],
    ['CON.png', 'asset-con.png'],
    ['lpt9.jpg', 'asset-lpt9.jpg'],
    ['a'.repeat(100) + '.png', 'a'.repeat(80) + '.png'],
  ];
  for (const [input, expected] of cases) {
    assert.equal(safeAssetName(input), expected);
    assert.match(safeAssetName(input), /^[a-z0-9][a-z0-9_-]*\.[a-z]+$/);
    assert.equal(safeAssetName(input).includes('..'), false);
    assert.equal(safeAssetName(safeAssetName(input)), expected);
  }
  for (const name of ['', ' ', null, 'missing-extension', 'file.svg', 'file.html', 'file.exe', '.png', 'bad\0.png']) {
    assert.throws(() => safeAssetName(name), /filename|extension/i);
  }
});

test('Base64 helpers round-trip binary data including empty, padded, and multi-chunk input', () => {
  for (const length of [0, 1, 2, 3, 4, 16, 255, 256, 257, 65535, 65536, 100001]) {
    const bytes = Uint8Array.from({ length }, (_, index) => (index * 37 + 127) & 255);
    const encoded = bytesToBase64(bytes);
    assert.equal(encoded, Buffer.from(bytes).toString('base64'));
    assert.deepEqual(base64ToBytes(encoded), bytes);
  }
  const view = new Uint8Array([1, 2, 3, 4, 5]).subarray(1, 4);
  assert.equal(bytesToBase64(view), 'AgME');
  assert.throws(() => bytesToBase64([1, 2]), /Uint8Array/);
});

test('Base64 parser rejects malformed text and noncanonical padding', () => {
  for (const text of [null, 123, 'A', 'AAA', '====', 'A===', 'AA=A', 'AA==\n', 'A A=', '____', 'AB==', 'AAB=', 'éééé']) {
    assert.throws(() => base64ToBytes(text), /Base64|padding/, JSON.stringify(text));
  }
});

function zipRecords(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const end = bytes.length - 22;
  const count = view.getUint16(end + 10, true);
  let central = view.getUint32(end + 16, true);
  const records = [];
  for (let index = 0; index < count; index += 1) {
    const nameLength = view.getUint16(central + 28, true);
    const local = view.getUint32(central + 42, true);
    records.push({ central, local, nameLength, data: local + 30 + nameLength });
    central += 46 + nameLength;
  }
  return { view, end, records };
}

function renameZipEntry(bytes, index, nameBytes) {
  const { records } = zipRecords(bytes);
  const record = records[index];
  const encoded = typeof nameBytes === 'string' ? new TextEncoder().encode(nameBytes) : nameBytes;
  assert.equal(encoded.length, record.nameLength);
  bytes.set(encoded, record.local + 30);
  bytes.set(encoded, record.central + 46);
}

test('readZip restores guide exports, empty files, Unicode names, and byte-array views without aliases', () => {
  const entries = [
    { name: 'config.json', bytes: '{"app":{"name":"客户 🚀"}}\n' },
    { name: 'assets/čebelica 🐝.png', bytes: new Uint8Array([0, 255, 42, 5]) },
    { name: 'empty.txt', bytes: '' },
  ];
  const archive = makeZip(entries);
  const padded = new Uint8Array(archive.length + 10);
  padded.set(archive, 5);
  const result = readZip(padded.subarray(5, padded.length - 5));
  assert.deepEqual(result, entries.map(({ name, bytes }) => ({
    name, bytes: typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes,
  })));
  padded.fill(0);
  assert.equal(decoder.decode(result[0].bytes), entries[0].bytes);
  result[1].bytes[0] = 99;
  assert.equal(entries[1].bytes[0], 0);
  assert.deepEqual(readZip(makeZip([])), []);
});

test('readZip rejects traversal, absolute, backslash, duplicate, directory-collision, and invalid UTF-8 names', () => {
  for (const name of ['../a.txt', '/bad.txt', 'a\\aa.txt', 'a\0aa.txt']) {
    const archive = makeZip([{ name: 'safe.txt', bytes: 'hello' }]);
    renameZipEntry(archive, 0, name);
    assert.throws(() => readZip(archive), /Unsafe ZIP path/);
  }
  const invalidUtf8 = makeZip([{ name: 'a.txt', bytes: '' }]);
  renameZipEntry(invalidUtf8, 0, new Uint8Array([0xff, 46, 116, 120, 116]));
  assert.throws(() => readZip(invalidUtf8), /valid UTF-8/);
  const duplicate = makeZip([{ name: 'a.txt', bytes: '' }, { name: 'b.txt', bytes: '' }]);
  renameZipEntry(duplicate, 1, 'a.txt');
  assert.throws(() => readZip(duplicate), /Duplicate ZIP entry/);
  for (const [entries, renameIndex, replacement] of [
    [[{ name: 'one', bytes: '' }, { name: 'two/x', bytes: '' }], 1, 'one/x'],
    [[{ name: 'one/x', bytes: '' }, { name: 'two', bytes: '' }], 1, 'one'],
  ]) {
    const collision = makeZip(entries);
    renameZipEntry(collision, renameIndex, replacement);
    assert.throws(() => readZip(collision), /both a file and a directory/);
  }
});

test('readZip verifies file data CRCs and both copies of header metadata and filenames', () => {
  const original = makeZip([{ name: 'a.txt', bytes: 'hello' }]);
  const corrupt = original.slice();
  const { records: [record] } = zipRecords(corrupt);
  corrupt[record.data] ^= 0xff;
  assert.throws(() => readZip(corrupt), /CRC32 checksum/);
  for (const [offset, size] of [[14, 4], [18, 4], [22, 4], [4, 2], [6, 2], [8, 2], [10, 2], [12, 2], [26, 2], [28, 2]]) {
    const changed = original.slice();
    const { view, records: [entry] } = zipRecords(changed);
    if (size === 4) view.setUint32(entry.local + offset, view.getUint32(entry.local + offset, true) ^ 1, true);
    else view.setUint16(entry.local + offset, view.getUint16(entry.local + offset, true) ^ 1, true);
    assert.throws(() => readZip(changed), /headers do not match/);
  }
  const wrongName = original.slice();
  wrongName[30] = 98;
  assert.throws(() => readZip(wrongName), /filenames do not match/);
  const wrongBothCrcs = original.slice();
  const { view, records: [entry] } = zipRecords(wrongBothCrcs);
  view.setUint32(entry.local + 14, 0, true);
  view.setUint32(entry.central + 16, 0, true);
  assert.throws(() => readZip(wrongBothCrcs), /CRC32 checksum/);
});

test('readZip rejects compressed, encrypted, multidisk, ZIP64, descriptor, and extra-field variants', () => {
  const original = makeZip([{ name: 'a.txt', bytes: 'hello' }]);
  const cases = [
    [(v, r) => v.setUint16(r.central + 10, 8, true), /Compressed ZIP/],
    [(v, r) => v.setUint16(r.central + 8, 0x0801, true), /Encrypted ZIP/],
    [(v, r) => v.setUint16(r.central + 8, 0x0840, true), /Encrypted ZIP/],
    [(v, r, e) => v.setUint16(e + 4, 1, true), /Multidisk/],
    [(v, r) => v.setUint16(r.central + 34, 1, true), /Multidisk/],
    [(v, r, e) => { v.setUint16(e + 8, 0xffff, true); v.setUint16(e + 10, 0xffff, true); }, /ZIP64/],
    [(v, r, e) => v.setUint32(e + 12, 0xffffffff, true), /ZIP64/],
    [(v, r, e) => v.setUint32(e + 16, 0xffffffff, true), /ZIP64/],
    [(v, r) => v.setUint32(r.central + 24, 0xffffffff, true), /ZIP64/],
    [(v, r) => v.setUint32(r.central + 42, 0xffffffff, true), /ZIP64/],
    [(v, r) => v.setUint16(r.central + 6, 45, true), /ZIP64/],
    [(v, r) => v.setUint16(r.central + 8, 0x0808, true), /unsupported ZIP flags/],
    [(v, r) => v.setUint16(r.central + 30, 1, true), /extra fields/],
    [(v, r) => v.setUint16(r.central + 32, 1, true), /file comments/],
  ];
  for (const [mutate, pattern] of cases) {
    const archive = original.slice();
    const { view, end, records: [entry] } = zipRecords(archive);
    mutate(view, entry, end);
    assert.throws(() => readZip(archive), (error) => pattern.test(error.message)
      && /Only uncompressed ZIP bundles exported by this guide are supported/.test(error.message));
  }
});

test('readZip rejects truncations, inconsistent offsets and sizes, overlap, trailing data, and invalid input', () => {
  const original = makeZip([{ name: 'a.txt', bytes: 'hello' }, { name: 'b.txt', bytes: 'world' }]);
  for (const length of [0, 1, 21, 22, 30, 40, 80, original.length - 1]) {
    assert.throws(() => readZip(original.subarray(0, length)), /truncated|end record/i);
  }
  const mutations = [
    (v, rs, e) => v.setUint32(e + 16, v.getUint32(e + 16, true) + 1, true),
    (v, rs, e) => v.setUint32(e + 12, 0, true),
    (v, rs) => v.setUint32(rs[1].central + 42, rs[0].local, true),
    (v, rs) => v.setUint32(rs[0].central + 20, 4, true),
    (v, rs, e) => { v.setUint16(e + 8, 1, true); v.setUint16(e + 10, 1, true); },
    (v, rs) => v.setUint16(rs[0].central + 28, 0xffff, true),
    (v, rs) => v.setUint32(rs[0].local, 0, true),
    (v, rs) => v.setUint32(rs[0].central, 0, true),
  ];
  for (const mutate of mutations) {
    const archive = original.slice();
    const { view, end, records } = zipRecords(archive);
    mutate(view, records, end);
    assert.throws(() => readZip(archive), /Cannot import this ZIP/);
  }
  const trailing = new Uint8Array(original.length + 1);
  trailing.set(original);
  assert.throws(() => readZip(trailing), /end record/);
  for (const invalid of [null, undefined, [], new ArrayBuffer(22)]) {
    assert.throws(() => readZip(invalid), /Uint8Array/);
  }
});

test('readZip enforces the 100 MiB archive and total extracted-data limits before copying files', () => {
  class OversizedArchive extends Uint8Array { get byteLength() { return 100 * 1024 * 1024 + 1; } }
  assert.throws(() => readZip(new OversizedArchive(0)), /100 MiB import limit/);
  const archive = makeZip([{ name: 'a.txt', bytes: '' }]);
  const { view, records: [entry] } = zipRecords(archive);
  view.setUint32(entry.central + 20, 100 * 1024 * 1024 + 1, true);
  view.setUint32(entry.central + 24, 100 * 1024 * 1024 + 1, true);
  assert.throws(() => readZip(archive), /Extracted files exceed the 100 MiB/);
});
