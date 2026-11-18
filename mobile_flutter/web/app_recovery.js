// Keep a recoverable screen when Android restores a suspended renderer or a
// startup download fails. Reloading is explicit and never repeats an action.
(function () {
  var ready = false;
  var graphicsTimer;
  var graphicsLost = false;
  var startupTimer;
  var resumeTimer;
  var redraw;
  var redrawTimer;
  var pendingFailure = false;
  // Recovery also works before Flutter or its translation assets are available.
  var recoveryCopy = {
    en: ['The app could not display this screen. Please reopen it to continue.', 'Reopen app'],
    ar: ['تعذّر على التطبيق عرض هذه الشاشة. أعد فتحه للمتابعة.', 'إعادة فتح التطبيق'],
    de: ['Die App konnte diese Ansicht nicht anzeigen. Öffne sie erneut, um fortzufahren.', 'App erneut öffnen'],
    es: ['La aplicación no pudo mostrar esta pantalla. Vuelve a abrirla para continuar.', 'Volver a abrir la aplicación'],
    fr: ['L’application n’a pas pu afficher cet écran. Rouvrez-la pour continuer.', 'Rouvrir l’application'],
    hi: ['ऐप यह स्क्रीन नहीं दिखा सका। जारी रखने के लिए ऐप दोबारा खोलें।', 'ऐप दोबारा खोलें'],
    id: ['Aplikasi tidak dapat menampilkan layar ini. Buka kembali aplikasi untuk melanjutkan.', 'Buka kembali aplikasi'],
    it: ['L’app non è riuscita a mostrare questa schermata. Riaprila per continuare.', 'Riapri l’app'],
    ja: ['この画面を表示できませんでした。続けるにはアプリを開き直してください。', 'アプリを開き直す'],
    ko: ['이 화면을 표시할 수 없습니다. 계속하려면 앱을 다시 열어 주세요.', '앱 다시 열기'],
    pl: ['Nie udało się wyświetlić tego ekranu. Otwórz aplikację ponownie, aby kontynuować.', 'Otwórz aplikację ponownie'],
    pt: ['Não foi possível exibir esta tela. Abra o aplicativo novamente para continuar.', 'Reabrir aplicativo'],
    tr: ['Uygulama bu ekranı gösteremedi. Devam etmek için uygulamayı yeniden açın.', 'Uygulamayı yeniden aç']
  };
  function recoveryLanguage() {
    var preferred = [];
    try {
      var saved = JSON.parse(window.localStorage.getItem('flutter.app.language.v1'));
      if (typeof saved === 'string') preferred.push(saved);
    } catch (_) { /* Storage can be unavailable in private browsing. */ }
    var browser = window.navigator;
    if (browser) preferred = preferred.concat(browser.languages || [browser.language]);
    for (var i = 0; i < preferred.length; i++) {
      var code = String(preferred[i]).toLowerCase().split('-')[0];
      if (Object.prototype.hasOwnProperty.call(recoveryCopy, code)) return code;
    }
    return 'en';
  }
  function hide() {
    var panel = document.getElementById('example-recovery');
    if (panel) panel.remove();
  }
  function show() {
    pendingFailure = true;
    if (document.visibilityState === 'hidden' || document.getElementById('example-recovery')) return;
    var panel = document.createElement('div');
    panel.id = 'example-recovery';
    panel.setAttribute('role', 'alert');
    panel.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:var(--brand-background);color:var(--brand-ink);display:flex;flex-direction:column;align-items:center;justify-content:center;padding:24px;font:16px var(--brand-font,system-ui);text-align:center;gap:16px';
    var message = document.createElement('p');
    var language = recoveryLanguage();
    panel.lang = language;
    panel.dir = language === 'ar' ? 'rtl' : 'ltr';
    message.textContent = recoveryCopy[language][0];
    var button = document.createElement('button');
    button.textContent = recoveryCopy[language][1];
    button.style.cssText = 'border:0;border-radius:24px;padding:14px 28px;background:var(--brand-fill);color:var(--brand-on-fill);font:600 16px system-ui;cursor:pointer';
    button.onclick = function () { window.location.reload(); };
    panel.appendChild(message);
    panel.appendChild(button);
    document.body.appendChild(panel);
  }
  function armStartup() {
    clearTimeout(startupTimer);
    if (!ready && document.visibilityState !== 'hidden') startupTimer = setTimeout(show, 30000);
  }
  function draw() {
    if (document.visibilityState === 'hidden') return;
    try {
      window.dispatchEvent(new Event('resize'));
      if (redraw) redraw();
    } catch (error) {
      show();
    }
  }
  function requestRedraw() {
    if (document.visibilityState === 'hidden') return;
    // Android may resume JS before restarting animation callbacks. Do not put
    // the only repaint request behind the stalled renderer we are recovering.
    draw();
    clearTimeout(redrawTimer);
    redrawTimer = setTimeout(draw, 250);
  }
  function resume() {
    armStartup();
    if (document.visibilityState === 'hidden') {
      clearTimeout(resumeTimer);
      clearTimeout(redrawTimer);
      return;
    }
    if (pendingFailure) show();
    // A previously healthy renderer may have been discarded in the background.
    // Flutter acknowledges a rasterized frame, not merely a running JS timer.
    if (ready) {
      clearTimeout(resumeTimer);
      resumeTimer = setTimeout(show, 8000);
    }
    requestRedraw();
    if (graphicsLost) {
      clearTimeout(graphicsTimer);
      graphicsTimer = setTimeout(show, 3000);
    }
  }
  function frameRendered() {
    // Flutter 3.44 can report frame timings even after its context-loss handler
    // throws. Do not dismiss recovery while the graphics context is still lost.
    if (graphicsLost) return;
    pendingFailure = false;
    clearTimeout(graphicsTimer);
    clearTimeout(resumeTimer);
    hide();
  }
  window.exampleRecovery = {
    show: show,
    onRedraw: function (callback) { redraw = callback; },
    frameRendered: frameRendered,
  };
  window.addEventListener('flutter-first-frame', function () {
    ready = true;
    clearTimeout(startupTimer);
    frameRendered();
  });
  document.addEventListener('visibilitychange', resume);
  window.addEventListener('pageshow', resume);
  // Page Lifecycle resume also fires when Chrome thaws a frozen PWA.
  document.addEventListener('resume', resume);
  window.addEventListener('focus', resume);
  var seenEvents = new WeakSet();
  function lost(event) {
    if (seenEvents.has(event)) return;
    seenEvents.add(event);
    event.preventDefault();
    graphicsLost = true;
    clearTimeout(graphicsTimer);
    graphicsTimer = setTimeout(show, 3000);
    requestRedraw();
  }
  function restored() {
    graphicsLost = false;
    requestRedraw();
  }
  document.addEventListener('webglcontextlost', lost, true);
  document.addEventListener('webglcontextrestored', restored, true);

  // OffscreenCanvas and canvases inside Flutter's shadow tree do not deliver
  // these events to document. Observe their actual WebGL context targets.
  var watched = new WeakSet();
  function observeContexts(Canvas) {
    if (!Canvas || !Canvas.prototype.getContext) return;
    var original = Canvas.prototype.getContext;
    Canvas.prototype.getContext = function (type) {
      var context = original.apply(this, arguments);
      if (context && (type === 'webgl' || type === 'webgl2' || type === 'experimental-webgl') && !watched.has(this)) {
        watched.add(this);
        this.addEventListener('webglcontextlost', lost);
        this.addEventListener('webglcontextrestored', restored);
      }
      return context;
    };
  }
  observeContexts(window.HTMLCanvasElement);
  observeContexts(window.OffscreenCanvas);
  armStartup();
})();
