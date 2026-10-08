import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import '../customer-guide/config-engine.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const engine = globalThis.BrandGuideEngine;
const sample = JSON.parse(fs.readFileSync(path.join(root, 'mobile_flutter/config/sample.json'), 'utf8'));
const hoppa = JSON.parse(fs.readFileSync(path.join(root, 'mobile_flutter/config/hoppa.json'), 'utf8'));
const fixture = () => engine.clone(sample);
const set = (object, field, value) => {
  const keys = field.split('.');
  const last = keys.pop();
  const target = keys.reduce((current, key) => current[key], object);
  target[last] = value;
};
const hasError = (config, field, metadata) => engine.validateConfig(config, metadata).errors.some(error => error.path === field);

test('current sample and Hoppa configs validate without claiming local files exist', () => {
  for (const config of [sample, hoppa]) {
    const report = engine.validateConfig(config);
    assert.equal(report.valid, true, JSON.stringify(report.errors));
    assert.ok(report.assets.length >= 5);
    assert.ok(report.assets.every(asset => asset.status === 'unverified'));
    assert.ok(report.warnings.some(warning => warning.message.includes('File not verified')));
  }
});

test('import → edit identity → export preserves advanced tokens, fonts, Firebase and custom defines', () => {
  const imported = engine.clone(hoppa);
  imported.native.firebase = {android: 'assets/google-services.json', ios: 'assets/GoogleService-Info.plist'};
  imported.flutterDefines = {...imported.flutterDefines, FEATURE_CUSTOM: true, RETRY_COUNT: 3, FRACTION: 0.5, PUBLIC_LABEL: 'Customer <A> & B'};
  imported.design.light.cardOverlay = '#29aBcDeF';
  imported.design.dark.atmosphereMid = '#2F123456';
  const state = engine.init(imported);
  state.app.name = 'Customer Wallet';
  const output = engine.buildConfig(state);
  assert.equal(output.app.name, 'Customer Wallet');
  assert.deepEqual(output.design, imported.design);
  assert.deepEqual(output.fonts, imported.fonts);
  assert.deepEqual(output.native, imported.native);
  assert.deepEqual(output.flutterDefines, imported.flutterDefines);
  assert.equal(imported.app.name, 'Hoppa');
  assert.notEqual(output, state);
  assert.notEqual(output.design, state.design);
  assert.deepEqual(engine.buildConfig(JSON.parse(JSON.stringify(output))), output);
  assert.equal(engine.validateConfig(output).valid, true);
});

test('only actual Python defaults are filled; malformed fields are never coerced', () => {
  const input = fixture();
  for (const key of ['description', 'supportEmail', 'supportPhone', 'legalEntity', 'themeMode', 'transferDashboardUrl']) delete input.app[key];
  for (const key of ['typography', 'shape', 'loader', 'splash', 'motion', 'layout']) delete input.design[key];
  delete input.fonts;
  delete input.flutterDefines;
  delete input.native.iconBackground;
  delete input.native.firebase;
  const output = engine.buildConfig(input);
  assert.equal(output.app.themeMode, 'system');
  assert.deepEqual(output.design.typography, {fontFamily: '', monoFontFamily: '', scale: 1});
  assert.equal(output.design.splash.backgroundLight, input.design.light.paper);
  assert.equal(output.native.iconBackground, input.design.light.fill);
  assert.deepEqual(output.flutterDefines, {});
  assert.equal(engine.validateConfig(output).valid, true);
  assert.equal(input.design.loader, undefined);
  for (const bad of [null, false, '', 1, []]) {
    const config = fixture();
    config.design.motion = bad;
    assert.deepEqual(engine.buildConfig(config).design.motion, bad);
    assert.equal(hasError(config, 'design.motion'), true);
  }
});

