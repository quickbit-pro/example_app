/* Standalone customer guide. No network calls, accounts or server mutations. */
(() => {
  'use strict';
  const data = JSON.parse(document.getElementById('guide-data').textContent);
  const E = globalThis.BrandGuideEngine;
  const F = globalThis.BrandGuideFiles;
  const S = globalThis.CustomerServerGuide;
  const clone = value => JSON.parse(JSON.stringify(value));
  let config = E.init(data.configs.sample);
  Object.assign(config.app, {name: 'Customer Pay', id: 'customer', legalEntity: '', supportEmail: 'support@example.com'});
  Object.assign(config.native, {androidApplicationId: 'com.example.customer', iosBundleId: 'com.example.customer'});
  Object.assign(config.flutterDefines, {APP_FLAVOR: 'prod', API_BASE_URL: 'https://api.example.com'});
  const server = {apiDomain: 'api.example.com', appDomain: 'app.example.com', adminDomain: 'admin.example.com',
    dbMode: 'local', dbHost: '127.0.0.1', dbPort: '5432', dbName: 'customer', dbUser: 'customer_app',
    dbSslMode: 'VerifyFull', dbRootCert: '', repoUrl: 'https://github.com/quickbit-pro/example_app.git'};
  const assets = new Map();
  let lastImport = '';
  let step = 0, previewMode = 'light', previewScreen = 'home', toastTimer, fieldCounter = 0;
  // Steps 1–4 (zero-based) edit the brand config and show the live preview.
  // The other steps are reading material: overview, local run, customization, server, export.
  const steps = [
    {short: 'Before you start', title: 'Know what you are building.', description: 'Three programs, one database, one server, one platform. Read this page first: it lists what you need from Hoppa, from the customer and on your own laptop, and how long each phase usually takes.', kind: 'doc'},
    {short: 'Brand basics', title: 'Make it yours.', description: 'Start with the details your customers see. One configuration powers Android, iOS and the web app.', kind: 'brand'},
    {short: 'Colors & type', title: 'A look that feels like you.', description: 'Choose a starting palette, then tune the details. Light and dark appearances are configured independently.', kind: 'brand'},
    {short: 'Logos & launch', title: 'Your brand, from the first tap.', description: 'Add your artwork once. The app’s build tools create platform icons, splash images and the animated loader.', kind: 'brand'},
    {short: 'Connections', title: 'Give your app a home.', description: 'Set public domains and optional mobile services. Database passwords and provider secrets belong on the server, never in this app config.', kind: 'brand'},
    {short: 'Run it on your laptop', title: 'See it running before any server exists.', description: 'Start the API, the admin website and the app on your own computer with a local database. Every command says what you should see. No server, domain or certificate is needed yet.', kind: 'doc'},
    {short: 'Customize beyond branding', title: 'Change screens, text and features.', description: 'Where each part of the code lives, how to change a sentence, how to add a screen, which product features can be switched on, and how to build for release.', kind: 'doc'},
    {short: 'Server setup', title: 'Prepare the customer installation.', description: 'A separate Linux server, customer database and customer domains. Each command block says where it runs. Follow it with your technical team; this page does not run commands.', kind: 'doc'},
    {short: 'Review & export', title: 'Ready for the handoff.', description: 'Review your choices, download the config or a complete handoff bundle, then validate and build the app.', kind: 'doc'}
  ];
  const WHERE_HINT = {Laptop: 'your own computer', Server: 'the customer’s Ubuntu server, inside an SSH session', 'Database admin': 'a psql session signed in as the database administrator'};
  const whereClass = where => 'where where-' + String(where).toLowerCase().replace(/[^a-z]+/g, '-');
  function whereBadge(where) { return where ? `<span class="${whereClass(where)}" title="Run this on ${esc(WHERE_HINT[where] || where)}">Run on: ${esc(where)}</span>` : ''; }
  function codeBlock(code, where, language = 'bash') { return `<div class="code-wrap">${whereBadge(where)}<button class="copy" data-copy-code>Copy</button><pre><code data-language="${esc(language)}">${esc(code)}</code></pre></div>`; }
  // One numbered step of reading material: what it does, the command, what you should see, what to watch out for.
  function docStep(item, index) {
    return `<div class="guide-step"><h3>${index + 1}. ${esc(item.title)}</h3>${item.text ? `<p><strong>What this does:</strong> ${esc(item.text)}</p>` : ''}${item.code ? codeBlock(item.code, item.where, item.language) : ''}${item.html || ''}${item.expect ? `<p class="expect"><strong>What you should see:</strong> ${esc(item.expect)}</p>` : ''}${item.watch ? `<p class="watch"><strong>Watch out:</strong> ${esc(item.watch)}</p>` : ''}</div>`;
  }
  const $ = id => document.getElementById(id);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const get = path => path.split('.').reduce((value, key) => value?.[key], config);
  function put(path, value) {
    const parts = path.split('.'); let target = config;
    for (const key of parts.slice(0, -1)) { if (!Object.hasOwn(target, key)) target[key] = {}; target = target[key]; }
    target[parts.at(-1)] = value;
  }
  const human = value => value.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, c => c.toUpperCase());
  function toast(message) { $('toast').textContent = message; $('toast').hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').hidden = true, 5000); }
  function cssColor(color) { if (!/^#[\da-f]{6}([\da-f]{2})?$/i.test(color || '')) return '#808080'; return color.length === 9 ? '#' + color.slice(3) + color.slice(1, 3) : color; }
  function field(path, label, hint = '', opts = {}) {
    const value = get(path) ?? '';
    let input;
    if (opts.choices) input = `<select id="f-${path}" data-field="${path}">${opts.choices.map(choice => {const [key,text] = Array.isArray(choice) ? choice : [choice,choice]; return `<option value="${esc(key)}" ${value === key ? 'selected' : ''}>${esc(text)}</option>`;}).join('')}</select>`;
    else if (opts.area) input = `<textarea id="f-${path}" data-field="${path}">${esc(value)}</textarea>`;
    else input = `<input id="f-${path}" data-field="${path}" type="${opts.type || 'text'}" value="${esc(value)}" ${opts.min !== undefined ? `min="${opts.min}" max="${opts.max}" step="${opts.step ?? 1}"` : ''} ${opts.list ? `list="${opts.list}"` : ''} autocomplete="off" spellcheck="false">`;
    return `<div class="field ${opts.full ? 'full' : ''}"><label for="f-${path}">${esc(label)}</label>${input}${hint ? `<div class="hint">${esc(hint)}</div>` : ''}</div>`;
  }
  function colorField(path, label) {
    const color = get(path) || '#FFFFFF';
    const id = `color-${fieldCounter++}`;
    return `<div class="field"><label for="${id}">${esc(label)}</label><div class="color-control"><input type="color" data-color="${path}" value="#${esc(color.slice(-6))}" aria-label="Choose ${esc(label)}"><input type="text" id="${id}" data-field="${path}" value="${esc(color)}" spellcheck="false" maxlength="9"></div></div>`;
  }
  function check(path, label, hint) {return `<label class="check-row"><input type="checkbox" data-field="${path}" ${get(path) ? 'checked' : ''}><span>${esc(label)}${hint ? `<span class="hint" style="display:block">${esc(hint)}</span>` : ''}</span></label>`;}
  function serverField(key, label, hint = '', choices) {
    const input = choices ? `<select id="s-${key}" data-server="${key}">${choices.map(([value,text]) => `<option value="${esc(value)}" ${server[key] === value ? 'selected' : ''}>${esc(text)}</option>`).join('')}</select>` : `<input id="s-${key}" data-server="${key}" value="${esc(server[key])}" autocomplete="off" spellcheck="false">`;
    return `<div class="field"><label for="s-${key}">${esc(label)}</label>${input}<div class="hint">${esc(hint)}</div></div>`;
  }
  function assetURL(path) { const item = assets.get(path); return item ? `data:${item.mime};base64,${item.data}` : ''; }
  function referencedAssets() {
    const entries = [config.design.assets.logo, config.design.assets.logoDark, config.design.assets.splash, config.design.assets.loader, config.native.icon,
      ...Object.values(config.native.firebase || {}), ...(config.fonts || []).flatMap(font => font.files.map(file => file.path))];
    return [...new Set(entries.filter(Boolean))];
  }
  function metadata() { return Object.fromEntries([...assets].map(([path,item]) => [path,item.metadata || {valid:true}])); }
  function validation() { return E.validateConfig(config, metadata()); }
  function errorsHTML(errors) { return errors.length ? `<div class="error-list" role="alert"><strong>Check these details</strong><ul>${errors.map(error => `<li>${esc(typeof error === 'string' ? error : error.path + ': ' + error.message)}</li>`).join('')}</ul></div>` : ''; }
  function modeButtons(scope) { return `<div class="segmented" aria-label="${scope === 'preview' ? 'Preview appearance' : 'Palette appearance'}"><button data-mode="light" aria-pressed="${previewMode === 'light'}">Light</button><button data-mode="dark" aria-pressed="${previewMode === 'dark'}">Dark</button></div>`; }
  let flutterPreview = null, flutterStarting = false, previewTimer;
  function previewState() {
    const firebasePaths = new Set(Object.values(config.native.firebase || {}));
    const visualPaths = new Set([
      ...Object.values(config.design.assets || {}),
      ...(config.fonts || []).flatMap(font => font.files.map(file => file.path)),
    ].filter(path => path && !firebasePaths.has(path)));
    const previewAssets = Object.fromEntries([...assets].filter(([path]) => visualPaths.has(path)).map(([path,item]) => [path,{data:item.data,mime:item.mime}]));
    return {type:'customer-brand-update',config:clone(config),assets:previewAssets,theme:previewMode,screen:previewScreen};
  }
  function renderPreview() {
    if (!$('flutter-preview-mount')) {
      $('preview').innerHTML = `<div class="preview-head"><span>Actual Flutter preview</span><span class="tag">Real app</span></div><div id="preview-controls"></div><div id="flutter-preview-mount" class="flutter-viewport"><div class="flutter-loading"><strong>Starting the app preview…</strong><span>The Flutter runtime is included in this file.</span></div></div><div class="preview-runtime-status hint" id="preview-runtime-status" role="status" aria-live="polite">Loading locally. No customer API connection.</div><button class="btn small-btn preview-expand" id="preview-expand">Expand preview ↗</button><p class="preview-caption">The production Flutter screens and components, with sample data. Scroll and inspect the real layouts. Authentication and payment actions do not contact a server. Sample issued cards omit provider-supplied artwork.</p>`;
      $('preview-expand').onclick = expandPreview;
      const mount=$('flutter-preview-mount');
      mount.addEventListener('customer-preview-applied',()=>{mount.querySelector('.flutter-loading')?.remove();$('preview-runtime-status').textContent='Actual Flutter screens · sample data · no live API';});
      mount.addEventListener('customer-preview-notice',event=>{$('preview-runtime-status').textContent=event.detail.message || 'This action is unavailable in the sample preview.';});
      mount.addEventListener('customer-preview-status',event=>{$('preview-runtime-status').textContent=event.detail.message || 'Loading Flutter…';});
      mount.addEventListener('customer-preview-error',event=>{$('preview-runtime-status').textContent='Preview: '+event.detail.message;});
    }
    $('preview-controls').innerHTML = `<div class="between">${modeButtons('preview')}<label class="hint" for="preview-screen-select">Screen <select id="preview-screen-select" aria-label="App preview screen">${[['home','Home'],['login','Login'],['cards','Cards'],['profile','Profile'],['splash','Splash replay'],['loader','Loader']].map(([value,label])=>`<option value="${value}" ${previewScreen===value?'selected':''}>${label}</option>`).join('')}</select></label></div>`;
    $('preview-screen-select').onchange = event => {previewScreen=event.target.value;renderPreview();};
    $('preview-controls').querySelectorAll('[data-mode]').forEach(button=>button.onclick=()=>{previewMode=button.dataset.mode;render();});
    const report=E.validateConfig(config);
    if(!report.valid) {$('preview-runtime-status').textContent='Fix the invalid config fields to update the preview. The last valid appearance stays visible.';return;}
    if(!flutterPreview && !flutterStarting) {
      flutterStarting=true;
      const payload=JSON.parse($('flutter-preview-data').textContent);
      Promise.resolve(globalThis.CustomerFlutterPreview.create($('flutter-preview-mount'),payload)).then(handle=>{
        flutterPreview=handle;handle.post(previewState());
      }).catch(error=>{flutterStarting=false;$('preview-runtime-status').textContent='Preview could not start: '+error.message;});
    }
    clearTimeout(previewTimer);
    previewTimer=setTimeout(()=>{if(flutterPreview)flutterPreview.post(previewState());},120);
    if($('contrast-results'))$('contrast-results').innerHTML=validation().contrasts.filter(item=>item.mode===previewMode).slice(0,6).map(item=>`<div class="contrast-item"><span>${esc(item.label)}</span><span class="${item.pass?'good':'bad'}">${Number(item.ratio).toFixed(2)}:1 ${item.pass?'✓':'· review'}</span></div>`).join('');
  }
  function expandPreview() {
    let dialog=$('preview-dialog');
    if(!dialog){dialog=document.createElement('dialog');dialog.id='preview-dialog';dialog.className='preview-dialog';dialog.innerHTML='<div class="between"><strong>Actual Flutter app</strong><button class="btn small-btn" id="close-preview">Close ×</button></div><div id="expanded-controls"></div><div id="expanded-preview"></div>';document.body.append(dialog);$('close-preview').onclick=()=>dialog.close();dialog.addEventListener('close',()=>{$('preview').insertBefore($('preview-controls'),$('preview-runtime-status'));$('preview').insertBefore($('flutter-preview-mount'),$('preview-runtime-status'));});}
    $('expanded-controls').append($('preview-controls'));
    $('expanded-preview').append($('flutter-preview-mount'));dialog.showModal();
  }
  function renderBasics() {
    return `<div class="import-box"><span>Resume a saved handoff ZIP with its artwork, fonts and server choices, or import a config JSON.</span><button class="btn small-btn" data-action="import">Import ZIP / JSON</button></div>
    <section class="panel"><h2>Brand identity</h2><p class="lead">Use your customer-facing name. Support and legal details appear in the app where those fields are supported.</p><div class="fields">
    ${field('app.name','App name','Displayed in the app, launcher and web title.')}${field('app.id','Brand ID','Lowercase, 2–64 characters. Use a short unique ID for the Linux installation.')}
    ${field('app.description','Short description','A short description for the app shell.',{area:true,full:true})}
    ${field('app.supportEmail','Support email')}${field('app.supportPhone','Support phone','Optional, including country code.')}${field('app.legalEntity','Legal entity','Use the customer’s approved legal name.',{full:true})}
    ${field('app.themeMode','Starting appearance','Users can save their own preference later.',{choices:[['system','Follow device'],['light','Light'],['dark','Dark']]})}
    ${field('design.layout','Screen layout','Full app keeps the existing banking layouts.',{choices:[['example','Full app (recommended)'],['generic','Generic variants']]})}</div>
    <div class="note">Your logo, name and palette come from this configuration.</div></section>
    <section class="panel"><h2>Installed-app identity</h2><p class="lead">Use application IDs owned by the customer. Confirm these before store registration; changing them creates a different installed app.</p><div class="fields">
    ${field('native.androidApplicationId','Android application ID','For example com.yourcompany.pay.')}${field('native.iosBundleId','iOS bundle ID','Usually the same reverse-domain name.')}</div></section>`;
  }
  function renderColors() {
    const mode = previewMode;
    const palette = config.design[mode];
    const contrast = validation().contrasts.filter(item => item.mode === mode).slice(0, 6);
    return `<section class="panel"><div class="between"><h2>Choose your palette</h2>${modeButtons('edit')}</div><p class="lead">Use a starting point, or set your colors. Presets replace both palettes; all other brand details stay as you entered them.</p>
    <div class="preset-row">${[['sample','Ocean'],['hoppa','Purple & lime'],['sunrise','Warm sunset']].map(([key,label]) => `<button class="preset" data-preset="${key}"><span class="swatches"><i style="background:${data.configs[key].design.light.fill}"></i><i style="background:${data.configs[key].design.dark.fill}"></i></span>${label}</button>`).join('')}</div>
    <div class="compact-grid">${['fill','accent','paper','surface','ink','onFill'].map(key => colorField(`design.${mode}.${key}`, {fill:'Primary / button',accent:'Accent / links',paper:'Page background',surface:'Panels',ink:'Main text',onFill:'Button text'}[key])).join('')}</div>
    <div class="actions" style="margin-top:18px"><button class="btn soft" data-action="generate-palette">Generate matching ${mode} palette</button></div><p class="hint" style="margin-top:9px">This replaces the full ${mode} palette using your primary, accent, page, panel and text colors. Individual edits otherwise leave your advanced tokens intact.</p>
    <div class="contrast-items" id="contrast-results">${contrast.map(item => `<div class="contrast-item"><span>${esc(item.label)}</span><span class="${item.pass ? 'good' : 'bad'}">${Number(item.ratio).toFixed(2)}:1 ${item.pass ? '✓' : '· review'}</span></div>`).join('')}</div>
    <div class="advanced"><details><summary>All ${mode} color tokens (${Object.keys(palette).length})</summary><p>Fine-tune surfaces, text, status colors, card gradients and effects. Colors use <code>#RRGGBB</code>, or <code>#AARRGGBB</code> with alpha first.</p><div class="token-grid">${Object.keys(palette).map(key => colorField(`design.${mode}.${key}`,human(key))).join('')}</div></details></div></section>
    <section class="panel"><h2>Typography & shape</h2><p class="lead">Geist and Geist Mono are already bundled. For another family, supply the licensed font files below.</p><datalist id="font-families"><option value="Geist"><option value="GeistMono">${config.fonts.map(font => `<option value="${esc(font.family)}">`).join('')}</datalist><div class="fields">
    ${field('design.typography.fontFamily','Main font family','Use a bundled family or one you add below.',{list:'font-families'})}${field('design.typography.monoFontFamily','Number / mono family','For tabular and code-like content.',{list:'font-families'})}
    ${field('design.typography.scale','Text scale','1 is the original size; 0.75–1.5 supported.',{type:'number',min:.75,max:1.5,step:.05})}${field('design.shape.radiusScale','Corner scale','0 for square; 1 for original; up to 2.',{type:'number',min:0,max:2,step:.1})}</div>
    <div id="font-entries">${config.fonts.map((font,i) => `<div class="font-entry"><div class="between"><strong>${esc(font.family || 'Custom font')}</strong><button class="btn small-btn" data-remove-font="${i}">Remove family</button></div><div class="fields">${field(`fonts.${i}.family`,'Family name')}</div>${font.files.map((file,j) => `<div class="fields" style="margin-top:12px">${field(`fonts.${i}.files.${j}.path`,'Font path','Relative to brand.json.')}${field(`fonts.${i}.files.${j}.weight`,'Weight','100–900 in steps of 100.',{type:'number',min:100,max:900,step:100})}${field(`fonts.${i}.files.${j}.style`,'Style','',{choices:['normal','italic']})}<div class="field"><label for="font-upload-${i}-${j}">Choose TTF / OTF</label><input id="font-upload-${i}-${j}" type="file" data-font-upload="${i}:${j}" accept=".ttf,.otf"><span class="hint">${assets.has(file.path) ? 'File included' : 'No file included yet'}</span></div></div>`).join('')}<button class="btn small-btn" style="margin-top:12px" data-add-weight="${i}">Add weight</button></div>`).join('')}</div>
    <div class="actions" style="margin-top:15px"><button class="btn" data-action="add-font">Add font family</button><label class="btn" for="font-license">Add font license</label><input type="file" id="font-license" accept=".txt" hidden></div><p class="hint" style="margin-top:10px">The Flutter preview uses the real bundled fonts and loads your uploaded font files. License text files are included in your handoff.</p></section>`;
  }
  const assetFields = [
    ['design.assets.logo','Main logo','Required. Compact artwork works best in the current square logo slots.'],
    ['design.assets.logoDark','Logo on dark backgrounds','Optional. Falls back to the main logo.'],
    ['native.icon','App icon','Required. Aim for a square 1024 × 1024 source.'],
    ['design.assets.splash','Splash artwork','Optional. Falls back to the logo for the active appearance.'],
    ['design.assets.loader','Loader artwork','Optional. Falls back to the matching logo.']
  ];
  function renderAssets() {
    return `<section class="panel"><h2>Your artwork</h2><p class="lead">Choose PNG, JPEG, WebP or GIF. This guide converts uploads to a static PNG, matching the build’s first-frame behavior. Export SVG artwork to PNG first.</p><div class="asset-list">${assetFields.map(([path,label,hint]) => {
      const current = get(path); const item = assets.get(current);
      return `<div class="asset-row"><div class="asset-thumb">${item ? `<img src="${assetURL(current)}" alt="${esc(label)}">` : '<span aria-hidden="true">＋</span>'}</div><div><label for="asset-${path}">${label}</label><div class="hint">${hint}</div><input id="asset-${path}" type="file" data-asset="${path}" accept=".png,.jpg,.jpeg,.webp,.gif"><div class="asset-path">${esc(current || 'Using logo fallback')}${item?.example ? ' · example artwork' : item ? ' · included' : current ? ' · file needed' : ''}</div><div class="actions">${path !== 'design.assets.logo' ? `<button class="btn small-btn" data-use-logo="${path}">${path === 'native.icon' ? 'Use main logo' : 'Use logo fallback'}</button>` : '<button class="btn small-btn" data-action="reuse-logo">Use main logo everywhere</button>'}</div></div></div>`;
    }).join('')}</div><div class="note">The bundle includes the actual uploaded files. The JSON contains relative file paths, not embedded images or remote image URLs.</div></section>
    <section class="panel"><h2>Splash & loader</h2><div class="fields">${colorField('native.iconBackground','Icon background')}${field('design.loader.style','Loader style','Use logo or circular for customer branding.',{choices:[['logo','Animate my logo'],['circular','Circular spinner']]})}
    ${colorField('design.splash.backgroundLight','Light splash background')}${colorField('design.splash.backgroundDark','Dark splash background')}
    ${field('design.loader.durationMs','Loader cycle (ms)','200–10000 ms.',{type:'number',min:200,max:10000,step:100})}${field('design.motion.durationScale','Motion speed scale','0.1–3; 1 preserves the original timing.',{type:'number',min:.1,max:3,step:.1})}
    ${field('design.splash.minimumDurationMs','Minimum app splash (ms)','0–10000 ms.',{type:'number',min:0,max:10000,step:100})}${field('design.splash.maximumDurationMs','Maximum app splash (ms)','0–30000 ms; at least the minimum.',{type:'number',min:0,max:30000,step:100})}</div>
    ${check('design.splash.enabled','Show splash artwork','OS launch screens are static; the app and web manage their own loading presentation.')}${check('design.motion.enabled','Enable branding animation','Reduced-motion preferences are also respected by supported loaders.')}
    <div class="note">Native splash and icon background colors must be opaque. The mobile OS controls native launch duration; these duration values configure the Flutter presentation.</div></section>`;
  }
  function renderConnections() {
    return `<section class="panel"><h2>Public endpoints</h2><p class="lead">Use three domains with DNS pointing at the customer’s server. The API is compiled into the app, so changing it requires rebuilding.</p><div class="fields">
    ${serverField('apiDomain','API domain','Hostname only, such as api.yourcompany.com.')}${serverField('appDomain','Web / PWA domain','Hostname only, such as app.yourcompany.com.')}${serverField('adminDomain','Admin domain','Hostname only, such as admin.yourcompany.com.')}
    ${field('flutterDefines.API_BASE_URL','App API URL','Kept in sync when the API domain changes. HTTPS is required for production.')}${field('flutterDefines.APP_FLAVOR','Build mode','Production is appropriate for a hosted customer app.',{choices:[['prod','Production'],['staging','Staging'],['dev','Development']]})}
    ${field('app.transferDashboardUrl','External transfer dashboard','Optional. Leave empty unless your product uses a separate dashboard.',{full:true})}</div>
    <div class="note">Use the customer’s own API address here. For running on your laptop (step 6) you do not change this field; the local run command overrides the address with <code>http://localhost:5188</code>.</div></section>
    <section class="panel"><h2>Mobile push (optional)</h2><p class="lead">Leave Firebase empty to disable client push. To enable it, create the customer’s Firebase project and register the exact application IDs from step 2.</p><div class="fields">
    ${field('native.firebase.android','Android client config path','Optional, for example private/google-services.json.')}${field('native.firebase.ios','iOS client config path','Optional, for example private/GoogleService-Info.plist.')}
    <div class="field"><label for="firebase-android">Android client JSON</label><input type="file" id="firebase-android" data-firebase="android" accept=".json"></div><div class="field"><label for="firebase-ios">iOS client plist</label><input type="file" id="firebase-ios" data-firebase="ios" accept=".plist"></div></div>
    <div class="actions" style="margin-top:16px"><button class="btn small-btn" data-action="disable-firebase">Clear Firebase / disable push</button></div>
    <div class="note">Upload only client configuration files, never a Firebase Admin service-account key. APNs setup, signing capabilities and backend push credentials are configured separately by the technical team.</div></section>
    <section class="panel"><h2>Provider & platform handoff</h2><ul class="inline-list"><li>Arrange the customer’s payment/banking provider installation, API credentials and webhook registrations with your integration team.</li><li>Confirm supported account, card, KYC and payment features in the backend before promising them in the branded app.</li><li>Configure the customer’s transactional email sender and delivery provider on the server.</li><li>For native releases, supply the customer’s Android signing key / Play Console account and Apple team / App Store Connect setup. An iOS build requires macOS and Xcode.</li><li>The admin’s name and logo use its build settings; its full theme is separate from this mobile config. Provider-hosted flows also keep their provider’s own appearance.</li></ul></section>`;
  }
  function architectureSVG() {
    const box = (x, y, w, h, lines, cls = '') => `<rect class="arch-box ${cls}" x="${x}" y="${y}" width="${w}" height="${h}" rx="10"/>${lines.map((line, i) => `<text x="${x + w / 2}" y="${y + 22 + i * 17}" text-anchor="middle" class="${i ? 'arch-sub' : 'arch-title'}">${esc(line)}</text>`).join('')}`;
    const arrow = (x1, y1, x2, y2, label, both = false) => `<line class="arch-arrow" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" marker-end="url(#arch-head)" ${both ? 'marker-start="url(#arch-head)"' : ''}/>${label ? `<text x="${(x1 + x2) / 2}" y="${(y1 + y2) / 2 - 6}" text-anchor="middle" class="arch-label">${esc(label)}</text>` : ''}`;
    return `<svg class="arch" viewBox="0 0 780 380" role="img" aria-labelledby="arch-title-text"><title id="arch-title-text">Architecture: the customer app and admin website call the API through nginx on one Linux server; the API uses PostgreSQL and the Hoppa platform.</title>
<defs><marker id="arch-head" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="currentColor"/></marker></defs>
${box(40, 24, 220, 64, ['Customer app', 'phone (Android, iOS) and browser (PWA)'], 'arch-client')}
${box(300, 24, 220, 64, ['Admin website', 'used by the customer’s staff'], 'arch-client')}
<rect class="arch-server" x="24" y="132" width="516" height="222" rx="14"/><text x="40" y="154" class="arch-caption">One Linux server (Ubuntu 24.04)</text>
${box(48, 168, 468, 44, ['nginx · public HTTPS on ports 80 and 443'])}
${box(48, 248, 220, 76, ['API (.NET)', 'listens on 127.0.0.1:5300', 'all business logic and secrets'], 'arch-api')}
${box(300, 248, 216, 76, ['PostgreSQL', 'users, cards, settings', 'one database for this customer'])}
${box(590, 248, 170, 76, ['Hoppa platform', 'accounts, cards, KYC', 'reached with the API key'], 'arch-hoppa')}
${arrow(150, 88, 150, 168, 'HTTPS')}${arrow(410, 88, 410, 168, 'HTTPS')}
${arrow(158, 212, 158, 248, 'forwarded to port 5300')}
${arrow(268, 286, 300, 286, '')}
${arrow(516, 286, 590, 286, 'API calls', true)}
<text x="650" y="346" text-anchor="middle" class="arch-label">webhooks come back the same way</text>
</svg>`;
  }
  function renderStart() {
    const prerequisites = [
      ['From Hoppa (your provider contact)', [
        ['Platform API base URL', 'The HTTPS address of the Hoppa platform your API will call. The exported settings show https://staging.hoppa.global/ for development; check with your Hoppa contact which address is right for you.'],
        ['Company API key', 'One secret key that identifies your company. It lives only in the API settings, never in the app or admin code.'],
        ['Webhook signing secrets', 'Two shared secrets (Hoppa and SumSub). They prove that an incoming event really came from the provider.'],
        ['The list of enabled features', 'Which products (accounts, cards, KYC, referrals, vouchers, exchange, business onboarding) are switched on for your company. Only enable the same ones in the API.']
      ]],
      ['From the customer', [
        ['Three domain names', 'One for the API, one for the app, one for the admin website (for example api., app., admin.). The customer must control their DNS.'],
        ['An Ubuntu 24.04 server', 'A fresh virtual machine with SSH access and sudo rights. 2 vCPU, 4 GB RAM and 30 GB SSD is a practical start.'],
        ['A SendGrid account', 'For verification and password-reset emails. A sender address or domain must be verified in SendGrid.'],
        ['Google Play and Apple developer accounts', 'Only for native store releases. The customer owns the app IDs, the signing keys and the store listings.']
      ]],
      ['On your laptop (the developer)', [
        ['.NET 10 SDK', 'Builds and runs the API. Check with: dotnet --version'],
        ['Node.js 24 with npm', 'Builds and runs the admin website. Check with: node --version'],
        ['Flutter 3.44 (Dart 3.12)', 'Builds and runs the app for web, Android and iOS. Check with: flutter --version'],
        ['Python 3.10 or newer', 'Runs the branding tool that turns brand.json into icons, splash images and build settings. Check with: python3 --version'],
        ['Git', 'To clone the repository and record your changes. Check with: git --version'],
        ['PostgreSQL 16 or Docker', 'A local database for the laptop run in step 6. Either install PostgreSQL or run it in one Docker container.']
      ]]
    ];
    const phases = [
      ['Before you start', 'Half a day of reading, then waiting for accounts and keys from Hoppa and the customer (often 1–5 working days).'],
      ['Brand basics, colors, logos, connections (steps 2–5)', '2–4 hours with the artwork at hand.'],
      ['Run it on your laptop (step 6)', 'Half a day the first time, including tool installation.'],
      ['Customize beyond branding (step 7)', 'Open-ended. A text change takes minutes; a new screen takes hours to days.'],
      ['Server setup (step 8)', '1–2 days for a first installation, plus 1–2 days of acceptance testing with the customer.'],
      ['Native store release', '1–2 weeks of calendar time for store review, after signing and accounts exist.']
    ];
    return `<section class="panel"><h2>What you are building</h2><p class="lead">The product has three parts. They all talk to one API, and only the API talks to the Hoppa platform.</p><ol class="inline-list">
    <li><strong>The customer app.</strong> One Flutter code base that runs on Android, iOS and in the browser as a PWA (a website that installs like an app). Folder: <code>mobile_flutter/</code>.</li>
    <li><strong>The admin website.</strong> A Vue website for the customer’s staff: customers, verification, cards, support tickets, email templates. Folder: <code>admin_vue/</code>.</li>
    <li><strong>The API.</strong> A .NET program. It holds every business rule, the database and the Hoppa API key. The app and the admin website call it; it calls Hoppa. Folder: <code>backend/</code>.</li></ol>
    <p>One PostgreSQL database stores users, cards and settings. One Linux server (Ubuntu 24.04) runs the API, the database and nginx, the public web server. The Hoppa platform is where accounts, cards and identity checks (KYC) really live.</p>
    ${architectureSVG()}</section>
    <section class="panel"><h2>Prerequisites checklist</h2><p class="lead">Tick each item when you have it. Nothing on this page is saved; the list is here so you can ask for everything at once.</p>${prerequisites.map(([group, items]) => `<h3>${esc(group)}</h3><table class="doc-table"><thead><tr><th></th><th>Item</th><th>What it is and why you need it</th></tr></thead><tbody>${items.map(([item, why]) => `<tr><td><input type="checkbox" aria-label="${esc(item)}"></td><td><strong>${esc(item)}</strong></td><td>${esc(why)}</td></tr>`).join('')}</tbody></table>`).join('')}
    <div class="note">Secrets (API keys, passwords, signing keys) are never typed into this page. This page only prepares public branding and instructions.</div></section>
    <section class="panel"><h2>How long it takes</h2><p class="lead">Realistic estimates for one developer who is new to this stack. Waiting for other people is usually the longest part.</p><table class="doc-table"><thead><tr><th>Phase</th><th>Estimate</th></tr></thead><tbody>${phases.map(([phase, time]) => `<tr><td><strong>${esc(phase)}</strong></td><td>${esc(time)}</td></tr>`).join('')}</tbody></table></section>
    <section class="panel"><h2>How to read this guide</h2><ul class="inline-list">
    <li><strong>Badges say where a command runs.</strong> ${whereBadge('Laptop')} is your own computer. ${whereBadge('Server')} is the customer’s Ubuntu server, inside an SSH session. ${whereBadge('Database admin')} is a psql session signed in as the database administrator. Never run a Server command on your laptop or the other way round.</li>
    <li><strong>Copy buttons.</strong> Every command block has a Copy button in its top-right corner. Paste the whole block into the terminal named by the badge.</li>
    <li><strong>“What you should see”</strong> follows each command. If your output differs, stop and read the “Watch out” line before continuing.</li>
    <li><strong>Steps 2–5</strong> edit the app configuration and show a live preview of the real app. <strong>Steps 6–8</strong> are reading material with commands. <strong>Step 9</strong> exports everything as one ZIP file.</li>
    <li><strong>Every term is defined the first time it appears</strong>, and again in the Glossary at the end of the Server setup step.</li></ul></section>`;
  }
  function renderLaptop() {
    const id = config.app.id;
    const repoName = (server.repoUrl.split('/').pop() || 'example_app').replace(/\.git$/, '');
    const brand = `mobile_flutter/config/${id}/brand.json`;
    const localSettings = JSON.stringify({
      ConnectionStrings: {NeoBankingDb: 'Host=localhost;Port=5432;Database=neobank_dev;Username=neobank;Password=devpassword'},
      Jwt: {SigningKey: 'local-development-only-signing-key-0123456789abcdef'},
      Hoppa: {BaseUrl: 'https://staging.hoppa.global/', ApiKey: 'PASTE-THE-COMPANY-API-KEY-FROM-YOUR-HOPPA-CONTACT', WebhookSecret: 'any-long-random-text-for-local-use-only', SumSubWebhookSecret: 'any-long-random-text-for-local-use-only'},
      Email: {Provider: 'log'}
    }, null, 2);
    const keys = [
      ['ConnectionStrings:NeoBankingDb', 'How the API reaches PostgreSQL: host, port, database name, login and password in one line.'],
      ['Jwt:SigningKey', 'The secret that signs login tokens. Any text of 32 characters or more works on a laptop. The server generates its own.'],
      ['Jwt:Issuer, Jwt:Audience', 'Names written into every login token. Keep the values from appsettings.Development.json.'],
      ['Hoppa:BaseUrl', 'The address of the Hoppa platform. The exported file says https://staging.hoppa.global/; check with your Hoppa contact that this is right for you.'],
      ['Hoppa:ApiKey', 'Your company key from Hoppa. Without it, sign-up and every account or card screen in the app fails, but the API, the admin website and the login screen still start.'],
      ['Hoppa:WebhookSecret, Hoppa:SumSubWebhookSecret', 'Shared secrets that prove a webhook came from Hoppa or SumSub. On a laptop no webhooks arrive, so any long random text is fine.'],
      ['Company:*', 'The name, brand name and branding the API reports to the app. The development values are fine for a laptop.'],
      ['Email:Provider', '"log" writes every email (verification codes, password resets) to the API console instead of sending it. Use "sendgrid" only on the server.'],
      ['Cors:AllowedOrigins', 'Not needed on a laptop: in Development the API automatically allows localhost and 127.0.0.1 origins.']
    ];
    const items = [
      {title: 'Get the source code', where: 'Laptop', text: `Downloads the repository into a folder named ${repoName} and enters it. All later commands in this step run from that folder unless the command changes directory.`, code: `git clone ${shell(server.repoUrl)}\ncd ${shell(repoName)}`, expect: 'Folders named backend, admin_vue, mobile_flutter, scripts and docs.', watch: 'If you already exported the handoff ZIP (step 9), copy its config/ folder to ' + `mobile_flutter/config/${id}/` + ' now. Until then, mobile_flutter/config/sample.json is a complete example you can run.'},
      {title: 'Check your tools', where: 'Laptop', text: 'Prints the version of each tool from the prerequisites checklist.', code: 'dotnet --version\nnode --version\nnpm --version\nflutter --version\npython3 --version\ngit --version', expect: 'dotnet 10.x, node v24.x, flutter 3.44.x, python 3.10 or newer. Any "command not found" means that tool is missing.', watch: 'Flutter must be exactly the version tested for this repository (3.44.2). Other versions may fail to build.'},
      {title: 'Install PostgreSQL locally', where: 'Laptop', text: 'Installs the database on your laptop. Pick ONE option: a native install, or a single Docker container that already contains the user, password and database used in the next steps.', code: `# Option A — macOS with Homebrew\nbrew install postgresql@16\nbrew services start postgresql@16\n\n# Option B — Ubuntu or Debian\nsudo apt-get install -y postgresql-16\n\n# Option C — any OS with Docker (creates user neobank / password devpassword / database neobank_dev)\ndocker run --name neobank-dev-db -e POSTGRES_USER=neobank -e POSTGRES_PASSWORD=devpassword -e POSTGRES_DB=neobank_dev -p 5432:5432 -v neobank-dev-db:/var/lib/postgresql/data -d postgres:16`, expect: 'For A and B: "psql --version" prints 16.x. For C: "docker ps" lists neobank-dev-db with port 5432.', watch: 'On Windows, use the installer from postgresql.org or Docker Desktop. Only one PostgreSQL may use port 5432 at a time.'},
      {title: 'Create the development database', where: 'Laptop', text: 'Creates a database login (role) named neobank and an empty database neobank_dev that it owns. Skip this if you chose Docker; the container already did it. The last line logs in as that role to prove it works.', code: `# macOS Homebrew (your own user is the administrator):\npsql -d postgres -c "CREATE ROLE neobank LOGIN PASSWORD 'devpassword';" -c "CREATE DATABASE neobank_dev OWNER neobank;"\n# Ubuntu (the administrator is the postgres user):\nsudo -u postgres psql -c "CREATE ROLE neobank LOGIN PASSWORD 'devpassword';" -c "CREATE DATABASE neobank_dev OWNER neobank;"\n\n# Everyone: test the login.\npsql 'postgresql://neobank:devpassword@localhost:5432/neobank_dev' -c 'SELECT current_user, current_database();'`, expect: 'CREATE ROLE, CREATE DATABASE, then one row: neobank | neobank_dev.', watch: 'These are laptop-only credentials. The server uses its own role and a password chosen on the server (step 8, section 3).'},
      {title: 'Tell the API about the database and keys', where: 'Laptop', text: `The API reads backend/src/NeoBanking.Api/appsettings.json, then appsettings.Development.json (the export ships it with blank placeholders), then appsettings.Local.json. Git ignores the Local file, so create it for your real values and leave the other two untouched. This command writes it.`, code: `cat > backend/src/NeoBanking.Api/appsettings.Local.json <<'LOCAL_SETTINGS_JSON'\n${localSettings}\nLOCAL_SETTINGS_JSON`, html: `<table class="doc-table"><thead><tr><th>Key</th><th>What it means</th></tr></thead><tbody>${keys.map(([key, meaning]) => `<tr><td><code>${esc(key)}</code></td><td>${esc(meaning)}</td></tr>`).join('')}</tbody></table>`, expect: 'A new file backend/src/NeoBanking.Api/appsettings.Local.json. "git status" does not list it.', watch: 'Never paste production keys into a laptop file. appsettings.Local.json is read only when the API runs in Development mode, which "dotnet run" uses automatically.'},
      {title: 'Create the tables and the first administrator', where: 'Laptop', text: 'Downloads the .NET packages, then starts the API once with the --migrate-and-seed flag. The API creates every table in neobank_dev (a "migration") and creates one administrator from the two SeedAdmin values, then exits.', code: `dotnet restore backend/NeoBanking.sln\nSeedAdmin__Email='admin@example.com' SeedAdmin__Password='Local-Admin-Password-Change-Me-1' dotnet run --project backend/src/NeoBanking.Api/NeoBanking.Api.csproj -- --migrate-and-seed`, expect: '"Database migrated and admin account seeded for admin@example.com." The command takes a minute the first time.', watch: 'An error mentioning "connection" means the connection string or PostgreSQL is wrong; go back two steps. The password is hashed; the API never stores it in clear text.'},
      {title: 'Start the API', where: 'Laptop', text: 'Runs the API in Development mode. It stays in the foreground; leave this terminal open and use a new terminal for the next steps.', code: 'dotnet run --project backend/src/NeoBanking.Api/NeoBanking.Api.csproj', expect: '"Now listening on: http://localhost:5188". Open http://localhost:5188/health in a browser: {"status":"Healthy",...}. Opening http://localhost:5188 shows the API reference page.', watch: 'The port comes from backend/src/NeoBanking.Api/Properties/launchSettings.json (profile "http"). Press Ctrl+C to stop the API.'},
      {title: 'Start the admin website', where: 'Laptop', text: 'In a new terminal: installs the JavaScript packages and starts the Vite development server for the admin website, pointed at your local API. VITE_BACKEND_API_BASE_URL is the only address the admin ever calls; VITE_APP_NAME and VITE_APP_LOGO set its title and logo.', code: `cd admin_vue\nnpm install\nVITE_BACKEND_API_BASE_URL=http://localhost:5188 VITE_APP_NAME=${shell(config.app.name)} npm run dev`, expect: '"Local: http://localhost:5173/". Open it, sign in at /login with admin@example.com and the password from the migration step, and see the Overview page.', watch: 'You can also copy admin_vue/.env.example to admin_vue/.env and edit the three VITE_ lines there; Git ignores .env. Never put an API key in a VITE_ variable: it is compiled into the public website.'},
      {title: 'Run the app in Chrome', where: 'Laptop', text: `In a new terminal, from the repository root: creates a small Python environment for the branding tool, then runs the app through the branded run script. The script validates the JSON, generates icons and defines, and starts Flutter in Chrome. The last option points the app at your local API instead of the address stored in the JSON.`, code: `python3 -m venv .venv\n.venv/bin/pip install -r scripts/branding/requirements.txt\nexport BRANDING_PYTHON="$PWD/.venv/bin/python"\n./scripts/run-mobile-branded.sh ${shell(brand)} -d chrome --dart-define=API_BASE_URL=http://localhost:5188`, expect: 'Chrome opens with the branded login screen. Press "r" in the terminal to hot-reload after a code change.', watch: `Use mobile_flutter/config/sample.json instead of ${brand} until you have exported the ZIP. Sign-up in the app creates a user on the Hoppa platform, so it needs a working Hoppa:ApiKey; the seeded administrator is for the admin website only. Check with your Hoppa contact for a test user. A phone cannot reach "localhost"; for a phone use "dotnet run ... --launch-profile lan-http" (listens on port 8080 on all addresses) and your laptop's network IP. If the app still calls the address from the JSON, edit flutterDefines.API_BASE_URL in the JSON for local runs.`},
      {title: 'Stop everything', where: 'Laptop', text: 'Press Ctrl+C in each terminal (API, admin, Flutter). If you used Docker, stop the database container; its data is kept in the named volume.', code: 'docker stop neobank-dev-db\n# Later: docker start neobank-dev-db', expect: 'The container name printed once.'}
    ];
    return `<section class="panel"><h2>What runs where on your laptop</h2><table class="doc-table"><thead><tr><th>Program</th><th>Address</th><th>Started by</th></tr></thead><tbody>
    <tr><td>PostgreSQL</td><td>localhost:5432</td><td>Homebrew, apt or Docker</td></tr>
    <tr><td>API (.NET)</td><td>http://localhost:5188</td><td>dotnet run</td></tr>
    <tr><td>Admin website (Vue)</td><td>http://localhost:5173</td><td>npm run dev</td></tr>
    <tr><td>Customer app (Flutter web)</td><td>a port Chrome shows you</td><td>./scripts/run-mobile-branded.sh</td></tr></tbody></table>
    <div class="note">All ten commands below run on your laptop: ${whereBadge('Laptop')}. Keep three terminals open: one for the API, one for the admin, one for the app.</div></section>
    <section class="panel">${items.map(docStep).join('')}</section>`;
  }
  function renderCustomize() {
    const id = config.app.id;
    const features = [
      ['ReferralsEnabled', 'false', 'Shows the referral program (invite friends, earn rewards). Needs the referral module enabled for your company on Hoppa.'],
      ['ReferralRegistrationMode', '"optional"', '"optional" or "required": whether a referral code must be entered at sign-up. Only matters when referrals are on.'],
      ['VouchersEnabled', 'false', 'Lets users redeem voucher codes. Needs the voucher module on Hoppa.'],
      ['ExistingAccountClaimEnabled', 'false', 'Lets an existing Hoppa user connect this app by QR code or email code. Needs the Hoppa account-link endpoints for your company.'],
      ['BoomFiExchangeEnabled', 'false', 'Shows the BoomFi-backed exchange screens. The Hoppa company and the user must also be set up for BoomFi.'],
      ['WalletOutflowsEnabled', 'false', 'Allows operations that move funds out of a provider account. Keep off until the customer signs off operationally.'],
      ['EqualsMoneyEnabled', 'true', 'Shows EqualsMoney bank-account onboarding and account screens. Off means crypto cards only.'],
      ['BusinessOnboardingEnabled', 'true', 'Offers a business account type at sign-up and enables the business (KYB) onboarding endpoints. Off means personal accounts only.']
    ];
    const tree = `mobile_flutter/                      the customer app (Flutter)
  lib/app/router/app_router.dart     every screen's address (route) in one list
  lib/app/routes.dart                the route names, for example AppRoutes.cards = '/cards'
  lib/app/shell/banking_shell.dart   the tab bar / side menu around the main screens
  lib/features/<feature>/            one folder per product area: cards, money, profile, rewards ...
    presentation/                    the screens and widgets users see
    domain/                          plain data types and rules (no UI)
    application/, data/              state and API calls (present in some features)
  lib/core/l10n/                     the translation loader (app_localizations.dart)
  lib/core/api/dio_provider.dart     the one HTTP client that calls your API
  assets/l10n/<language>.json        translated text, one file per language (13 languages)
  config/<brand>/brand.json          your exported branding
admin_vue/                           the admin website (Vue 3 + PrimeVue)
  src/router/index.ts                every admin page's address
  src/views/*.vue                    one file per page (AdminCardsView.vue, AdminCustomersView.vue ...)
  src/components/                    shared building blocks, including AppShell.vue (menu)
  src/lib/apiClient.ts               the one HTTP client; it refuses any address outside your API
  src/styles.css, src/main.ts        colors and theme
backend/src/                         the API (.NET)
  NeoBanking.Api/Controllers/        one file per group of addresses: Mobile*Controller (app), Admin*Controller (admin)
  NeoBanking.Api/appsettings*.json   settings, including Company:Features
  NeoBanking.Application/UseCases/   business rules
  NeoBanking.Infrastructure/         Hoppa client, email, database (Persistence/Migrations)
scripts/                             branding tool, run and build wrappers, this guide's builder`;
    const items = [
      {title: 'Find your way around the repository', text: 'Three folders, one per program. Inside the app, each product area is a "feature" folder with its screens in presentation/.', html: `<div class="file-tree">${esc(tree)}</div>`},
      {title: 'Change the text on a screen', where: 'Laptop', text: 'The English sentence in the Dart code is also the translation key. A screen calls context.tr(\'Order a card\'). For English the key itself is shown. For every other language the app looks the key up in assets/l10n/<language>.json. All 13 JSON files must contain exactly the same keys; a test checks that.', code: `# Find where a sentence is used.\ngrep -rn "Order a card" mobile_flutter/lib mobile_flutter/assets/l10n\n\n# To change the English wording: edit the string in the .dart file, then rename the key\n# in every assets/l10n/*.json file (en.json included; its value equals the key).\n# To change only a translation: edit the value in that language's file, e.g. de.json.\n\n# Check that all languages still have the same keys and placeholders.\ncd mobile_flutter && flutter test test/core/l10n/app_localizations_test.dart`, expect: 'The grep lists the .dart file and 13 JSON lines. The test ends with "All tests passed!".', watch: 'Placeholders look like {p0} and must stay in every translation. Do not translate user data, currency codes or identifiers; only app copy belongs in the JSON files.'},
      {title: 'Add a screen and a route', where: 'Laptop', text: 'A new screen needs three edits: a widget file in the feature\'s presentation/ folder, a route name in lib/app/routes.dart, and a GoRoute entry in lib/app/router/app_router.dart. Put the GoRoute inside the ShellRoute block to show it with the tab bar, or outside for a full-screen page. To add a tab, edit lib/app/shell/banking_shell.dart.', code: `// 1. mobile_flutter/lib/features/support/presentation/faq_screen.dart\nimport 'package:flutter/material.dart';\nimport 'package:mobile_flutter/core/l10n/app_localizations.dart';\n\nclass FaqScreen extends StatelessWidget {\n  const FaqScreen({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return Scaffold(\n      appBar: AppBar(title: Text(context.tr('Frequently asked questions'))),\n      body: Center(child: Text(context.tr('Coming soon'))),\n    );\n  }\n}\n\n// 2. mobile_flutter/lib/app/routes.dart — inside AppRoutes\nstatic const faq = '/faq';\n\n// 3. mobile_flutter/lib/app/router/app_router.dart — inside the routes: [...] list\nGoRoute(\n  path: AppRoutes.faq,\n  builder: (context, state) => const FaqScreen(),\n),\n\n// Navigate from any screen:\ncontext.go(AppRoutes.faq);`, language: 'dart', expect: 'After a hot reload, context.go(AppRoutes.faq) opens the new screen. "flutter analyze" reports no issues.', watch: 'Add the two new English sentences as keys to all 13 assets/l10n/*.json files, or the localization test fails. Screens behind the login are protected by the redirect logic in app_router.dart; new routes inherit it.'},
      {title: 'Change the admin website', where: 'Laptop', text: 'Admin pages are Vue files in admin_vue/src/views. A new page needs a route in admin_vue/src/router/index.ts (with meta: adminMeta so only administrators can open it) and, to appear in the menu, an entry in admin_vue/src/components/AppShell.vue. All API calls go through admin_vue/src/lib/apiClient.ts, which only allows /api/v1/admin, /api/v1/auth and /api/v1/branding addresses.', code: `// admin_vue/src/router/index.ts — add to the routes array\n{ path: '/reports', name: 'admin-reports', component: () => import('@/views/AdminReportsView.vue'), meta: adminMeta },`, language: 'typescript', expect: 'npm run dev reloads; http://localhost:5173/reports shows your view after sign-in. "npm run typecheck" passes.', watch: 'A view that needs new data also needs a new Admin*Controller address in the API; add both, never call Hoppa from the browser.'},
      {title: 'Change the API', where: 'Laptop', text: 'Addresses for the app live in backend/src/NeoBanking.Api/Controllers/Mobile*Controller.cs, addresses for the admin in Admin*Controller.cs. New Hoppa-backed features follow the process in docs/customer-implementation-guide.md ("Adding a New Hoppa-Backed Feature"). Database changes are migrations, created with the command below and applied by --migrate-and-seed.', code: `dotnet build backend/NeoBanking.sln\ndotnet tool install --global dotnet-ef\ndotnet ef migrations add AddReportTable --project backend/src/NeoBanking.Infrastructure/NeoBanking.Infrastructure.csproj --startup-project backend/src/NeoBanking.Infrastructure/NeoBanking.Infrastructure.csproj --context NeoBankingDbContext --output-dir Persistence/Migrations`, expect: 'A new file under backend/src/NeoBanking.Infrastructure/Persistence/Migrations. The next --migrate-and-seed run applies it.', watch: 'Every server release with a new migration needs a database backup first (step 8, section 11).'},
      {title: 'Switch product features on or off', where: 'Laptop', text: 'The API decides which features exist. It reads Company:Features from its settings and the app asks for that list at start (/api/v1/mobile/config). On your laptop, put the section in appsettings.Local.json. On the server it lives in /etc/' + id + '/appsettings.Production.json, or as environment variables such as Company__Features__ReferralsEnabled=true. Restart the API after a change.', code: JSON.stringify({Company: {Features: Object.fromEntries(features.map(([key, value]) => [key, JSON.parse(value)]))}}, null, 2), language: 'json', html: `<table class="doc-table"><thead><tr><th>Key</th><th>Code default</th><th>What it switches</th></tr></thead><tbody>${features.map(([key, value, meaning]) => `<tr><td><code>${esc(key)}</code></td><td><code>${esc(value)}</code></td><td>${esc(meaning)}</td></tr>`).join('')}</tbody></table>`, expect: 'After a restart, http://localhost:5188/api/v1/mobile/config reports the new values and the app hides or shows the matching screens.', watch: 'The server overlay generated in step 8 starts with every feature set to false. Turn a feature on only when your Hoppa contact confirms the matching module is enabled for your company. Push notifications (PushNotifications:Enabled) and market data (MarketData:Enabled) are separate switches with their own credentials.'},
      {title: 'Build for release', where: 'Laptop', text: 'Release builds use the same wrappers as the laptop run, with the production JSON (its API_BASE_URL is the customer\'s HTTPS address). The full, copy-ready version with the admin and API builds is section 5 of step 8.', code: `export BRANDING_PYTHON="$PWD/.venv/bin/python"\n# Web app (PWA) for the server:\n./scripts/build-mobile-branded.sh web mobile_flutter/config/${id}/brand.json --release\n# Android app bundle for Google Play (needs release signing):\n./scripts/build-mobile-branded.sh appbundle mobile_flutter/config/${id}/brand.json --release\n# iOS archive (macOS with Xcode and signing only):\n./scripts/build-mobile-branded.sh ipa mobile_flutter/config/${id}/brand.json --release\n# Admin website:\n(cd admin_vue && VITE_BACKEND_API_BASE_URL=https://${server.apiDomain} VITE_APP_NAME=${shell(config.app.name)} npm run build)\n# API:\ndotnet publish backend/src/NeoBanking.Api/NeoBanking.Api.csproj -c Release -o artifacts/api`, expect: 'mobile_flutter/build/web/, admin_vue/dist/ and artifacts/api/ are filled. No appsettings.Production.json is inside artifacts/api.', watch: 'Native store builds need the customer\'s signing keys and store accounts (step 8, section 12). Remove appsettings*.json from the published API folder; production settings come only from the server.'}
    ];
    return `<section class="panel">${items.map(docStep).join('')}</section>`;
  }
  function serverParams() {return {...server, dbSslMode:server.dbMode==='local'?'Disable':'VerifyFull', brandId:config.app.id,appName:config.app.name,primaryColor:config.design.light.fill,supportEmail:config.app.supportEmail,legalEntity:config.app.legalEntity};}
  function currentGuide() {
    const errors=S.validate(serverParams());
    if(config.flutterDefines.API_BASE_URL !== 'https://'+server.apiDomain)errors.push('For this production server recipe, the app API URL must be https://'+server.apiDomain+'. Use step 5 (Connections) to align the public endpoint.');
    if(errors.length)return {sections:[],errors};
    try {return {sections:S.render(serverParams()),errors:[]};} catch(error) {return {sections:[],errors:[error.message]};}
  }
  function guideHTML(sections) {
    return `<nav class="step-links" aria-label="Server sections">${sections.map(section => `<a href="#guide-${esc(section.id)}">${esc(section.title)}</a>`).join('')}</nav>` + sections.map(section => `<section class="panel guide-section" id="guide-${esc(section.id)}"><h2>${esc(section.title)}</h2><p class="summary">${esc(section.summary)}</p>${section.outline?.length ? `<ol class="outline">${section.outline.map(line => `<li>${esc(line)}</li>`).join('')}</ol>` : ''}${section.steps.map(docStep).join('')}${section.terms?.length ? `<dl class="glossary">${section.terms.map(item => `<dt>${esc(item.term)}</dt><dd>${esc(item.definition)}</dd>`).join('')}</dl>` : ''}${section.links?.length ? `<div class="sources">${section.links.map(link => `<a href="${esc(link.url)}" target="_blank" rel="noopener noreferrer">${esc(link.label)} ↗</a>`).join('')}</div>` : ''}</section>`).join('');
  }
  function renderServer() {
    const guide = currentGuide();
    return `<section class="panel"><h2>How to use this section</h2><p class="lead">The instructions below are generated from the fields in the next panel. Read one numbered section at a time. Every command block carries a badge: ${whereBadge('Laptop')} means your own computer, ${whereBadge('Server')} means the customer’s Ubuntu server inside an SSH session, ${whereBadge('Database admin')} means a psql session signed in as the database administrator. Under each command, “What you should see” tells you whether it worked. Section 13 is troubleshooting and section 14 defines every term.</p></section>
    <section class="panel server-inputs"><h2>Customer infrastructure</h2><p class="lead">Target: a fresh Ubuntu 24.04 LTS installation. Build tools run on your laptop or CI; the production server runs nginx, the .NET runtime and the customer API.</p><div class="fields">
    ${serverField('apiDomain','API domain')}${serverField('appDomain','PWA domain')}${serverField('adminDomain','Admin domain')}
    ${serverField('repoUrl','Customer source repository','Use a customer-owned copy / isolated checkout.')}${serverField('dbMode','PostgreSQL location','Choose where the customer’s database runs.',[['local','On this Linux server'],['managed','Managed / separate PostgreSQL']])}
    ${serverField('dbName','Database name','Customer-specific, lowercase SQL identifier.')}${serverField('dbUser','Database role','A dedicated role for this customer.')}
    ${server.dbMode === 'managed' ? serverField('dbHost','PostgreSQL hostname','Private address preferred; certificate hostname must match.') + serverField('dbPort','PostgreSQL port') + serverField('dbRootCert','Database root CA path','Optional absolute path on the server when the provider uses a private CA.') : ''}</div>
    <div class="note">No passwords are entered here. Secret-setup commands prompt on the customer’s server. Review hostnames and the repository URL before copying commands.</div><button class="btn soft" data-action="refresh-guide">Update instructions</button></section>
    ${errorsHTML(guide.errors)}${guideHTML(guide.sections)}`;
  }
  function guideMarkdown(sections) {
    const stepMarkdown = (item, index) => `### ${index + 1}. ${item.title}\n\n` + (item.where ? `**Run on:** ${item.where} (${WHERE_HINT[item.where] || item.where})\n\n` : '') + `**What this does:** ${item.text}\n\n` + (item.code ? '```' + (item.language || 'bash') + '\n' + item.code + '\n```\n\n' : '') + (item.expect ? `**What you should see:** ${item.expect}\n\n` : '') + (item.watch ? `**Watch out:** ${item.watch}\n\n` : '');
    return '# Customer server setup — ' + config.app.name + '\n\nGenerated for a separate customer installation. Review all values before running commands.\n\nEvery command block says where it runs: **Laptop** is your own computer, **Server** is the customer’s Ubuntu server inside an SSH session, **Database admin** is a psql session signed in as the database administrator.\n\n' + sections.map(section => `## ${section.title}\n\n${section.summary}\n\n` + (section.outline?.length ? section.outline.map((line, index) => `${index + 1}. ${line}`).join('\n') + '\n\n' : '') + section.steps.map(stepMarkdown).join('') + (section.terms?.length ? section.terms.map(item => `- **${item.term}** — ${item.definition}`).join('\n') + '\n\n' : '') + (section.links || []).map(link => `[${link.label}](${link.url})`).join(' · ') + '\n\n').join('');
  }
  function checklist() {
    const report = validation(); const missing = referencedAssets().filter(path => !assets.has(path)); const examples = referencedAssets().filter(path => assets.get(path)?.example);
    const ownIdentity = !config.native.androidApplicationId.startsWith('com.example.') && !config.native.iosBundleId.startsWith('com.example.');
    const realDomain = !/example\.(com|org|net)/i.test(config.flutterDefines.API_BASE_URL || '') && /^https:\/\//.test(config.flutterDefines.API_BASE_URL || '');
    return {report,missing,examples,rows:[
      [report.valid,'Config fields match the supported schema',report.valid ? 'Run the real validator after unpacking to check all source files.' : `${report.errors.length} field issue(s) need attention.`],
      [!missing.length,'Referenced files included',missing.length ? missing.join(', ') : `${referencedAssets().length} referenced files are available for the bundle.`],
      [!examples.length,'Customer artwork selected',examples.length ? 'Some artwork is still the included example. Replace it before a customer release.' : 'No included example artwork remains in the config.'],
      [ownIdentity,'Customer application IDs confirmed',ownIdentity ? 'Reconfirm ownership and store registrations with your release team.' : 'Replace com.example identifiers before registering native apps.'],
      [realDomain,'Customer HTTPS API selected',realDomain ? config.flutterDefines.API_BASE_URL : 'Replace the example API with the customer’s reachable HTTPS endpoint.'],
      [config.flutterDefines.APP_FLAVOR === 'prod','Production build selected',`Current mode: ${config.flutterDefines.APP_FLAVOR}`]
    ]};
  }
  function renderReview() {
    const review = checklist(); const guide = currentGuide();
    return `<section class="panel"><h2>Handoff checklist</h2><ul class="review-list">${review.rows.map(([ok,title,text]) => `<li><span class="indicator ${ok ? '' : 'warn'}">${ok ? '✓' : '!'}</span><div><strong>${esc(title)}</strong><div class="hint">${esc(text)}</div></div></li>`).join('')}</ul></section>
    ${errorsHTML(review.report.errors)}
    <section class="panel download-card"><h2>Download your app configuration</h2><p class="lead">The JSON is the actual app configuration. The bundle adds your source assets and the setup guide so your implementation team has everything in one place.</p><div class="actions"><button class="btn primary" data-action="download-config" ${!review.report.valid ? 'disabled' : ''}>Download config JSON ↓</button><button class="btn" data-action="download-bundle" ${!review.report.valid || review.missing.length || guide.errors.length ? 'disabled' : ''}>Download handoff ZIP ↓</button></div>
    <p class="hint" style="margin-top:12px">ZIP requires every referenced file and valid server fields. ${review.missing.length ? 'Add the missing files in steps 3–5.' : ''} ${guide.errors.length ? 'Fix the server details in step 8.' : ''}</p><div class="file-tree">config/\n  brand.json\n  assets/…\n  private/…  (optional Firebase client files)\nREADME.md\nserver-setup.md\nonboarding-settings.json  (public domains and database location)</div>
    <div class="actions"><button class="btn small-btn" data-action="copy-config" ${!review.report.valid ? 'disabled' : ''}>Copy JSON</button><button class="btn small-btn" data-action="download-guide" ${guide.errors.length ? 'disabled' : ''}>Download server guide</button></div></section>
    <section class="panel"><h2>Build & validate</h2><p class="lead">Extract the ZIP’s <code>config</code> folder into your separate customer checkout as <code>mobile_flutter/config/${esc(config.app.id)}/</code>. Run these commands from that checkout’s root.</p>${codeBlock(buildCommands(), 'Laptop')}<ul class="inline-list"><li>Always use the branded build wrappers. A plain <code>flutter run</code> does not load this JSON automatically.</li><li>Changing branding means rebuilding and redeploying. Build each customer in a separate clone or worktree.</li><li>Check the actual app in light and dark appearances on a real device. Include launch, login, cards, payments and error states in acceptance testing.</li><li>Keep non-design bug fixes in separate upstream commits, cherry-pick them into the customer checkout and validate there before deployment.</li></ul></section>
    <section class="panel advanced"><h2>Full configuration</h2><p class="lead">All supported tokens, fonts, client Firebase paths and additional non-secret defines are preserved. Use this editor for settings beyond the form.</p><details><summary>Edit or inspect JSON</summary><textarea class="json-editor" id="json-editor" aria-label="Complete branding JSON" spellcheck="false">${esc(JSON.stringify(config,null,2))}</textarea><div class="actions" style="margin-top:12px"><button class="btn soft" data-action="apply-json">Apply JSON edits</button><button class="btn" data-action="restore-json-editor">Restore current config</button></div><div id="json-errors" style="margin-top:12px"></div></details></section>
    ${review.report.warnings.length ? `<section class="panel"><h3>Items to review</h3><ul class="inline-list">${review.report.warnings.map(warning => `<li>${esc(warning.path ? warning.path + ': ' + warning.message : warning.message || warning)}</li>`).join('')}</ul></section>` : ''}`;
  }
  function buildCommands() {
    const brand = `mobile_flutter/config/${config.app.id}/brand.json`;
    return `python3 -m venv .venv\n.venv/bin/pip install -r scripts/branding/requirements.txt\nexport BRANDING_PYTHON="$PWD/.venv/bin/python"\n\n# Validate configuration, files and platform identities.\n"$BRANDING_PYTHON" scripts/prepare-mobile-brand.py ${shell(brand)} --check\n\n# Preview the app locally.\n./scripts/run-mobile-branded.sh ${shell(brand)} -d chrome\n\n# Build the web app.\n./scripts/build-mobile-branded.sh web ${shell(brand)} --release\n\n# Native examples; configure customer signing before store release.\n./scripts/build-mobile-branded.sh appbundle ${shell(brand)} --release\n# On macOS with Xcode and customer signing:\n./scripts/build-mobile-branded.sh ipa ${shell(brand)} --release`;
  }
  function shell(text) {return "'" + String(text).replace(/'/g, "'\\''") + "'";}
  function readme() {
    const id = config.app.id;
    return `# ${config.app.name} — customer handoff

This package contains the public app branding, the generated server guide and the public server choices. It is not a live deployment and it contains no secrets.

## What is in this package

- config/brand.json — the app configuration (schema version 1) with every color, font and identifier.
- config/assets/ and config/private/ — the artwork, fonts, font licenses and optional public Firebase client files that brand.json refers to.
- server-setup.md — the step-by-step Ubuntu, PostgreSQL, nginx and HTTPS guide. Every command block says where it runs: Laptop, Server or Database admin.
- onboarding-settings.json — the public domains and database choices, so the wizard can be reopened later.

## What you are building

Three programs that all talk to the Hoppa platform through your own API:

1. The customer app (${config.app.name}) for Android, iOS and the browser, built with Flutter from mobile_flutter/.
2. The admin website for the customer's staff, built with Vue from admin_vue/.
3. The API, built with .NET from backend/. It owns the PostgreSQL database and is the only program that holds the Hoppa API key.

All three run on one Ubuntu 24.04 server behind nginx with HTTPS.

## Quick start in 10 steps

1. Gather the prerequisites: from Hoppa the platform base URL, your company API key, the webhook signing secrets and the list of enabled features; from the customer three domain names, an Ubuntu 24.04 server, a SendGrid account and (for native apps) Google Play and Apple developer accounts; on your laptop the .NET 10 SDK, Node.js 24, Flutter 3.44, Python 3.10+ and Git.
2. On your laptop, clone the customer repository: git clone ${server.repoUrl}
3. Copy this package's config/ folder to mobile_flutter/config/${id}/ inside that checkout, so the JSON lives at mobile_flutter/config/${id}/brand.json.
4. Install the branding tool and validate the configuration with the "App build" commands below (the --check line changes no files).
5. Install PostgreSQL 16 locally (or start one Docker container) and create a development database and role.
6. Create backend/src/NeoBanking.Api/appsettings.Local.json with the connection string, a Jwt:SigningKey of at least 32 characters, the Hoppa values and "Email": {"Provider": "log"}. Run the migration once: SeedAdmin__Email=... SeedAdmin__Password=... dotnet run --project backend/src/NeoBanking.Api/NeoBanking.Api.csproj -- --migrate-and-seed. Then start the API with dotnet run --project backend/src/NeoBanking.Api/NeoBanking.Api.csproj (it listens on http://localhost:5188).
7. Start the admin website: cd admin_vue && npm install && VITE_BACKEND_API_BASE_URL=http://localhost:5188 npm run dev, then sign in at http://localhost:5173/login with the seeded administrator.
8. Run the app in Chrome: ./scripts/run-mobile-branded.sh mobile_flutter/config/${id}/brand.json -d chrome --dart-define=API_BASE_URL=http://localhost:5188
9. Customize text (assets/l10n/*.json), screens (mobile_flutter/lib/features/<feature>/presentation), routes (mobile_flutter/lib/app/router/app_router.dart) and features (Company:Features in the API settings). Commit your work.
10. Follow server-setup.md section by section on the customer's server, then run its acceptance checks (section 9) before the customer goes live.

The interactive guide (customer-onboarding.html) explains steps 5–9 with "what you should see" after every command.

## App build

Run from the repository root of the customer checkout.

\`\`\`bash
${buildCommands()}
\`\`\`

## Review before release

- Confirm customer name, application IDs, domains and artwork.
- Check light/dark, launch/loading, authentication and main account/card/payment flows on real devices.
- Configure native signing, stores, APNs/Firebase and provider onboarding separately where used.
- Keep database credentials, JWT signing keys and provider secrets on the customer server only.
- Mobile brand.json does not restyle every admin screen or provider-hosted flow.
- Use the current repository validator (prepare-mobile-brand.py --check) as the final authority.

## Reopening the wizard

Open the same guide and choose Import ZIP / JSON, then select this original handoff ZIP. The guide restores the config, artwork, fonts and licenses, optional Firebase client files, and public server choices together after validating the bundle. No files are uploaded. Keep the original ZIP unchanged; ZIPs recompressed by other tools are not supported. You can also import config/brand.json alone, but JSON does not include asset bytes or server choices, so referenced files must be selected again.
`;
  }
  function jsonOutput() {return JSON.stringify(E.buildConfig(config),null,2) + '\n';}
  function download(bytes, filename, mime) {
    const blob = bytes instanceof Blob ? bytes : new Blob([bytes],{type:mime});
    const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();setTimeout(() => URL.revokeObjectURL(url),60000);
  }
  async function copyText(text) {
    try {await navigator.clipboard.writeText(text);} catch {const area=document.createElement('textarea');area.value=text;area.style.position='fixed';area.style.opacity='0';document.body.append(area);area.select();const ok=document.execCommand('copy');area.remove();if(!ok) throw new Error('Clipboard access is unavailable. Select and copy the text manually.');}
    toast('Copied to clipboard.');
  }
  function bundleEntries() {
    const review = checklist(); const guide = currentGuide();
    if (!review.report.valid || review.missing.length || guide.errors.length) throw new Error('Complete the required config, source files and server details before exporting the bundle.');
    const names = new Set(referencedAssets());
    for (const [path,item] of assets) if (item.license) names.add(path);
    return [{name:'config/brand.json',bytes:jsonOutput()},...Array.from(names).map(path => ({name:'config/'+path,bytes:F.base64ToBytes(assets.get(path).data)})),
      {name:'README.md',bytes:readme()},{name:'server-setup.md',bytes:guideMarkdown(guide.sections)},
      {name:'onboarding-settings.json',bytes:JSON.stringify(serverParams(),null,2)+'\n'}];
  }
  function syncImportedConfig() {
    try {const url=new URL(config.flutterDefines.API_BASE_URL);server.apiDomain=url.hostname;} catch {}
    server.dbName=config.app.id.replace(/-/g,'_');server.dbUser=server.dbName+'_app';
  }
  function applyImported(value) {
    const report=E.validateConfig(value);
    if (!report.valid) return report;
    bundleImportSequence++;
    config=E.init(value);lastImport=config.app.name;syncImportedConfig();render();toast('Config imported. Add any referenced files that are not included yet.');return report;
  }
  // BEGIN BUNDLE IMPORT: staged helpers have no UI mutations until applyImportedBundle commits.
  let bundleImportSequence=0;
  const serverImportKeys=['apiDomain','appDomain','adminDomain','dbMode','dbHost','dbPort','dbName','dbUser','dbSslMode','dbRootCert','repoUrl'];
  function importFailure(report) {return report.errors.slice(0,5).map(item=>item.path+': '+item.message).join(' · ');}
  function jsonFromBytes(bytes,label,max=2*1024*1024) {
    if(bytes.byteLength>max)throw new Error(label+' exceeds its size limit.');
    try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}
    catch{throw new Error(label+' must contain valid UTF-8 JSON.');}
  }
  function rejectServerSecrets(value) {
    const pending=[value];
    while(pending.length){const item=pending.pop();if(!item||typeof item!=='object')continue;
      if(item.type==='service_account')throw new Error('Server service-account credentials cannot be imported into the app guide.');
      for(const [key,entry] of Object.entries(item)){
        if(/(?:PRIVATE[_-]?KEY|CLIENT[_-]?SECRET|PASSWORD|SIGNING[_-]?KEY|CONNECTION[_-]?STRING|ACCESS[_-]?TOKEN)/i.test(key)
          ||(typeof entry==='string'&&/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(entry)))throw new Error('Server credentials cannot be imported into the app guide ('+key+').');
        if(entry&&typeof entry==='object')pending.push(entry);
      }
    }
  }
  function firebaseMetadata(bytes,platform) {
    if(bytes.byteLength>1024*1024)throw new Error('Firebase client files must be no larger than 1 MiB.');
    let parsed;
    if(platform==='android')parsed=jsonFromBytes(bytes,'Firebase Android client JSON',1024*1024);
    else{
      const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
      const xml=new DOMParser().parseFromString(text,'application/xml');
      if(xml.querySelector('parsererror'))throw new Error('Choose a valid XML GoogleService-Info.plist file. Binary plists must be converted to XML first.');
      const dict=xml.querySelector('plist > dict');if(!dict)throw new Error('The plist must contain a Firebase client dictionary.');
      parsed={};const nodes=[...dict.children];
      for(let i=0;i<nodes.length-1;i++)if(nodes[i].tagName==='key'){const key=nodes[i].textContent;const val=nodes[++i];if(val.tagName==='string'||val.tagName==='integer')Object.defineProperty(parsed,key,{value:val.textContent,enumerable:true});}
    }
    if(!parsed||typeof parsed!=='object'||Array.isArray(parsed))throw new Error('Firebase client configuration must contain an object.');
    rejectServerSecrets(parsed);return {valid:true,data:parsed};
  }
  function importedServerSettings(input,nextConfig) {
    if(!input||typeof input!=='object'||Array.isArray(input))throw new Error('onboarding-settings.json must contain public server settings.');
    const derived={brandId:nextConfig.app.id,appName:nextConfig.app.name,primaryColor:nextConfig.design.light.fill,supportEmail:nextConfig.app.supportEmail,legalEntity:nextConfig.app.legalEntity};
    const allowed=new Set([...serverImportKeys,...Object.keys(derived)]);
    for(const key of Object.keys(input))if(!allowed.has(key))throw new Error('Unsupported server setting '+key+'. Only public fields from this guide can be imported.');
    const next={};
    for(const key of serverImportKeys){const value=input[key];if(typeof value!=='string'&&!(key==='dbPort'&&typeof value==='number'))throw new Error('Missing or invalid public server field: '+key);next[key]=String(value);}
    for(const [key,value] of Object.entries(derived))if(input[key]!==value)throw new Error('The bundle server setting '+key+' does not match config/brand.json.');
    const errors=S.validate({...next,...derived});
    if(nextConfig.flutterDefines.API_BASE_URL!=='https://'+next.apiDomain)errors.push('The app API URL must match the saved API domain exactly.');
    if(errors.length)throw new Error(errors.slice(0,5).join(' · '));
    return next;
  }
  async function prepareImportedBundle(bytes) {
    const entries=new Map(F.readZip(bytes).map(entry=>[entry.name,entry.bytes]));
    if(!entries.has('config/brand.json')||!entries.has('onboarding-settings.json'))throw new Error('Choose the original handoff ZIP containing config/brand.json and onboarding-settings.json.');
    const value=jsonFromBytes(entries.get('config/brand.json'),'config/brand.json');
    rejectServerSecrets(value);
    const initial=E.validateConfig(value);if(!initial.valid)throw new Error(importFailure(initial));
    const nextConfig=E.init(value);
    const nextServer=importedServerSettings(jsonFromBytes(entries.get('onboarding-settings.json'),'onboarding-settings.json'),nextConfig);
    const required=new Map(initial.assets.map(item=>[item.path,item]));
    const nextAssets=new Map(),faces=[];
    for(const path of required.keys())if(!entries.has('config/'+path))throw new Error('The bundle is missing its referenced file: '+path);
    for(const [name,content] of entries){
      if(['config/brand.json','onboarding-settings.json','README.md','server-setup.md'].includes(name))continue;
      if(!name.startsWith('config/'))throw new Error('Unexpected file in handoff ZIP: '+name);
      const path=name.slice(7),reference=required.get(path);
      if(!reference){
        if(!/^assets\/.+\.txt$/i.test(path)||content.byteLength>1024*1024)throw new Error('Unexpected or oversized asset in handoff ZIP: '+path);
        const license=new TextDecoder('utf-8',{fatal:true}).decode(content);
        if(/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(license))throw new Error('A font license file contains a private key.');
        nextAssets.set(path,{data:F.bytesToBase64(content),mime:'text/plain',license:true,metadata:{valid:true}});continue;
      }
      if(content.byteLength>25*1024*1024)throw new Error('Asset exceeds the 25 MiB file limit: '+path);
      let mime,meta;
      if(reference.kind==='image'){
        const extension=path.split('.').at(-1).toLowerCase();mime={png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg',webp:'image/webp',gif:'image/gif'}[extension];
        const magic=Array.from(content.subarray(0,12)),ascii=(start,end)=>String.fromCharCode(...content.subarray(start,end));
        const signature=extension==='png'?magic.slice(0,8).join(',')==='137,80,78,71,13,10,26,10':extension==='gif'?['GIF87a','GIF89a'].includes(ascii(0,6)):extension==='webp'?ascii(0,4)==='RIFF'&&ascii(8,12)==='WEBP':magic[0]===255&&magic[1]===216&&magic[2]===255;
        if(!signature)throw new Error('Image contents do not match their file extension: '+path);
        const bitmap=await createImageBitmap(new Blob([content],{type:mime}));
        try{if(!bitmap.width||!bitmap.height||bitmap.width>8192||bitmap.height>8192)throw new Error('Images must be at most 8192 pixels per dimension: '+path);meta={valid:true,width:bitmap.width,height:bitmap.height};}finally{bitmap.close();}
      }else if(reference.kind==='font'){
        mime='application/octet-stream';
        for(const font of nextConfig.fonts)for(const file of font.files)if(file.path===path){const face=new FontFace(font.family,content.buffer,{weight:String(file.weight),style:file.style});await face.load();faces.push(face);}
        meta={valid:true};
      }else{
        const platform=reference.field.endsWith('.android')?'android':'ios';mime=platform==='android'?'application/json':'application/xml';meta=firebaseMetadata(content,platform);
      }
      const encoded=F.bytesToBase64(content);
      const example=data.assets.some(item=>item.example&&item.data===encoded);
      nextAssets.set(path,{data:encoded,mime,metadata:meta,...(example?{example:true}:{})});
    }
    const report=E.validateConfig(nextConfig,new Map([...nextAssets].map(([path,item])=>[path,item.metadata])));
    if(!report.valid)throw new Error(importFailure(report));
    return {config:nextConfig,server:nextServer,assets:nextAssets,faces};
  }
  async function applyImportedBundle(bytes) {
    const sequence=++bundleImportSequence;
    const prepared=await prepareImportedBundle(bytes);
    if(sequence!==bundleImportSequence)return;
    const added=[];
    try{for(const face of prepared.faces){document.fonts.add(face);added.push(face);}}
    catch(error){for(const face of added)document.fonts.delete(face);throw error;}
    config=prepared.config;lastImport=config.app.name;Object.assign(server,prepared.server);assets.clear();
    for(const [path,item] of prepared.assets)assets.set(path,item);
    render();toast('Handoff restored: config, artwork, fonts, Firebase client files and public server choices.');
  }
  // END BUNDLE IMPORT
  async function fileBytes(file,max=25*1024*1024) {if(file.size>max)throw new Error('This file is too large. The limit is '+Math.round(max/(1024*1024))+' MiB.');return new Uint8Array(await file.arrayBuffer());}
  async function uploadImage(file,path) {
    if (!/\.(png|jpe?g|webp|gif)$/i.test(file.name)) throw new Error('Use PNG, JPEG, WebP or GIF. Export SVG to PNG first.');
    await fileBytes(file);
    const bitmap=await createImageBitmap(file);try {
      if(!bitmap.width||!bitmap.height||bitmap.width>8192||bitmap.height>8192)throw new Error('Images must be at most 8192 pixels per dimension.');
      const canvas=document.createElement('canvas');canvas.width=bitmap.width;canvas.height=bitmap.height;canvas.getContext('2d').drawImage(bitmap,0,0);
      const png=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));if(!png)throw new Error('The image could not be converted to PNG.');
      const name=F.safeAssetName(file.name).replace(/\.[^.]+$/,'.png');const role=path.split('.').at(-1);
      const relative=`assets/${role}-${name}`;
      assets.set(relative,{data:F.bytesToBase64(new Uint8Array(await png.arrayBuffer())),mime:'image/png',metadata:{valid:true,width:bitmap.width,height:bitmap.height}});
      const previous=get(path);put(path,relative);
      // If a shared logo was deliberately reused, keep its dependants together.
      if(path==='design.assets.logo')for(const [other] of assetFields)if(other!==path&&get(other)===previous)put(other,relative);
      render();toast('Artwork added. Your bundle will include the PNG source.');
    } finally {bitmap.close();}
  }
  async function uploadFont(file,index,weightIndex) {
    if(!/\.(ttf|otf)$/i.test(file.name))throw new Error('Use a TrueType (.ttf) or OpenType (.otf) font.');
    const bytes=await fileBytes(file);const path=`assets/font-${index}-${weightIndex}-`+F.safeAssetName(file.name);
    const family=config.fonts[index].family || 'Customer Sans';
    const face=new FontFace(family,bytes.buffer,{weight:String(config.fonts[index].files[weightIndex].weight),style:config.fonts[index].files[weightIndex].style});
    await face.load();document.fonts.add(face);
    assets.set(path,{data:F.bytesToBase64(bytes),mime:'application/octet-stream',metadata:{valid:true}});config.fonts[index].files[weightIndex].path=path;render();toast('Font included and loaded for preview.');
  }
  async function uploadFirebase(file,platform) {
    const bytes=await fileBytes(file,1024*1024);const meta=firebaseMetadata(bytes,platform);
    const path='private/'+(platform==='android'?'google-services.json':'GoogleService-Info.plist');
    assets.set(path,{data:F.bytesToBase64(bytes),mime:platform==='android'?'application/json':'application/xml',metadata:meta});config.native.firebase[platform]=path;render();toast('Client Firebase file included. The build validator checks project and application IDs.');
  }
  const actions = {
    import:()=> $('import-file').click(),
    'generate-palette':()=>{const p=config.design[previewMode];config.design[previewMode]=E.makePalette({primary:p.fill,accent:p.accent,paper:p.paper,surface:p.surface,text:p.ink},previewMode);render();toast(`Matching ${previewMode} tokens generated.`);},
    'add-font':()=>{config.fonts.push({family:'Customer Sans',files:[{path:'assets/customer-sans-regular.ttf',weight:400,style:'normal'}]});render();},
    'reuse-logo':()=>{for(const [path] of assetFields)put(path,config.design.assets.logo);render();toast('Main logo is used for every artwork slot.');},
    'disable-firebase':()=>{config.native.firebase={};render();toast('Client push configuration cleared.');},
    'refresh-guide':()=>{render();toast('Instructions updated from your server details.');},
    'download-config':()=>{if(!validation().valid)throw new Error('Fix the config fields before downloading.');download(jsonOutput(),'brand.json','application/json');toast('Config JSON downloaded. Keep its referenced source files together.');},
    'copy-config':()=>copyText(jsonOutput()),
    'download-bundle':()=>{download(F.makeZip(bundleEntries()),config.app.id+'-handoff.zip','application/zip');toast('Handoff bundle downloaded.');},
    'download-guide':()=>{const guide=currentGuide();if(guide.errors.length)throw new Error('Check the server fields first.');download(guideMarkdown(guide.sections),'server-setup.md','text/markdown');},
    'apply-json':()=>{try{const value=JSON.parse($('json-editor').value);const report=applyImported(value);if(!report.valid)$('json-errors').innerHTML=errorsHTML(report.errors);}catch(error){$('json-errors').innerHTML=errorsHTML([error.message]);}},
    'restore-json-editor':()=>{$('json-editor').value=JSON.stringify(config,null,2);$('json-errors').innerHTML='';}
  };
  async function handle(work) {try{await work();}catch(error){toast(error.message || 'Please check your input and try again.');}}
  function bind() {
    $('step-content').querySelectorAll('[data-field]').forEach(input=>{
      input.addEventListener('input',()=>{
        const path=input.dataset.field;let value=input.type==='checkbox'?input.checked:input.type==='number'?Number(input.value):input.value;
        if(input.type==='number'&&input.value==='')return;
        if(path.startsWith('native.firebase.')&&!value)delete config.native.firebase[path.split('.').at(-1)];else put(path,value);
        if(path==='flutterDefines.API_BASE_URL'){try{server.apiDomain=new URL(value).hostname;}catch{}}
        renderPreview();
        document.querySelectorAll(`[data-field="${path}"]`).forEach(other=>{if(other!==input)other.value=value;});
        document.querySelectorAll(`[data-color="${path}"]`).forEach(other=>{if(/^#[\da-f]{6}([\da-f]{2})?$/i.test(value))other.value='#'+value.slice(-6);});
      });
      input.addEventListener('change',()=>{if(input.tagName==='SELECT'||input.type==='checkbox')render();});
    });
    $('step-content').querySelectorAll('[data-color]').forEach(input=>input.oninput=()=>{const path=input.dataset.color;put(path,input.value.toUpperCase());document.querySelectorAll(`[data-field="${path}"]`).forEach(other=>other.value=get(path));renderPreview();});
    $('step-content').querySelectorAll('[data-server]').forEach(input=>input.onchange=()=>{server[input.dataset.server]=input.value.trim();if(input.dataset.server==='apiDomain'){config.flutterDefines.API_BASE_URL='https://'+server.apiDomain;document.querySelectorAll('[data-field="flutterDefines.API_BASE_URL"]').forEach(other=>other.value=config.flutterDefines.API_BASE_URL);}if(input.dataset.server==='dbMode'){server.dbHost=server.dbMode==='local'?'127.0.0.1':'db.example.com';server.dbPort='5432';render();}});
    $('step-content').querySelectorAll('[data-action]').forEach(button=>button.onclick=()=>handle(actions[button.dataset.action]));
    $('step-content').querySelectorAll('[data-preset]').forEach(button=>button.onclick=()=>{const design=data.configs[button.dataset.preset].design;config.design.light=clone(design.light);config.design.dark=clone(design.dark);config.design.splash.backgroundLight=design.splash.backgroundLight;config.design.splash.backgroundDark=design.splash.backgroundDark;render();toast('Both palettes updated. Identity and artwork are unchanged.');});
    $('step-content').querySelectorAll('[data-mode]').forEach(button=>button.onclick=()=>{previewMode=button.dataset.mode;render();});
    $('step-content').querySelectorAll('[data-asset]').forEach(input=>input.onchange=()=>input.files[0]&&handle(()=>uploadImage(input.files[0],input.dataset.asset)));
    $('step-content').querySelectorAll('[data-use-logo]').forEach(button=>button.onclick=()=>{const path=button.dataset.useLogo;put(path,path==='native.icon'?config.design.assets.logo:'');render();});
    $('step-content').querySelectorAll('[data-remove-font]').forEach(button=>button.onclick=()=>{config.fonts.splice(Number(button.dataset.removeFont),1);render();});
    $('step-content').querySelectorAll('[data-add-weight]').forEach(button=>button.onclick=()=>{config.fonts[Number(button.dataset.addWeight)].files.push({path:'assets/customer-sans-bold.ttf',weight:700,style:'normal'});render();});
    $('step-content').querySelectorAll('[data-font-upload]').forEach(input=>input.onchange=()=>{if(input.files[0])handle(()=>uploadFont(input.files[0],...input.dataset.fontUpload.split(':').map(Number)));});
    $('step-content').querySelectorAll('[data-firebase]').forEach(input=>input.onchange=()=>input.files[0]&&handle(()=>uploadFirebase(input.files[0],input.dataset.firebase)));
    $('step-content').querySelectorAll('[data-copy-code]').forEach(button=>button.onclick=()=>handle(()=>copyText(button.nextElementSibling.textContent)));
    if($('font-license'))$('font-license').onchange=()=>handle(async()=>{const file=$('font-license').files[0];if(!file)return;const bytes=await fileBytes(file,1024*1024);let path='assets/'+F.safeAssetName(file.name),n=1;while(assets.has(path))path='assets/license-'+(n++)+'-'+F.safeAssetName(file.name);assets.set(path,{data:F.bytesToBase64(bytes),mime:'text/plain',license:true,metadata:{valid:true}});toast('Font license added to your handoff bundle.');});
  }
  function render() {
    fieldCounter=0;
    $('import-notice').hidden=!lastImport;
    $('import-notice').textContent=lastImport ? 'Imported '+lastImport+'. Both light and dark palettes are loaded. The preview is showing '+previewMode+'; use Light / Dark to inspect each appearance.' : '';
    $('steps').innerHTML=steps.map((item,i)=>`<button data-step="${i}" ${step===i?'aria-current="step"':''}><span class="step-num">${i+1}</span>${item.short}</button>`).join('');
    $('steps').querySelectorAll('button').forEach(button=>button.onclick=()=>go(Number(button.dataset.step)));
    $('step-eyebrow').textContent=`Step ${step+1} of ${steps.length}`;$('step-title').textContent=steps[step].title;$('step-description').textContent=steps[step].description;
    $('step-position').textContent=`${step+1} / ${steps.length}`;$('back').disabled=step===0;$('next').hidden=step===steps.length-1;
    const brandStep=steps[step].kind==='brand';
    $('work-grid').classList.toggle('wide',!brandStep);$('preview').hidden=!brandStep;
    $('open-preview-top').hidden=!brandStep;
    $('open-preview-top').onclick=expandPreview;
    $('step-content').innerHTML=[renderStart,renderBasics,renderColors,renderAssets,renderConnections,renderLaptop,renderCustomize,renderServer,renderReview][step]();
    if(brandStep)renderPreview();bind();
  }
  function go(next) {step=Math.max(0,Math.min(steps.length-1,next));render();window.scrollTo({top:0,behavior:'instant'});$('step-title').setAttribute('tabindex','-1');$('step-title').focus({preventScroll:true});}
  $('back').onclick=()=>go(step-1);$('next').onclick=()=>go(step+1);$('sidebar-import').onclick=()=> $('import-file').click();
  $('import-file').onchange=()=>handle(async()=>{const input=$('import-file'),file=input.files[0];if(!file)return;try{if(/\.zip$/i.test(file.name)){await applyImportedBundle(await fileBytes(file,100*1024*1024));}else{const value=jsonFromBytes(await fileBytes(file,2*1024*1024),'Config JSON');const report=applyImported(value);if(!report.valid)throw new Error(importFailure(report));}}finally{input.value='';}});
  for(const item of data.assets)assets.set(item.path,{...item,metadata:{valid:true}});
  render();
  // Read real image dimensions locally; the Python generator remains authoritative.
  Promise.all([...assets].map(async([path,item])=>{const image=await createImageBitmap(new Blob([F.base64ToBytes(item.data)],{type:item.mime}));item.metadata={valid:true,width:image.width,height:image.height};image.close();})).catch(()=>{});
})();
