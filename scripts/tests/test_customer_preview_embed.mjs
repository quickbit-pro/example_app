import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../customer-guide/flutter-embed.js', import.meta.url), 'utf8');
function harness(extraContext = {}) {
  const listeners = new Map(), messages = [], events = [], children = [];
  const iframe = { style: {}, contentWindow: { postMessage: data => messages.push(data) },
    attributes: {}, setAttribute(k, v) { this.attributes[k] = v; }, remove() { this.removed = true; } };
  const context = { document: { createElement: () => iframe },
    addEventListener: (type, callback) => listeners.set(type, callback),
    removeEventListener: (type, callback) => { if (listeners.get(type) === callback) listeners.delete(type); },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
  };
  Object.assign(context, extraContext);
  context.globalThis = context;
  vm.runInNewContext(source, context);
  const container = { style: {}, clientWidth: 312, appendChild: child => children.push(child), dispatchEvent: event => events.push(event) };
  const payload = { schemaVersion: 1, assets: [] };
  const preview = context.CustomerFlutterPreview.create(container, payload);
  const message = (data, source = iframe.contentWindow) => listeners.get('message')?.({ source, data });
  return { preview, iframe, messages, events, children, listeners, message, payload, container, context };
}

test('latest config waits for actual Flutter readiness, then updates without rebooting', () => {
  const h = harness();
  h.preview.post({ config: { app: { name: 'One' } } });
  h.preview.post({ config: { app: { name: 'Two' } } });
  assert.equal(h.messages.length, 0);
  h.message({ type: 'customer-preview-frame-ready' });
  assert.equal(h.messages[0].type, 'customer-preview-initialize');
  assert.equal(h.messages[0].payload, h.payload);
  h.message({ type: 'customer-preview-ready' });
  assert.equal(h.preview.ready, true);
  assert.equal(h.messages[1].config.app.name, 'Two');
  h.preview.post({ config: { app: { name: 'Three' } }, screen: 'cards' });
  assert.equal(h.messages[2].config.app.name, 'Three');
  assert.equal(h.children.length, 1);
  assert.equal(h.iframe.style.width, '390px');
  assert.equal(h.iframe.style.height, '844px');
  assert.equal(h.iframe.style.transform, 'scale(0.8)');
});

test('unrelated frames cannot claim ready or request package bytes', () => {
  const h = harness();
  h.message({ type: 'customer-preview-frame-ready' }, {});
  h.message({ type: 'customer-preview-ready' }, {});
  assert.equal(h.messages.length, 0);
  assert.equal(h.preview.ready, false);
});

test('errors and applied statuses reach the accessible host UI', () => {
  const h = harness();
  h.message({ type: 'customer-preview-error', message: 'Broken package' });
  h.message({ type: 'customer-preview-applied', screen: 'home' });
  assert.equal(h.events[0].type, 'customer-preview-error');
  assert.equal(h.events[0].detail.message, 'Broken package');
  assert.equal(h.events[1].detail.screen, 'home');
});

test('frame blocks server connections and embeds actual engine bootstrapping', () => {
  const h = harness();
  assert.equal(h.iframe.attributes.sandbox, 'allow-scripts allow-same-origin');
  assert.ok(h.iframe.srcdoc.includes("default-src 'none'"));
  assert.ok(h.iframe.srcdoc.includes("connect-src data: blob:"));
  assert.ok(h.iframe.srcdoc.includes('WebAssembly.compile'));
  assert.ok(h.iframe.srcdoc.includes('window._flutter.loader.load'));
  assert.ok(h.iframe.srcdoc.endsWith('</script></body></html>'));
});

test('destroy removes iframe, parent listener and pending configuration', () => {
  const h = harness();
  h.preview.destroy();
  assert.equal(h.iframe.removed, true);
  assert.equal(h.listeners.has('message'), false);
  h.preview.post({ config: {} });
  assert.equal(h.messages.length, 0);
});


test('container resize and DPR changes refresh Flutter metrics without recreating the iframe', () => {
  let observeResize, mediaChange, stoppedObserver = false;
  const removedMedia = [];
  const h = harness({
    ResizeObserver: class {
      constructor(callback) { observeResize = callback; }
      observe() {}
      disconnect() { stoppedObserver = true; }
    },
    devicePixelRatio: 2,
    matchMedia: query => ({
      media: query,
      addEventListener: (_type, callback) => { mediaChange = callback; },
      removeEventListener: (_type, callback) => { removedMedia.push(callback); },
    }),
  });
  h.message({ type: 'customer-preview-frame-ready' });
  h.message({ type: 'customer-preview-ready' });
  h.messages.length = 0;
  h.container.clientWidth = 390;
  observeResize();
  assert.equal(h.iframe.style.transform, 'scale(1)');
  assert.equal(h.messages.at(-1).type, 'customer-preview-resize');
  h.listeners.get('resize')();
  assert.equal(h.messages.length, 2, 'outer resize remains observed alongside ResizeObserver');
  h.context.devicePixelRatio = 1;
  mediaChange();
  assert.equal(h.messages.length, 3);
  assert.equal(h.children.length, 1, 'metrics updates preserve the running Flutter frame');
  assert.ok(h.iframe.srcdoc.includes("window.dispatchEvent(new Event('resize'))"));
  h.preview.destroy();
  assert.equal(stoppedObserver, true);
  assert.equal(h.listeners.has('resize'), false);
  assert.equal(removedMedia.length, 2, 'DPR listener is replaced after changes and removed on destroy');
});