test('all palette keys remain in sync with the Python validator', () => {
  const python = fs.readFileSync(path.join(root, 'scripts/prepare-mobile-brand.py'), 'utf8');
  const declared = python.match(/^PALETTE = set\('([^']+)'\.split\(\)\)/m)[1].split(' ');
  const optional = python.match(/^OPTIONAL_PALETTE = set\('([^']+)'\.split\(\)\)/m)[1].split(' ');
  assert.equal(declared.length, 44);
  assert.deepEqual([...engine.paletteKeys].sort(), declared.sort());
  assert.deepEqual([...engine.optionalPaletteKeys].sort(), optional.sort());
  assert.deepEqual(engine.fieldDescriptors.palette.map(field => field.path).sort(), [...engine.paletteKeys].sort());
  for (const mode of ['light', 'dark']) {
    for (const key of engine.requiredPaletteKeys) {
      const config = fixture(); delete config.design[mode][key];
      assert.equal(hasError(config, `design.${mode}.${key}`), true, `${mode}.${key}`);
    }
    const minimal = fixture();
    for (const key of engine.optionalPaletteKeys) delete minimal.design[mode][key];
    assert.equal(engine.validateConfig(minimal).valid, true);
  }
});

test('schema rejects unknown keys at every configurable object boundary', () => {
  for (const field of ['config', 'app', 'design', 'design.light', 'design.dark', 'design.typography', 'design.shape', 'design.assets', 'design.loader', 'design.splash', 'design.motion', 'native', 'native.firebase']) {
    const config = fixture();
    const object = field === 'config' ? config : field.split('.').reduce((current, key) => current[key], config);
    object.unsupported = 'kept for error reporting';
    assert.equal(hasError(config, `${field}.unsupported`), true, field);
    assert.equal((field === 'config' ? engine.buildConfig(config) : field.split('.').reduce((current, key) => current[key], engine.buildConfig(config))).unsupported, 'kept for error reporting');
  }
});

test('native identity restrictions, required values and strings match the generator', () => {
  const cases = [
    ['schemaVersion', 2], ['schemaVersion', true], ['app.name', ''], ['app.name', 'Name; command'],
    ['app.name', '$Name'], ['app.name', 'Name // comment'], ['app.name', 'a'.repeat(61)],
    ['app.description', 'line\nbreak'], ['app.id', 'a'], ['app.id', 'Uppercase'], ['app.id', 'bad.dot'],
    ['app.themeMode', 'auto'], ['design.layout', 'custom'],
    ['native.androidApplicationId', 'com.Customer.app'], ['native.androidApplicationId', 'single'],
    ['native.androidApplicationId', 'com.customer-app'], ['native.androidApplicationId', 'com.customer.app\n'], ['native.iosBundleId', 'com.customer_app'],
    ['native.iosBundleId', '.com.customer'], ['design.splash.enabled', 'true'], ['design.motion.enabled', 1],
    ['native.iconBackground', '#80ABCDEF'], ['design.splash.backgroundDark', '#00FFFFFF'],
    ['design.light.fill', '#abc'], ['design.light.ink', '#123456\n'], ['design.dark.paper', '#GGFFFFFF'], ['design.loader.style', 'animated-gif']
  ];
  for (const [field, value] of cases) {
    const config = fixture(); set(config, field, value);
    assert.equal(hasError(config, field), true, `${field}: ${value}`);
  }
  const good = fixture();
  good.app.name = "Acme's Wallet – EUR";
  good.app.id = 'acme_wallet-2';
  good.native.androidApplicationId = 'com.acme_wallet.app2';
  good.native.iosBundleId = 'com.Acme-Wallet.app2';
  good.native.iconBackground = '#ffABCDef';
  assert.equal(engine.validateConfig(good).valid, true);
});

