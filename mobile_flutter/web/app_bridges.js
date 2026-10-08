// Runtime bridges retain their public names for compatibility with Flutter.

    // Device biometrics for the installed web app. A platform passkey
    // (Face ID / Touch ID / fingerprint) gates the locally stored session,
    // the same role local_auth plays on iOS and Android. Nothing here is
    // sent to a server.
    (function () {
      var KEY = window.APP_BRAND.id + '.biometric.credential';
      var activePrompt = null;
      function cancelPrompt() {
        if (activePrompt) activePrompt.abort();
        activePrompt = null;
      }
      function beginPrompt() {
        cancelPrompt();
        activePrompt = new AbortController();
        return activePrompt;
      }
      function toBase64(buffer) {
        return btoa(String.fromCharCode.apply(null, new Uint8Array(buffer)));
      }
      function fromBase64(value) {
        return Uint8Array.from(atob(value), function (c) { return c.charCodeAt(0); });
      }
      window.exampleBiometrics = {
        available: async function () {
          try {
            // Device biometrics (platform passkey) work in any secure context,
            // installed app or browser tab, as long as the device has a
            // user-verifying authenticator (fingerprint, face, screen lock).
            return !!(window.isSecureContext && window.PublicKeyCredential &&
              await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable());
          } catch (e) { return false; }
        },
        hasCredential: function () { return !!localStorage.getItem(KEY); },
        cancel: cancelPrompt,
        register: async function (userName) {
          var prompt = beginPrompt();
          try {
            var credential = await navigator.credentials.create({
              signal: prompt.signal,
              publicKey: {
                challenge: crypto.getRandomValues(new Uint8Array(32)),
                rp: { name: window.APP_BRAND.name, id: location.hostname },
                user: {
                  id: crypto.getRandomValues(new Uint8Array(16)),
                  name: userName || window.APP_BRAND.id,
                  displayName: userName || window.APP_BRAND.name
                },
                pubKeyCredParams: [
                  { type: 'public-key', alg: -7 },
                  { type: 'public-key', alg: -257 }
                ],
                authenticatorSelection: {
                  authenticatorAttachment: 'platform',
                  userVerification: 'required',
                  residentKey: 'preferred'
                },
                timeout: 60000,
                attestation: 'none'
              }
            });
            if (prompt.signal.aborted || !credential) return false;
            localStorage.setItem(KEY, toBase64(credential.rawId));
            return true;
          } catch (e) { return false; }
          finally { if (activePrompt === prompt) activePrompt = null; }
        },
        verify: async function () {
          var stored = localStorage.getItem(KEY);
          if (!stored) return 'none';
          var prompt = beginPrompt();
          try {
            var assertion = await navigator.credentials.get({
              signal: prompt.signal,
              publicKey: {
                challenge: crypto.getRandomValues(new Uint8Array(32)),
                allowCredentials: [{ type: 'public-key', id: fromBase64(stored) }],
                userVerification: 'required',
                rpId: location.hostname,
                timeout: 60000
              }
            });
            if (prompt.signal.aborted) return 'cancelled';
            return assertion ? 'success' : 'failed';
          } catch (e) {
            return e && (e.name === 'NotAllowedError' || e.name === 'AbortError') ? 'cancelled' : 'failed';
          } finally { if (activePrompt === prompt) activePrompt = null; }
        },
        clear: function () { localStorage.removeItem(KEY); }
      };
    })();


    // Sumsub WebSDK host for browsers (the mobile SDK has no web build).
    // The app hands over a container element and an access token; events
    // are reported back through onEvent(name, payloadJson).
    (function () {
      var SDK_URL = 'https://static.sumsub.com/idensic/static/sns-websdk-builder.js';
      var loading = null;
      function ensureSdk() {
        if (window.snsWebSdk) return Promise.resolve();
        if (loading) return loading;
        loading = new Promise(function (resolve, reject) {
          var script = document.createElement('script');
          script.src = SDK_URL;
          script.async = true;
          script.onload = function () { resolve(); };
          script.onerror = function () { loading = null; reject(new Error('Could not load the verification module.')); };
          document.head.appendChild(script);
        });
        return loading;
      }
      window.exampleSumsub = {
        launch: function (container, accessToken, refreshToken, onEvent) {
          function emit(name, payload) {
            try { onEvent(name, JSON.stringify(payload === undefined ? null : payload)); } catch (e) { /* ignore */ }
          }
          ensureSdk().then(function () {
            var instance = window.snsWebSdk
              .init(accessToken, function () { return refreshToken(); })
              .withConf({ lang: 'en', theme: (function () {
                var mode = window.APP_BRAND.theme;
                try {
                  var saved = JSON.parse(localStorage.getItem('flutter.app.themeMode.v1'));
                  if (saved === 'light' || saved === 'dark' || saved === 'system') mode = saved;
                } catch (_) {}
                return mode === 'light' || (mode === 'system' && matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';
              })() })
              .withOptions({ addViewportTag: false, adaptIframeHeight: true })
              .on('idCheck.onReady', function () { emit('ready'); })
              .on('idCheck.onApplicantLoaded', function (p) { emit('loaded', p); })
              .on('idCheck.onApplicantSubmitted', function () { emit('submitted'); })
              .on('idCheck.onApplicantStatusChanged', function (p) { emit('status', p); })
              .on('idCheck.onError', function (e) { emit('error', e); })
              .build();
            instance.launch(container);
          }).catch(function (e) {
            emit('error', { message: e && e.message ? e.message : String(e) });
          });
        }
      };
    })();


    // Install-to-home-screen bridge. Chrome fires `beforeinstallprompt` once the
    // PWA criteria are met; we keep the event so the app can show its own
    // install banner and trigger the native prompt from a button.
    (function () {
      var deferred = null;
      var listeners = [];
      function standalone() {
        return (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) ||
          window.navigator.standalone === true;
      }
      function notify() { listeners.forEach(function (cb) { try { cb(!!deferred); } catch (e) {} }); }
      window.addEventListener('beforeinstallprompt', function (event) {
        event.preventDefault();
        deferred = event;
        notify();
      });
      window.addEventListener('appinstalled', function () { deferred = null; notify(); });
      function platform() {
        var ua = navigator.userAgent || '';
        if (/android/i.test(ua)) return 'android';
        if (/iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) return 'ios';
        return 'other';
      }
      window.exampleSafeArea = (function () {
        // env(safe-area-inset-*) measured on a probe, for the Flutter side:
        // the web engine reports no view padding of its own.
        var probe = null;
        function insets() {
          if (!probe) {
            probe = document.createElement("div");
            probe.setAttribute("aria-hidden", "true");
            probe.style.cssText = "position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;pointer-events:none;" +
              "padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)";
            document.body.appendChild(probe);
          }
          var style = getComputedStyle(probe);
          var sides = [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft]
            .map(function (value) { var n = parseFloat(value); return isNaN(n) ? 0 : n; });
          // The bottom is deliberately not forwarded. On the installed iPhone
          // app WebKit's reported home-indicator inset lifted the bottom bar far
          // higher than the indicator needs, and the customer prefers the bar
          // flush with the screen edge; the status-bar inset at the top is the
          // one that was missing and it is kept.
          sides[2] = 0;
          return sides.join(",");
        }
        return { insets: insets };
      })();
      window.exampleInstall = {
        available: function () { return !!deferred && !standalone(); },
        installed: standalone,
        platform: platform,
        onChange: function (cb) { listeners.push(cb); cb(!!deferred && !standalone()); },
        prompt: async function () {
          if (!deferred) return 'unavailable';
          var event = deferred;
          deferred = null;
          notify();
          try {
            event.prompt();
            var choice = await event.userChoice;
            return choice && choice.outcome === 'accepted' ? 'accepted' : 'dismissed';
          } catch (e) { return 'dismissed'; }
        }
      };
    })();


    // App update detection: every deploy ships a service worker with a new
    // cache name; when the new worker takes control we tell the app so it can
    // offer a reload. Also poll for updates while the app stays open.
    (function () {
      var listeners = [];
      var updateReady = false;
      function notify() { listeners.forEach(function (cb) { try { cb(updateReady); } catch (e) {} }); }
      window.exampleUpdate = {
        ready: function () { return updateReady; },
        onChange: function (cb) { listeners.push(cb); cb(updateReady); },
        reload: function () { window.location.reload(); }
      };
      if (!('serviceWorker' in navigator)) return;
      var hadController = !!navigator.serviceWorker.controller;
      navigator.serviceWorker.addEventListener('controllerchange', function () {
        if (hadController) { updateReady = true; notify(); }
        hadController = true;
      });
      // Register once the app has drawn its first frame so precaching never
      // competes with the initial download (the shell is then served from the
      // browser's HTTP cache). A timer covers the case where the first frame
      // never arrives.
      var registered = false;
      function register() {
        if (registered) return;
        registered = true;
        navigator.serviceWorker.register('example_service_worker.js').then(function (reg) {
          function check() { try { reg.update(); } catch (e) {} }
          setInterval(check, 15 * 60 * 1000);
          document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'visible') check();
          });
          return navigator.serviceWorker.ready;
        }).then(function (reg) {
          // Tell the worker which CanvasKit variant this browser loaded so the
          // offline cache holds exactly the files this device needs.
          var urls = performance.getEntriesByType('resource')
            .map(function (entry) { return entry.name; })
            .filter(function (name) { return name.indexOf(location.origin + '/canvaskit') === 0; });
          if (reg.active && urls.length) reg.active.postMessage({ type: 'precache', urls: urls });
        }).catch(function () {});
      }
      window.addEventListener('flutter-first-frame', register);
      window.addEventListener('load', function () { setTimeout(register, 12000); });
    })();
    // BEGIN startup-handoff
    // Flutter's first frame already contains the brand loader. Cross-fading
    // two independently animated loaders makes both visible during startup.
    // Keep HTML opaque until that frame, then let Flutter own the splash.
    window.addEventListener('flutter-first-frame', function () {
      var loading = document.getElementById('example-loading');
      if (loading) loading.remove();
    }, { once: true });
    // END startup-handoff
