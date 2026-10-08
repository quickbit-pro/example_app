import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import vm from 'node:vm';
const source = readFileSync(new URL('../../web/app_recovery.js', import.meta.url), 'utf8');
function host() {
  const events = new Map();
  const timers = new Map();
  const nodes = new Map();
  let id = 0, reloads = 0, resizes = 0;
  const on = (name, callback) => events.set(name, callback);
  const document = {
    visibilityState: 'visible', addEventListener: on,
    getElementById: key => nodes.get(key),
    createElement: () => ({style: {}, children: [], setAttribute() {}, appendChild(node) { this.children.push(node); }, remove() { nodes.delete(this.id); }}),
    body: {appendChild(node) { nodes.set(node.id, node); }},
  };
  class Canvas {
    constructor() { this.events = new Map(); this.context = {}; }
    getContext(type) { return type === 'unsupported' ? null : this.context; }
    addEventListener(name, callback) { this.events.set(name, callback); }
    emit(name) { this.events.get(name)?.({preventDefault() {}}); }
  }
  const window = {
    OffscreenCanvas: Canvas, HTMLCanvasElement: class extends Canvas {},
    addEventListener: on, location: {reload() { reloads++; }},
    requestAnimationFrame(callback) { callback(); }, dispatchEvent(event) { if (event.type === 'resize') resizes++; },
  };
  vm.runInNewContext(source, {window, document, Event: class {constructor(type) {this.type = type;}},
    setTimeout(callback, delay) { timers.set(++id, {callback, delay}); return id; },
    clearTimeout(key) { timers.delete(key); },
  });
  return {document, window, emit(name, event = {}) { events.get(name)?.(event); },
    tick(delay) { for (const [key, timer] of [...timers]) { if (timer.delay <= delay) { timers.delete(key); timer.callback(); } } },
    panel: () => nodes.get('example-recovery'), reloads: () => reloads, resizes: () => resizes};
}
test('startup failure offers a manual reopen without automatically reloading', () => {
  const app = host(); app.tick(30000);
  assert.ok(app.panel()); assert.equal(app.reloads(), 0);
  app.panel().children[1].onclick(); assert.equal(app.reloads(), 1);
});
test('a ready app removes startup recovery and its timer', () => {
  const app = host(); app.tick(30000); app.emit('flutter-first-frame');
  app.tick(30000); assert.equal(app.panel(), undefined);
});
test('background context loss offers recovery after Android resume', () => {
  const app = host(); app.emit('flutter-first-frame');
  app.document.visibilityState = 'hidden'; app.emit('webglcontextlost', {preventDefault() {}});
  app.tick(3000); assert.equal(app.panel(), undefined);
  app.document.visibilityState = 'visible'; app.emit('visibilitychange'); app.tick(3000);
  assert.ok(app.panel()); assert.equal(app.reloads(), 0);
  app.emit('webglcontextrestored');
  assert.ok(app.panel(), 'Restoring a context alone does not prove a frame was drawn');
  app.window.exampleRecovery.frameRendered(); assert.equal(app.panel(), undefined);
});
test('restoring the browser page requests a new layout', () => {
  const app = host(); app.emit('pageshow', {persisted: true}); assert.equal(app.resizes(), 1);
});
test('service worker navigation returns the installed shell without mixing a newer HTML release', async () => {
  const worker = readFileSync(new URL('../../web/example_service_worker.js', import.meta.url), 'utf8');
  const handlers = new Map(); let network = 0;
  const shell = {release: 'installed'};
  vm.runInNewContext(worker, {
    self: {addEventListener(name, callback) {handlers.set(name, callback);}, location: {origin: 'https://app.test'}},
    caches: {open: async () => ({match: async () => shell})}, URL,
    fetch: async () => {network++; return {release: 'new'};},
  });
  let response;
  handlers.get('fetch')({request: {method: 'GET', mode: 'navigate', url: 'https://app.test/'}, respondWith(value) {response = value;}});
  assert.equal(await response, shell); assert.equal(network, 0);
});

test('custom bootstrap preserves local CanvasKit configuration and reports engine failures', async () => {
  const bootstrap = readFileSync(new URL('../../web/flutter_bootstrap.js', import.meta.url), 'utf8')
    .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');
  let options; let recovered = 0; let ran = false;
  vm.runInNewContext(bootstrap, {
    navigator: {vendor: '', userAgent: ''},
    document: {createElement: () => ({}), head: {appendChild() {}}},
    _flutter: {loader: {load(value) { options = value; }}},
    window: {exampleRecovery: {show() {recovered++;}}},
  });
  await options.onEntrypointLoaded({initializeEngine: async config => {
    assert.equal(config.canvasKitBaseUrl, 'canvaskit/');
    return {runApp: async () => { ran = true; }};
  }});
  assert.equal(ran, true);
  await options.onEntrypointLoaded({initializeEngine: async () => {throw Error('engine failed');}});
  assert.equal(recovered, 1);
});