test('numeric bounds reject booleans, numeric strings, infinities and fractional milliseconds', () => {
  const fields = [
    ['design.typography.scale', 0.75, 1.5, false], ['design.shape.radiusScale', 0, 2, false],
    ['design.loader.durationMs', 200, 10000, true], ['design.motion.durationScale', 0.1, 3, false],
    ['design.splash.minimumDurationMs', 0, 10000, true], ['design.splash.maximumDurationMs', 0, 30000, true]
  ];
  for (const [field, low, high, integer] of fields) {
    for (const bad of [true, `${low}`, null, Number.NaN, Infinity, low - 0.01, high + 1, ...(integer ? [low + 0.5] : [])]) {
      const config = fixture(); set(config, field, bad);
      assert.equal(hasError(config, field), true, `${field} rejects ${String(bad)}`);
    }
    for (const boundary of [low, high]) {
      const config = fixture();
      config.design.splash.minimumDurationMs = 0;
      config.design.splash.maximumDurationMs = 30000;
      set(config, field, boundary);
      assert.equal(hasError(config, field), false, `${field} accepts ${boundary}`);
    }
  }
  const config = fixture();
  config.design.splash.minimumDurationMs = 2000;
  config.design.splash.maximumDurationMs = 1000;
  assert.equal(hasError(config, 'design.splash.minimumDurationMs'), true);
});

test('asset paths cannot escape the customer folder or point to URLs', () => {
  for (const value of ['/tmp/logo.png', '../logo.png', 'assets/../logo.png', 'assets\\logo.png', 'https://example.com/logo.png', 'C:/logo.png', 'data:image/png;base64,aaa', '', 'assets/logo.svg']) {
    const config = fixture(); config.design.assets.logo = value;
    assert.equal(hasError(config, 'design.assets.logo'), true, value);
  }
  const config = fixture();
  config.design.assets.logo = 'artwork/my.logo.PNG';
  assert.equal(engine.validateConfig(config).valid, true);
});

test('asset checklist distinguishes unverified, verified, missing and invalid dimensions', () => {
  const config = fixture();
  const metadata = {[config.design.assets.logo]: {valid: true, width: 2048, height: 1024}, [config.native.icon]: {valid: true, width: 1024, height: 1024}};
  let report = engine.validateConfig(config, metadata);
  assert.equal(report.valid, true);
  assert.equal(report.assets.find(asset => asset.field === 'design.assets.logo').status, 'verified');
  assert.equal(report.assets.find(asset => asset.field === 'design.assets.logoDark').status, 'unverified');
  metadata[config.design.assets.logo].width = 8193;
  assert.equal(hasError(config, 'design.assets.logo', metadata), true);
  metadata[config.design.assets.logo] = {valid: false, error: 'Unreadable image.'};
  assert.equal(hasError(config, 'design.assets.logo', metadata), true);
  metadata[config.design.assets.logo] = {exists: false};
  assert.equal(hasError(config, 'design.assets.logo', metadata), true);
  const map = new Map([[config.design.assets.logo, {valid: true, width: 8192, height: 1}]]);
  assert.equal(hasError(config, 'design.assets.logo', map), false);
});

test('custom fonts preserve arrays and validate family, path, weight and style', () => {
  const config = fixture();
  config.fonts = [{family: 'Customer Sans', files: [{path: 'assets/customer-regular.ttf'}, {path: 'assets/customer-italic.otf', weight: 700, style: 'italic'}]}];
  config.design.typography.fontFamily = 'Customer Sans';
  assert.equal(engine.validateConfig(config).valid, true);
  assert.deepEqual(engine.buildConfig(config).fonts[0].files[0], {path: 'assets/customer-regular.ttf', weight: 400, style: 'normal'});
  for (const family of ['Geist', 'GeistMono', '1Font', 'Custom:Font']) {
    const bad = engine.clone(config); bad.fonts[0].family = family;
    assert.equal(hasError(bad, 'fonts[0].family'), true);
  }
  const duplicate = engine.clone(config); duplicate.fonts.push(engine.clone(duplicate.fonts[0]));
  assert.equal(hasError(duplicate, 'fonts[1].family'), true);
  const weight = engine.clone(config); weight.fonts[0].files[0].weight = 450;
  assert.equal(hasError(weight, 'fonts[0].files[0].weight'), true);
  const style = engine.clone(config); style.fonts[0].files[0].style = 'bold';
  assert.equal(hasError(style, 'fonts[0].files[0].style'), true);
  const webFont = engine.clone(config); webFont.fonts[0].files[0].path = 'assets/custom.woff2';
  assert.equal(hasError(webFont, 'fonts[0].files[0].path'), true);
  const undeclared = fixture(); undeclared.design.typography.fontFamily = 'Arial';
  assert.equal(hasError(undeclared, 'design.typography.fontFamily'), true);
});

