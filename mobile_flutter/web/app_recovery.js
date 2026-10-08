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
    message.textContent = 'The app could not display this screen. Please reopen it to continue.';
    var button = document.createElement('button');
    button.textContent = 'Reopen app';
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