test('foreground return requests a frame and offers recovery if Flutter never draws', () => {
  const app = host(); let redraws = 0;
  app.window.exampleRecovery.onRedraw(() => redraws++);
  app.emit('flutter-first-frame');
  app.document.visibilityState = 'hidden'; app.emit('visibilitychange');
  assert.equal(redraws, 0);
  app.document.visibilityState = 'visible'; app.emit('visibilitychange');
  assert.equal(redraws, 1);
  app.tick(8000); assert.ok(app.panel()); assert.equal(app.reloads(), 0);
  app.window.exampleRecovery.frameRendered(); assert.equal(app.panel(), undefined);
});

test('healthy foreground redraw cancels the recovery timer', () => {
  const app = host();
  app.window.exampleRecovery.onRedraw(() => app.window.exampleRecovery.frameRendered());
  app.emit('flutter-first-frame'); app.emit('pageshow', {persisted: true});
  app.tick(30000); assert.equal(app.panel(), undefined);
});

test('offscreen WebGL loss is observed without a document event', () => {
  const app = host(); app.emit('flutter-first-frame');
  const canvas = new app.window.OffscreenCanvas();
  assert.equal(canvas.getContext('webgl2'), canvas.context);
  canvas.emit('webglcontextlost'); app.tick(3000);
  assert.ok(app.panel());
  app.window.exampleRecovery.frameRendered();
  assert.ok(app.panel(), 'Frame timings must not hide a still-lost graphics context');
  canvas.emit('webglcontextrestored');
  app.window.exampleRecovery.frameRendered(); assert.equal(app.panel(), undefined);
});

test('2D and unsupported contexts do not install WebGL recovery listeners', () => {
  const app = host(); const canvas = new app.window.OffscreenCanvas();
  assert.equal(canvas.getContext('unsupported'), null);
  assert.equal(canvas.getContext('2d'), canvas.context);
  assert.equal(canvas.events.size, 0);
});

test('a failure while hidden is shown on return even after an earlier first frame', () => {
  const app = host(); app.emit('flutter-first-frame');
  app.document.visibilityState = 'hidden'; app.window.exampleRecovery.show();
  assert.equal(app.panel(), undefined);
  app.document.visibilityState = 'visible'; app.emit('visibilitychange');
  assert.ok(app.panel());
});

test('service worker reads JS only from its own release cache', async () => {
  const worker = readFileSync(new URL('../../web/example_service_worker.js', import.meta.url), 'utf8');
  const handlers = new Map(); let network = 0; let globalMatches = 0;
  const current = {release: 'current'};
  vm.runInNewContext(worker, {
    self: {addEventListener(name, callback) {handlers.set(name, callback);}, location: {origin: 'https://app.test'}},
    caches: {
      open: async () => ({match: async () => current}),
      match: async () => {globalMatches++; return {release: 'obsolete-flutter'};},
    }, URL,
    fetch: async () => {network++; return {};},
  });
  let response;
  handlers.get('fetch')({request: {method: 'GET', url: 'https://app.test/main.dart.js'}, respondWith(value) {response = value;}});
  assert.equal(await response, current); assert.equal(network, 0); assert.equal(globalMatches, 0);
});

test('entrypoint download rejection is immediately recoverable', async () => {
  const bootstrap = readFileSync(new URL('../../web/flutter_bootstrap.js', import.meta.url), 'utf8')
    .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');
  let recovered = 0;
  vm.runInNewContext(bootstrap, {
    navigator: {vendor: '', userAgent: ''},
    document: {createElement: () => ({}), head: {appendChild() {}}},
    _flutter: {loader: {load() {return Promise.reject(Error('download failed'));}}},
    window: {exampleRecovery: {show() {recovered++;}}},
  });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(recovered, 1);
});


test('Android resume repaints even when animation callbacks never run', () => {
  const app = host(); let redraws = 0;
  app.window.requestAnimationFrame = () => {}; // suspended compositor
  app.window.exampleRecovery.onRedraw(() => redraws++);
  app.emit('flutter-first-frame');
  app.emit('resume');
  assert.equal(redraws, 1);
  app.tick(250);
  assert.equal(redraws, 2, 'Retry after queued lifecycle notifications settle');
  app.tick(8000);
  assert.ok(app.panel());
  app.panel().children[1].onclick();
  assert.equal(app.reloads(), 1);
});

test('a missing Flutter redraw bridge still has a resume watchdog', () => {
  const app = host(); app.emit('flutter-first-frame');
  app.emit('focus'); app.tick(8000);
  assert.ok(app.panel());
});

test('a failing redraw bridge leaves a usable reopen button', () => {
  const app = host(); app.emit('flutter-first-frame');
  app.window.exampleRecovery.onRedraw(() => { throw Error('Renderer lost'); });
  assert.doesNotThrow(() => app.emit('resume'));
  assert.ok(app.panel()); assert.equal(app.reloads(), 0);
});