test('Firebase application IDs and cross-platform project matching can be checked from supplied files', () => {
  const config = fixture();
  config.native.firebase = {android: 'firebase/google-services.json', ios: 'firebase/GoogleService-Info.plist'};
  const android = {project_info: {project_id: 'customer-project', project_number: '123'}, client: [{client_info: {android_client_info: {package_name: config.native.androidApplicationId}, mobilesdk_app_id: '1:123:android:abc'}, api_key: [{current_key: 'public-android-key'}]}]};
  const ios = {BUNDLE_ID: config.native.iosBundleId, PROJECT_ID: 'customer-project', GCM_SENDER_ID: '123', GOOGLE_APP_ID: '1:123:ios:abc', API_KEY: 'public-ios-key'};
  const metadata = {[config.native.firebase.android]: {data: android}, [config.native.firebase.ios]: {data: ios}};
  let report = engine.validateConfig(config, metadata);
  assert.equal(report.valid, true);
  assert.ok(report.assets.filter(asset => asset.kind === 'firebase').every(asset => asset.status === 'verified'));
  android.client[0].client_info.android_client_info.package_name = 'com.wrong.app';
  assert.equal(hasError(config, 'native.firebase.android', metadata), true);
  android.client[0].client_info.android_client_info.package_name = config.native.androidApplicationId;
  ios.BUNDLE_ID = 'com.wrong.app';
  assert.equal(hasError(config, 'native.firebase.ios', metadata), true);
  ios.BUNDLE_ID = config.native.iosBundleId;
  ios.PROJECT_ID = 'wrong-project';
  assert.equal(hasError(config, 'native.firebase', metadata), true);
  ios.PROJECT_ID = 'customer-project';
  delete ios.API_KEY;
  assert.equal(hasError(config, 'native.firebase.ios', metadata), true);
});

test('public defines retain scalars but reject generated values and unsupported types', () => {
  const config = fixture();
  config.flutterDefines = {APP_FLAVOR: 'prod', API_BASE_URL: 'https://api.example.org', CUSTOM_FLAG: true, REQUEST_RETRIES: 3, AMOUNT_FACTOR: 1.25};
  assert.equal(engine.validateConfig(config).valid, true);
  for (const key of ['APP_NAME', 'APP_BRAND_ID', 'APP_DESIGN_JSON', 'SUPPORT_EMAIL', 'FIREBASE_CUSTOM', 'lowercase', '1INVALID', 'VALID_BUT_NEWLINE\n']) {
    const bad = engine.clone(config); bad.flutterDefines[key] = 'value';
    assert.equal(hasError(bad, `flutterDefines.${key}`), true, key);
  }
  for (const value of [null, [], {}, undefined, Infinity, Number.NaN]) {
    const bad = engine.clone(config); bad.flutterDefines.CUSTOM_VALUE = value;
    assert.equal(hasError(bad, 'flutterDefines.CUSTOM_VALUE'), true, String(value));
  }
  config.flutterDefines.DATABASE_PASSWORD = 'placeholder-do-not-use';
  assert.ok(engine.validateConfig(config).warnings.some(warning => warning.path === 'flutterDefines.DATABASE_PASSWORD'));
});

test('contrast uses WCAG sRGB and Flutter alpha-first colors', () => {
  assert.equal(engine.contrast('#FFFFFF', '#000000'), 21);
  assert.equal(engine.contrast(['#FFFFFF', '#FFFFFF']), 1);
  assert.equal(engine.contrast({foreground: '#00FFFFFF', background: '#000000'}), 1);
  assert.equal(engine.contrast('#FF000000', '#FFFFFFFF'), 21);
  assert.ok(engine.contrast('#80000000', '#FFFFFF') > 3.9);
  assert.ok(engine.contrast('#80000000', '#FFFFFF') < 4.1);
  assert.throws(() => engine.contrast('#fff', '#000000'), TypeError);
});

