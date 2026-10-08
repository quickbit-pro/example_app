/* Runs the actual, compiled Flutter app entirely from this HTML file. */
(function (global) {
  'use strict';

  function previewFrameRuntime() {
    'use strict';
    const resources = new Map();
    const blobUrls = new Set();
    const nativeFetch = window.fetch.bind(window);
    let initialized = false;
    const send = (type, extra = {}) => parent.postMessage({ type, ...extra }, '*');
    const fail = error => send('customer-preview-error', { message: String(error && error.message || error) });
    const decode = data => Uint8Array.from(atob(data), ch => ch.charCodeAt(0));
    const safePath = path => typeof path === 'string' && path.length > 0 &&
      !path.startsWith('/') && !path.includes('\\') && !path.split('/').some(part => part === '..' || !part);
    function resourcePath(url) {
      const value = String(url);
      if (resources.has(value)) return value;
      let path;
      try { path = decodeURIComponent(new URL(value, 'https://flutter-preview.invalid/').pathname).replace(/^\/+/, ''); }
      catch (_) { return null; }
      if (resources.has(path)) return path;
      // dart2js deferred chunk URLs may be based on the main script's blob URL.
      const filename = path.split('/').pop();
      return /^main\.dart\.js(?:_\d+\.part\.js)?$/.test(filename) && resources.has(filename) ? filename : null;
    }
    function findResource(url) {
      const path = resourcePath(url);
      return path == null ? null : resources.get(path);
    }
    function objectUrl(resource) {
      if (!resource.url) {
        resource.url = URL.createObjectURL(new Blob([resource.bytes], { type: resource.mime }));
        blobUrls.add(resource.url);
      }
      return resource.url;
    }
    function updateAssets(assets) {
      const items = Array.isArray(assets) ? assets : assets && typeof assets === 'object'
        ? Object.entries(assets).map(([path, asset]) => ({ path, ...asset })) : [];
      for (const asset of items) {
        if (!asset || !safePath(asset.path) || typeof asset.data !== 'string') continue;
        const resource = { bytes: decode(asset.data), mime: asset.mime || 'application/octet-stream' };
        for (const path of [asset.path, 'assets/' + asset.path, 'assets/config/' + asset.path]) {
          const previous = resources.get(path);
          if (previous && previous.url) { URL.revokeObjectURL(previous.url); blobUrls.delete(previous.url); }
          resources.set(path, resource);
        }
      }
    }
    window.fetch = async function (input, options) {
      const url = typeof input === 'string' || input instanceof URL ? String(input) : input.url;
      if (blobUrls.has(url) || String(url).startsWith('data:')) return nativeFetch(input, options);
      const resource = findResource(url);
      if (!resource) throw new TypeError('The offline preview cannot request external or missing resource: ' + url);
      return new Response(resource.bytes.slice(), { status: 200, headers: {
        'Content-Type': resource.mime, 'Content-Length': String(resource.bytes.length),
      } });
    };
    // Some Flutter packages use XMLHttpRequest rather than fetch for assets.
    const xhrOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url, ...rest) {
      const resource = findResource(url);
      const value = String(url);
      if (!resource && !blobUrls.has(value) && !value.startsWith('data:')) {
        throw new TypeError('The offline preview blocks external XMLHttpRequest: ' + value);
      }
      return xhrOpen.call(this, method, resource ? objectUrl(resource) : url, ...rest);
    };
    function loadScript(url) {
      return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = url;
        script.onload = resolve;
        script.onerror = () => reject(new Error('Cannot load embedded Flutter JavaScript'));
        document.head.appendChild(script);
      });
    }
    window.dartDeferredLibraryLoader = function (uri, success, error) {
      const resource = findResource(uri);
      if (!resource) { error(new Error('Missing embedded Flutter deferred library: ' + uri)); return; }
      loadScript(objectUrl(resource)).then(success, error);
    };
    addEventListener('error', event => fail(event.error || event.message));
    addEventListener('unhandledrejection', event => fail(event.reason));
    addEventListener('message', async event => {
      if (event.source !== parent || !event.data || typeof event.data !== 'object') return;
      const message = event.data;
      if (message.type === 'customer-preview-resize') {
        // The CSS viewport remains 390×844 while the parent can change scale
        // or device pixel ratio. Notify Flutter after browser layout settles.
        requestAnimationFrame(() => window.dispatchEvent(new Event('resize')));
        return;
      }
      if (message.type === 'customer-brand-update') {
        try { updateAssets(message.assets); } catch (error) { fail(error); }
        return;
      }
      if (message.type !== 'customer-preview-initialize' || initialized) return;
      initialized = true;
      try {
        const payload = message.payload;
        if (!payload || payload.schemaVersion !== 1 || payload.compression !== 'gzip') {
          throw new Error('Unsupported embedded Flutter package');
        }
        if (typeof DecompressionStream !== 'function') {
          throw new Error('Use a current Chrome, Edge, Firefox or Safari browser to run the embedded Flutter preview.');
        }
        send('customer-preview-status', { message: 'Loading the actual Flutter app…' });
        await Promise.all(payload.assets.map(async asset => {
          if (!safePath(asset.path)) throw new Error('Unsafe embedded Flutter asset path');
          const stream = new Blob([decode(asset.data)]).stream().pipeThrough(new DecompressionStream('gzip'));
          const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
          if (bytes.length !== asset.size) throw new Error('Embedded Flutter asset size mismatch: ' + asset.path);
          resources.set(asset.path, { bytes, mime: asset.mime });
        }));
        for (const [alias, path] of Object.entries(payload.aliases || {})) {
          if (!safePath(alias) || !safePath(path) || !resources.has(path) || resources.has(alias)) {
            throw new Error('Invalid embedded Flutter resource alias');
          }
          resources.set(alias, resources.get(path));
        }
        const requireResource = path => {
          const resource = resources.get(path);
          if (!resource) throw new Error('Missing embedded Flutter asset: ' + path);
          return resource;
        };
        // CanvasKit accepts a custom WASM initializer. Supplying its real module
        // directly avoids all CDN requests and relative Emscripten fetch paths.
        const canvasKitModule = await import(objectUrl(requireResource(payload.canvasKitJs)));
        const wasmModule = await WebAssembly.compile(requireResource(payload.canvasKitWasm).bytes);
        window.flutterCanvasKit = await canvasKitModule.default({
          instantiateWasm(imports, receiveInstance) {
            const instance = new WebAssembly.Instance(wasmModule, imports);
            receiveInstance(instance, wasmModule);
            return instance.exports;
          },
        });
        await loadScript(objectUrl(requireResource(payload.loader)));
        window._flutter.buildConfig = {
          engineRevision: payload.engineRevision, useLocalCanvasKit: true,
          builds: [{ compileTarget: 'dart2js', renderer: 'canvaskit', mainJsPath: objectUrl(requireResource(payload.entrypoint)) }],
        };
        const engineConfig = {
          renderer: 'canvaskit', canvasKitVariant: 'full',
          canvasKitBaseUrl: 'https://flutter-preview.invalid/canvaskit/',
          assetBase: 'https://flutter-preview.invalid/',
          fontFallbackBaseUrl: 'https://flutter-preview.invalid/font-fallback/',
        };
        await window._flutter.loader.load({ config: engineConfig,
          onEntrypointLoaded: async initializer => {
            try {
              const runner = await initializer.initializeEngine(engineConfig);
              await runner.runApp();
            } catch (error) { fail(error); }
          },
        });
      } catch (error) { fail(error); }
    });
    send('customer-preview-frame-ready');
  }

  function create(container, payload, options = {}) {
    if (!container || !payload) throw new Error('Flutter preview requires a container and packaged build');
    const iframe = document.createElement('iframe');
    iframe.title = 'Actual Flutter app preview';
    iframe.setAttribute('sandbox', 'allow-scripts allow-same-origin');
    iframe.setAttribute('referrerpolicy', 'no-referrer');
    iframe.setAttribute('allow', '');
    const viewportWidth = options.viewportWidth || 390, viewportHeight = options.viewportHeight || 844;
    container.style.position = 'relative';
    container.style.aspectRatio = viewportWidth + ' / ' + viewportHeight;
    container.style.overflow = 'hidden';
    iframe.style.cssText = 'display:block;position:absolute;left:0;top:0;border:0;background:transparent;transform-origin:0 0;';
    iframe.style.width = viewportWidth + 'px';
    iframe.style.height = viewportHeight + 'px';
    let latestState = null, frameReady = false, appReady = false, destroyed = false;
    const resize = () => {
      iframe.style.transform = 'scale(' + ((container.clientWidth || viewportWidth) / viewportWidth) + ')';
      if (frameReady && !destroyed) iframe.contentWindow.postMessage({ type: 'customer-preview-resize' }, '*');
    };
    const observer = typeof global.ResizeObserver === 'function' ? new global.ResizeObserver(resize) : null;
    if (observer) observer.observe(container);
    // An outer resize can change DPR while the fixed iframe size is unchanged.
    global.addEventListener('resize', resize);
    let dprQuery = null;
    const trackDpr = () => {
      if (dprQuery) dprQuery.removeEventListener('change', onDprChange);
      if (typeof global.matchMedia !== 'function') return;
      dprQuery = global.matchMedia('(resolution: ' + (global.devicePixelRatio || 1) + 'dppx)');
      dprQuery.addEventListener('change', onDprChange);
    };
    const onDprChange = () => { resize(); trackDpr(); };
    trackDpr();
    const status = (type, detail) => container.dispatchEvent(new CustomEvent(type, { detail }));
    function sendState() {
      if (frameReady && latestState && !destroyed) iframe.contentWindow.postMessage({ ...latestState, type: 'customer-brand-update' }, '*');
    }
    const onMessage = event => {
      if (event.source !== iframe.contentWindow || !event.data || destroyed) return;
      const data = event.data;
      if (data.type === 'customer-preview-frame-ready') {
        frameReady = true;
        iframe.contentWindow.postMessage({ type: 'customer-preview-initialize', payload }, '*');
      } else if (data.type === 'customer-preview-ready') {
        appReady = true;
        sendState();
        status('customer-preview-ready', data);
      } else if (data.type === 'customer-preview-applied' || data.type === 'customer-preview-error' || data.type === 'customer-preview-status' || data.type === 'customer-preview-notice') {
        status(data.type, data);
      }
    };
    global.addEventListener('message', onMessage);
    const csp = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob:; style-src 'unsafe-inline'; img-src data: blob:; connect-src data: blob:; font-src data: blob:; worker-src blob:; base-uri 'none'; form-action 'none'";
    iframe.srcdoc = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><meta http-equiv="Content-Security-Policy" content="' + csp + '"><style>html,body{width:100%;height:100%;margin:0;overflow:hidden}body{background:transparent}</style></head><body><script>(' + previewFrameRuntime.toString().replace(/<\/script/gi, '<\\/script') + ')();<\/script></body></html>';
    container.appendChild(iframe);
    resize();
    return {
      iframe,
      post(state) { latestState = state; if (appReady) sendState(); },
      destroy() {
        destroyed = true; global.removeEventListener('message', onMessage);
        if (observer) observer.disconnect();
        global.removeEventListener('resize', resize);
        if (dprQuery) dprQuery.removeEventListener('change', onDprChange);
        iframe.remove(); latestState = null;
      },
      get ready() { return appReady; },
    };
  }

  global.CustomerFlutterPreview = Object.freeze({ create });
})(globalThis);
