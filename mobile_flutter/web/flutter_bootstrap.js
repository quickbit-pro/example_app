{{flutter_js}}
{{flutter_build_config}}

(function () {
  // The engine replaces every viewport meta with its own when the app's view
  // is created, and its tag stops short of viewport-fit=cover; without that
  // an installed iPhone web app reports no safe-area insets and the bottom
  // bar sits under the home indicator. Rather than fight the engine, amend
  // whatever viewport tag is in the head, now and each time one is added.
  function coverSafeArea() {
    var metas = document.querySelectorAll('meta[name="viewport"]');
    for (var i = 0; i < metas.length; i++) {
      if (metas[i].content.indexOf('viewport-fit') === -1) {
        metas[i].content += ', viewport-fit=cover';
      }
    }
  }
  try {
    new MutationObserver(coverSafeArea).observe(document.head, { childList: true });
    coverSafeArea();
  } catch (e) { /* insets are best effort */ }

  // CanvasKit is served from this app, not the gstatic CDN. The deploy script
  // moves the folder to canvaskit-<engine revision>/ (and rewrites this line)
  // so the files can be cached immutably and still change with the engine.
  var base = 'canvaskit/'; // CANVASKIT_BASE

  // flutter.js only asks for CanvasKit once main.dart.js has run. Mirror its
  // variant choice here so the wasm download starts now, alongside the app.
  var chromium = (navigator.vendor === 'Google Inc.' || navigator.userAgent.indexOf('Edg/') !== -1) &&
    typeof ImageDecoder !== 'undefined' &&
    typeof Intl.v8BreakIterator !== 'undefined' &&
    typeof Intl.Segmenter !== 'undefined';
  var variantDir = base + (chromium ? 'chromium/' : '');
  function hint(rel, href, as) {
    var link = document.createElement('link');
    link.rel = rel;
    link.href = href;
    if (as) link.as = as;
    link.crossOrigin = 'anonymous';
    document.head.appendChild(link);
  }
  try {
    hint('preload', variantDir + 'canvaskit.wasm', 'fetch');
    hint('modulepreload', variantDir + 'canvaskit.js');
  } catch (e) { /* hints are best effort */ }

  try {
    Promise.resolve(_flutter.loader.load({
      onEntrypointLoaded: async function (engineInitializer) {
        try {
          var appRunner = await engineInitializer.initializeEngine({canvasKitBaseUrl: base});
          await appRunner.runApp();
        } catch (error) {
          if (window.exampleRecovery) window.exampleRecovery.show();
        }
      },
      config: {
        canvasKitBaseUrl: base,
      },
    })).catch(function () {
      if (window.exampleRecovery) window.exampleRecovery.show();
    });
  } catch (error) {
    if (window.exampleRecovery) window.exampleRecovery.show();
  }
})();