test('explicit palette derivation provides every token and readable action/card labels', () => {
  for (const mode of ['light', 'dark']) for (const primary of ['#000000', '#FFFFFF', '#777777', '#FF0000', '#00FF00', '#0000FF', '#621A96', '#C6F24E']) {
    const original = fixture();
    const derived = engine.makePalette({primary, accent: '#FFCC00'}, mode);
    assert.deepEqual(Object.keys(derived).sort(), [...engine.paletteKeys].sort());
    original.design[mode] = derived;
    assert.equal(engine.validateConfig(original).valid, true);
    const checks = engine.contrastChecks({design: {[mode]: derived}});
    assert.ok(checks.every(check => check.pass), `${mode}/${primary}: ${JSON.stringify(checks.filter(check => !check.pass))}`);
  }
  assert.throws(() => engine.makePalette({primary: '#80123456'}, 'light'), /opaque/);
  assert.throws(() => engine.makePalette({}, 'automatic'), /mode/);
});

test('contrast warnings do not silently rewrite imported brand tokens', () => {
  const config = fixture();
  config.design.light.onFill = config.design.light.fill;
  const report = engine.validateConfig(config);
  assert.equal(report.valid, true);
  assert.ok(report.warnings.some(warning => warning.path === 'design.light.onFill'));
  assert.equal(engine.buildConfig(config).design.light.onFill, config.design.light.fill);
});

test('all editable leaf fields are represented or covered by an advanced editor', () => {
  const described = new Set(Object.values(engine.fieldDescriptors).flat().map(field => field.path));
  function visit(value, field = '') {
    if (field === 'schemaVersion' || field === 'fonts' || field === 'flutterDefines' || /^design\.(light|dark)$/.test(field)) return;
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      for (const [key, nested] of Object.entries(value)) visit(nested, field ? `${field}.${key}` : key);
    } else assert.ok(described.has(field), `Missing field help: ${field}`);
  }
  visit(hoppa);
  assert.ok(described.has('native.firebase.android'));
  assert.ok(described.has('native.firebase.ios'));
});

test('prototype-looking imported JSON is preserved for rejection without polluting globals', () => {
  const config = fixture();
  Object.defineProperty(config.design, '__proto__', {value: {polluted: true}, enumerable: true});
  const output = engine.buildConfig(config);
  assert.equal({}.polluted, undefined);
  assert.equal(Object.getPrototypeOf(output.design), Object.prototype);
  assert.equal(hasError(output, 'design.__proto__'), true);
});

test('the real Python generator accepts the exported palette and filled defaults', () => {
  const config = fixture();
  config.app.name = 'Customer Wallet';
  config.app.id = 'customer-wallet';
  config.design.light = engine.makePalette({primary: '#7045A6', accent: '#17613E'}, 'light');
  config.design.dark = engine.makePalette({primary: '#C5ACFF', accent: '#88DCA3'}, 'dark');
  delete config.design.motion;
  delete config.design.loader;
  delete config.native.iconBackground;
  const output = engine.buildConfig(config);
  const source = `
import importlib.util, json, pathlib, shutil, sys, tempfile
root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('brand', root / 'scripts/prepare-mobile-brand.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
config = json.load(sys.stdin)
with tempfile.TemporaryDirectory(prefix='customer-guide-test-') as folder:
    base = pathlib.Path(folder)
    paths = list(config['design']['assets'].values()) + [config['native']['icon']]
    for value in paths:
        target = base / value
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / 'mobile_flutter/config' / value, target)
    config_file = base / 'customer.json'
    config_file.write_text(json.dumps(config))
    validated, _, _ = module.load_config(config_file)
    print(json.dumps(validated))
`;
  const result = spawnSync(process.env.BRANDING_PYTHON || 'python3', ['-c', source, root], {input: JSON.stringify(output), encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), output);
});
