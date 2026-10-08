/* Offline customer guide engine. Keep schema behavior aligned with prepare-mobile-brand.py. */
(function (scope) {
  'use strict';

  const PALETTE_KEYS = ('paper surface surfaceSubtle surfaceHigh navigation navigationGlass rail glassTop glassBottom ink textSecondary textTertiary border borderSubtle borderEmphasis controlEdge fill accent success danger warning teal shadowAmbient shadowLift skeletonBase skeletonHighlight sheenPeak onFill cardStart cardEnd cardMiddle cardForeground cardDecoration cardOverlay onAccent snackbar atmospherePrimary atmosphereMid atmosphereSecondary loader heroStart heroEnd mutedStart mutedEnd').split(' ');
  const OPTIONAL_PALETTE_KEYS = ('onAccent snackbar atmospherePrimary atmosphereMid atmosphereSecondary loader cardMiddle cardForeground cardDecoration cardOverlay').split(' ');
  const REQUIRED_PALETTE_KEYS = PALETTE_KEYS.filter(key => !OPTIONAL_PALETTE_KEYS.includes(key));
  const RESERVED_DEFINES = new Set(('APP_NAME APP_BRAND_ID APP_THEME_MODE APP_DESIGN_JSON APP_FONT_FAMILY APP_LOGO_ASSET APP_PRIMARY_COLOR APP_ACCENT_COLOR APP_LOGIN_BACKGROUND_COLOR APP_RADIUS_SCALE SUPPORT_EMAIL SUPPORT_PHONE LEGAL_ENTITY ACCOUNT_TRANSFER_DASHBOARD_URL').split(' '));
  const COLOR = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})(?![\s\S])/;
  const has = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
  const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);

  function clone(value, seen = new Map()) {
    if (value === null || typeof value !== 'object') return value;
    if (seen.has(value)) return seen.get(value);
    const result = Array.isArray(value) ? [] : {};
    seen.set(value, result);
    for (const key of Object.keys(value)) {
      Object.defineProperty(result, key, {value: clone(value[key], seen), writable: true, enumerable: true, configurable: true});
    }
    return result;
  }

  // Only add defaults provided by the actual generator. Never coerce invalid input,
  // replace imported palettes, discard unknown keys, or erase advanced settings.
  function buildConfig(state) {
    const config = clone(state);
    if (!isObject(config)) return config;
    const defaults = (target, values) => {
      if (isObject(target)) for (const [key, value] of Object.entries(values)) if (!has(target, key)) target[key] = clone(value);
    };
    defaults(config.app, {description: '', supportEmail: '', supportPhone: '', legalEntity: '', themeMode: 'system', transferDashboardUrl: ''});
    if (isObject(config.design)) {
      const design = config.design;
      defaults(design, {layout: 'example', typography: {}, shape: {}, assets: {}, loader: {}, splash: {}, motion: {}});
      defaults(design.typography, {fontFamily: '', monoFontFamily: '', scale: 1});
      defaults(design.shape, {radiusScale: 1});
      defaults(design.loader, {style: 'logo', durationMs: 1200});
      defaults(design.splash, {enabled: true, backgroundLight: design.light?.paper, backgroundDark: design.dark?.paper, minimumDurationMs: 700, maximumDurationMs: 12000});
      defaults(design.motion, {enabled: true, durationScale: 1});
    }
    defaults(config.native, {iconBackground: config.design?.light?.fill, firebase: {}});
    defaults(config, {fonts: [], flutterDefines: {}});
    if (Array.isArray(config.fonts)) for (const font of config.fonts) {
      if (isObject(font) && Array.isArray(font.files)) for (const file of font.files) defaults(file, {weight: 400, style: 'normal'});
    }
    return config;
  }

  function rgba(value) {
    if (typeof value !== 'string' || !COLOR.test(value)) throw new TypeError('Expected #RRGGBB or #AARRGGBB color.');
    const hex = value.slice(1);
    const rgb = hex.slice(-6);
    return [parseInt(rgb.slice(0, 2), 16), parseInt(rgb.slice(2, 4), 16), parseInt(rgb.slice(4, 6), 16), hex.length === 8 ? parseInt(hex.slice(0, 2), 16) / 255 : 1];
  }

  function composite(foreground, background) {
    const a = foreground[3];
    return [0, 1, 2].map(i => foreground[i] * a + background[i] * (1 - a)).concat(1);
  }

  function luminance(channels) {
    const rgb = channels.slice(0, 3).map(v => {
      const s = v / 255;
      return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
    });
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
  }

  // Accept contrast('#fff...', '#000...'), [foreground, background], or
  // {foreground, background, canvas}. Eight-digit values use Flutter ARGB order.
  function contrast(colors, background, canvas = '#FFFFFF') {
    let foreground = colors;
    if (Array.isArray(colors)) [foreground, background, canvas = '#FFFFFF'] = colors;
    else if (isObject(colors)) ({foreground, background, canvas = '#FFFFFF'} = colors);
    const base = composite(rgba(canvas), [255, 255, 255, 1]);
    const bg = composite(rgba(background), base);
    const fg = composite(rgba(foreground), bg);
    const l1 = luminance(fg), l2 = luminance(bg);
    return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  }

  function toHex(rgb) {
    return '#' + rgb.slice(0, 3).map(v => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, '0')).join('').toUpperCase();
  }

  function mix(first, second, amount) {
    const a = rgba(first), b = rgba(second);
    return toHex(a.map((value, i) => value * (1 - amount) + b[i] * amount));
  }

  function readable(background) {
    return contrast('#000000', background) >= contrast('#FFFFFF', background) ? '#000000' : '#FFFFFF';
  }

  function ensureContrast(foreground, background, minimum = 4.5) {
    if (contrast(foreground, background) >= minimum) return toHex(rgba(foreground));
    const target = readable(background);
    let low = 0, high = 1;
    for (let i = 0; i < 22; i++) {
      const middle = (low + high) / 2;
      if (contrast(mix(foreground, target, middle), background) >= minimum) high = middle;
      else low = middle;
    }
    // Small offset prevents a rounding boundary from falling below the target.
    return mix(foreground, target, Math.min(1, high + 0.002));
  }

  function alpha(color, opacity) {
    return '#' + Math.round(opacity * 255).toString(16).padStart(2, '0').toUpperCase() + toHex(rgba(color)).slice(1);
  }

  // Explicit palette action: callers decide whether replacing advanced tokens is
  // appropriate. buildConfig() never invokes this function implicitly.
  function makePalette(seed = {}, mode = 'light') {
    if (mode !== 'light' && mode !== 'dark') throw new TypeError('Palette mode must be light or dark.');
    if (typeof seed === 'string') seed = {primary: seed};
    if (!isObject(seed)) throw new TypeError('Palette seed must be an object or a color.');
    const dark = mode === 'dark';
    for (const key of ['primary', 'accent', 'surface', 'paper', 'text']) if (seed[key] !== undefined) {
      if (rgba(seed[key])[3] !== 1) throw new TypeError(`Palette seed ${key} must be opaque.`);
    }
    const primary = seed.primary || (dark ? '#9DCCFF' : '#2255CC');
    const accent = seed.accent || primary;
    const surface = seed.surface || (dark ? '#19212E' : '#FFFFFF');
    const paper = seed.paper || mix(surface, primary, dark ? 0.025 : 0.035);
    const ink = ensureContrast(seed.text || (dark ? '#F4F7FC' : '#142033'), surface, 7);
    const secondary = ensureContrast(mix(ink, surface, 0.28), surface, 4.8);
    const tertiary = ensureContrast(mix(ink, surface, 0.42), surface, 4.5);
    const fill = primary;
    const cardStart = mix(primary, '#000000', 0.32);
    const cardMiddle = mix(primary, '#000000', 0.16);
    const cardEnd = primary;
    const candidates = ['#FFFFFF', '#000000'];
    const cardForeground = candidates.sort((a, b) => Math.min(...[cardStart, cardMiddle, cardEnd].map(bg => contrast(b, bg))) - Math.min(...[cardStart, cardMiddle, cardEnd].map(bg => contrast(a, bg))))[0];
    // Keep the full card gradient readable, even for medium-luminance brand colors.
    const safeCard = bg => ensureContrast(bg, cardForeground, 4.8);
    const high = mix(surface, dark ? '#FFFFFF' : '#FFFFFF', dark ? 0.07 : 0);
    return {
      paper, surface, surfaceSubtle: mix(surface, primary, 0.06), surfaceHigh: high,
      navigation: paper, navigationGlass: alpha(paper, 0.92), rail: mix(surface, primary, 0.13),
      glassTop: alpha(high, 0.94), glassBottom: alpha(surface, 0.94),
      ink, textSecondary: secondary, textTertiary: tertiary,
      border: mix(surface, ink, 0.3), borderSubtle: mix(surface, ink, 0.13),
      borderEmphasis: mix(surface, ink, 0.5), controlEdge: ensureContrast(mix(surface, ink, 0.45), surface, 3),
      fill, accent, success: ensureContrast(dark ? '#83D9A5' : '#197346', surface, 4.5),
      danger: ensureContrast(dark ? '#FFA8B4' : '#BD2441', surface, 4.5),
      warning: ensureContrast(dark ? '#FFD787' : '#845A0A', surface, 4.5),
      teal: ensureContrast(dark ? '#86DADC' : '#0D7477', surface, 4.5),
      shadowAmbient: alpha('#000000', dark ? 0.25 : 0.08), shadowLift: alpha('#000000', dark ? 0.5 : 0.14),
      skeletonBase: mix(surface, ink, 0.09), skeletonHighlight: mix(surface, ink, 0.16), sheenPeak: alpha('#FFFFFF', dark ? 0.5 : 0.8),
      onFill: readable(fill), cardStart: safeCard(cardStart), cardEnd: safeCard(cardEnd), cardMiddle: safeCard(cardMiddle),
      cardForeground, cardDecoration: mix(cardForeground, accent, 0.2), cardOverlay: alpha(cardForeground, 0.09),
      onAccent: readable(accent), snackbar: mix(surface, ink, 0.08),
      atmospherePrimary: alpha(primary, dark ? 0.22 : 0.1), atmosphereMid: alpha(primary, 0.06), atmosphereSecondary: alpha(accent, 0.1),
      loader: ensureContrast(primary, surface, 3), heroStart: mix(surface, primary, 0.09), heroEnd: mix(surface, accent, 0.08),
      mutedStart: mix(surface, primary, 0.04), mutedEnd: mix(surface, primary, 0.025)
    };
  }

  function contrastChecks(config) {
    const checks = [];
    for (const mode of ['light', 'dark']) {
      const p = config?.design?.[mode];
      if (!isObject(p)) continue;
      const pairs = [
        ['Main text / surface', 'ink', 'surface', 4.5], ['Main text / page', 'ink', 'paper', 4.5],
        ['Secondary text / surface', 'textSecondary', 'surface', 4.5], ['Tertiary text / surface', 'textTertiary', 'surface', 4.5],
        ['Primary button label', 'onFill', 'fill', 4.5], ['Accent button label', 'onAccent', 'accent', 4.5],
        ['Card label / gradient start', 'cardForeground', 'cardStart', 4.5], ['Card label / gradient middle', 'cardForeground', 'cardMiddle', 4.5],
        ['Card label / gradient end', 'cardForeground', 'cardEnd', 4.5]
      ];
      for (const [label, foreground, background, minimum] of pairs) {
        if (!COLOR.test(p[foreground]) || !COLOR.test(p[background]) || !COLOR.test(p.paper)) continue;
        const ratio = contrast({foreground: p[foreground], background: p[background], canvas: p.paper});
        checks.push({mode, label, foreground, background, ratio, minimum, pass: ratio >= minimum});
      }
    }
    return checks;
  }

  // assetMetadata is optional: Map or object keyed by the exact relative path.
  // Image: {valid: true, width, height}; font: {valid: true}; Firebase: {data: {...}}.
  // No entry means unverified, not a claim that a file exists. {exists:false} or
  // {valid:false} rejects a supplied asset. Filesystem + native Firebase checks in
  // prepare-mobile-brand.py remain the final authority before building.
  function validateConfig(input, assetMetadata) {
    const errors = [], warnings = [], assets = [];
    const error = (path, message) => errors.push({path, message});
    const warning = (path, message) => warnings.push({path, message});
    const object = (value, path, keys) => {
      if (!isObject(value)) { error(path, 'Must be an object.'); return false; }
      for (const key of Object.keys(value)) if (!keys.includes(key)) error(`${path}.${key}`, 'Unknown field; the app generator rejects this key.');
      return true;
    };
    const string = (value, path, required = false) => {
      if (typeof value !== 'string') { error(path, 'Must be a string.'); return false; }
      if (required && !value.trim()) error(path, 'Must not be empty.');
      if (/[\x00-\x1f]/.test(value)) error(path, 'Must not contain control characters.');
      return true;
    };
    const number = (value, path, low, high, integer = false) => {
      if (typeof value !== 'number' || !Number.isFinite(value)) error(path, 'Must be a finite number.');
      else if (integer && !Number.isInteger(value)) error(path, 'Must be an integer.');
      else if (value < low || value > high) error(path, `Must be between ${low} and ${high}.`);
    };
    const boolean = (value, path) => { if (typeof value !== 'boolean') error(path, 'Must be true or false.'); };
    const oneOf = (value, path, choices) => { if (!choices.includes(value)) error(path, `Choose ${choices.join(', ')}.`); };
    const color = (value, path, opaque = false) => {
      if (typeof value !== 'string' || !COLOR.test(value)) error(path, 'Use #RRGGBB or #AARRGGBB (alpha first).');
      else if (opaque && value.length === 9 && value.slice(1, 3).toUpperCase() !== 'FF') error(path, 'This background must be opaque (#RRGGBB or #FFRRGGBB).');
    };
    const metadataFor = path => assetMetadata instanceof Map ? assetMetadata.get(path) : isObject(assetMetadata) && has(assetMetadata, path) ? assetMetadata[path] : undefined;
    const asset = (value, field, kind, extensions) => {
      const entry = {path: value, field, kind, status: 'unverified'};
      assets.push(entry);
      const before = errors.length;
      if (!string(value, field, true)) { entry.status = 'invalid'; return undefined; }
      if (value.startsWith('/') || value.includes('\\') || value.split('/').includes('..') || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(value)) error(field, 'Use a relative file path inside the config folder, without URLs, backslashes, or .. segments.');
      const extension = value.includes('.') ? value.slice(value.lastIndexOf('.')).toLowerCase() : '';
      if (!extensions.includes(extension)) error(field, `Supported files: ${extensions.join(', ')}.`);
      if (errors.length !== before) { entry.status = 'invalid'; return undefined; }
      const metadata = metadataFor(value);
      if (!metadata) {
        warning(field, `File not verified in this guide: ${value}. Include it beside the JSON at this relative path, then run the preparation check.`);
      } else if (metadata.exists === false || metadata.valid === false) {
        entry.status = 'invalid'; error(field, metadata.error || 'The selected file is missing or could not be decoded.');
      } else if (kind === 'image') {
        if (metadata.width !== undefined || metadata.height !== undefined) {
          if (![metadata.width, metadata.height].every(n => Number.isInteger(n) && n > 0 && n <= 8192)) {
            entry.status = 'invalid'; error(field, 'Image width and height must each be between 1 and 8192 pixels.');
          } else if (metadata.valid === true) entry.status = 'verified';
        }
        if (entry.status === 'unverified') warning(field, 'File supplied, but image decoding and dimensions have not been verified.');
        if (field === 'native.icon' && entry.status === 'verified' && Math.min(metadata.width, metadata.height) < 1024) warning(field, 'A square 1024 × 1024 source is recommended for a crisp app icon; the generator can resize smaller artwork.');
      } else if (kind === 'font') {
        if (metadata.valid === true) entry.status = 'verified';
        else warning(field, 'Font path supplied; verify the actual TTF/OTF file in the build check.');
      } else if (isObject(metadata.data)) entry.status = 'supplied';
      else warning(field, 'Firebase file supplied, but its application ID and project have not been verified.');
      if (kind === 'image' && extension === '.gif') warning(field, 'The generator uses the first GIF frame. Loader animation comes from the selected loader style.');
      return metadata;
    };
    if (!object(input, 'config', ['schemaVersion', 'app', 'design', 'native', 'fonts', 'flutterDefines'])) return {valid: false, errors, warnings, assets, contrasts: []};
    const config = buildConfig(input);
    if (config.schemaVersion !== 1) error('schemaVersion', 'Must be 1.');
    const app = config.app;
    if (object(app, 'app', ['name', 'id', 'description', 'supportEmail', 'supportPhone', 'legalEntity', 'themeMode', 'transferDashboardUrl'])) {
      string(app.name, 'app.name', true);
      if (typeof app.name === 'string' && (Array.from(app.name).length > 60 || /[$#"\\;]/.test(app.name) || app.name.includes('//'))) error('app.name', 'Use at most 60 characters; $, #, double quotes, backslashes, semicolons, and // are unsupported by native builds.');
      string(app.id, 'app.id', true);
      if (typeof app.id === 'string' && !/^[a-z][a-z0-9_-]{1,63}(?![\s\S])/.test(app.id)) error('app.id', 'Use 2–64 lowercase characters; start with a letter, then letters, numbers, _ or -.');
      for (const key of ['description', 'supportEmail', 'supportPhone', 'legalEntity', 'transferDashboardUrl']) string(app[key], `app.${key}`);
      oneOf(app.themeMode, 'app.themeMode', ['system', 'light', 'dark']);
      if (app.supportEmail && typeof app.supportEmail === 'string' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(app.supportEmail)) warning('app.supportEmail', 'Check the support email address before sharing the app.');
      if (app.transferDashboardUrl && typeof app.transferDashboardUrl === 'string' && !/^https:\/\/[^\s]+$/i.test(app.transferDashboardUrl)) warning('app.transferDashboardUrl', 'Use an HTTPS dashboard URL for production, or leave this empty.');
    }
    const design = config.design;
    if (object(design, 'design', ['layout', 'light', 'dark', 'typography', 'shape', 'assets', 'loader', 'splash', 'motion'])) {
      oneOf(design.layout, 'design.layout', ['example', 'generic']);
      for (const mode of ['light', 'dark']) if (object(design[mode], `design.${mode}`, PALETTE_KEYS)) {
        for (const key of REQUIRED_PALETTE_KEYS) if (!has(design[mode], key)) error(`design.${mode}.${key}`, 'Required color token is missing.');
        for (const [key, value] of Object.entries(design[mode])) if (PALETTE_KEYS.includes(key)) color(value, `design.${mode}.${key}`);
      }
      if (object(design.typography, 'design.typography', ['fontFamily', 'monoFontFamily', 'scale'])) {
        for (const key of ['fontFamily', 'monoFontFamily']) string(design.typography[key], `design.typography.${key}`);
        number(design.typography.scale, 'design.typography.scale', 0.75, 1.5);
      }
      if (object(design.shape, 'design.shape', ['radiusScale'])) number(design.shape.radiusScale, 'design.shape.radiusScale', 0, 2);
      if (object(design.assets, 'design.assets', ['logo', 'logoDark', 'splash', 'loader'])) {
        if (!has(design.assets, 'logo')) error('design.assets.logo', 'A logo image is required.');
        for (const [key, value] of Object.entries(design.assets)) if (['logo', 'logoDark', 'splash', 'loader'].includes(key)) asset(value, `design.assets.${key}`, 'image', ['.png', '.jpg', '.jpeg', '.webp', '.gif']);
      }
      if (object(design.loader, 'design.loader', ['style', 'durationMs'])) {
        oneOf(design.loader.style, 'design.loader.style', ['circular', 'logo']);
        number(design.loader.durationMs, 'design.loader.durationMs', 200, 10000, true);
      }
      if (object(design.splash, 'design.splash', ['enabled', 'backgroundLight', 'backgroundDark', 'minimumDurationMs', 'maximumDurationMs'])) {
        boolean(design.splash.enabled, 'design.splash.enabled');
        for (const mode of ['Light', 'Dark']) color(design.splash[`background${mode}`], `design.splash.background${mode}`, true);
        number(design.splash.minimumDurationMs, 'design.splash.minimumDurationMs', 0, 10000, true);
        number(design.splash.maximumDurationMs, 'design.splash.maximumDurationMs', 0, 30000, true);
        if (typeof design.splash.minimumDurationMs === 'number' && typeof design.splash.maximumDurationMs === 'number' && design.splash.minimumDurationMs > design.splash.maximumDurationMs) error('design.splash.minimumDurationMs', 'The minimum splash duration must not exceed the maximum.');
      }
      if (object(design.motion, 'design.motion', ['enabled', 'durationScale'])) {
        boolean(design.motion.enabled, 'design.motion.enabled');
        number(design.motion.durationScale, 'design.motion.durationScale', 0.1, 3);
      }
    }
    const native = config.native;
    if (object(native, 'native', ['androidApplicationId', 'iosBundleId', 'icon', 'iconBackground', 'firebase'])) {
      for (const [key, pattern] of [['androidApplicationId', /^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+(?![\s\S])/], ['iosBundleId', /^[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*)+(?![\s\S])/]]) {
        if (typeof native[key] !== 'string' || !pattern.test(native[key])) error(`native.${key}`, key === 'androidApplicationId' ? 'Use a reverse-DNS ID such as com.customer.wallet; lowercase letters, numbers and underscores are supported.' : 'Use a reverse-DNS ID such as com.customer.wallet; letters, numbers and hyphens are supported.');
      }
      asset(native.icon, 'native.icon', 'image', ['.png', '.jpg', '.jpeg', '.webp', '.gif']);
      color(native.iconBackground, 'native.iconBackground', true);
      if (object(native.firebase, 'native.firebase', ['android', 'ios'])) {
        const firebase = {};
        const nonempty = value => (typeof value === 'string' || Number.isInteger(value)) && String(value).trim().length > 0;
        for (const platform of ['android', 'ios']) if (has(native.firebase, platform)) {
          const field = `native.firebase.${platform}`;
          const info = asset(native.firebase[platform], field, 'firebase', platform === 'android' ? ['.json'] : ['.plist']);
          if (!isObject(info?.data)) continue;
          const data = info.data;
          const before = errors.length;
          if (platform === 'android') {
            const client = Array.isArray(data.client) && data.client.find(c => c?.client_info?.android_client_info?.package_name === native.androidApplicationId);
            if (!client) error(field, 'Android Firebase config does not contain the configured Android application ID.');
            const values = [data.project_info?.project_id, data.project_info?.project_number, client?.client_info?.mobilesdk_app_id, client?.api_key?.[0]?.current_key];
            if (!values.every(nonempty)) error(field, 'Android Firebase project ID, project number, mobile app ID and API key must be present.');
            firebase.android = {project: values[0], sender: values[1]};
          } else {
            if (data.BUNDLE_ID !== native.iosBundleId) error(field, 'iOS Firebase BUNDLE_ID must match the configured iOS bundle ID.');
            if (![data.PROJECT_ID, data.GCM_SENDER_ID, data.GOOGLE_APP_ID, data.API_KEY, data.BUNDLE_ID].every(nonempty)) error(field, 'iOS Firebase project ID, sender ID, app ID, API key and bundle ID must be present.');
            firebase.ios = {project: data.PROJECT_ID, sender: data.GCM_SENDER_ID};
          }
          const record = assets.findLast ? assets.findLast(a => a.field === field) : assets.filter(a => a.field === field).pop();
          if (record) record.status = before === errors.length ? 'verified' : 'invalid';
        }
        if (firebase.android && firebase.ios && (firebase.android.project !== firebase.ios.project || String(firebase.android.sender) !== String(firebase.ios.sender))) error('native.firebase', 'Android and iOS Firebase files must use the same project and messaging sender.');
      }
    }
    const families = new Set(['', 'Geist', 'GeistMono']);
    if (!Array.isArray(config.fonts)) error('fonts', 'Must be an array.');
    else config.fonts.forEach((font, index) => {
      const field = `fonts[${index}]`;
      if (!object(font, field, ['family', 'files'])) return;
      if (string(font.family, `${field}.family`, true)) {
        if (!/^[A-Za-z][A-Za-z0-9 _-]*(?![\s\S])/.test(font.family)) error(`${field}.family`, 'Start with a letter; use letters, numbers, spaces, _ or -.');
        if (families.has(font.family)) error(`${field}.family`, 'Font families must be unique and cannot replace bundled Geist or GeistMono.');
        families.add(font.family);
      }
      if (!Array.isArray(font.files) || !font.files.length) error(`${field}.files`, 'Add at least one TTF or OTF font file.');
      else font.files.forEach((file, fileIndex) => {
        const fileField = `${field}.files[${fileIndex}]`;
        if (!object(file, fileField, ['path', 'weight', 'style'])) return;
        asset(file.path, `${fileField}.path`, 'font', ['.ttf', '.otf']);
        number(file.weight, `${fileField}.weight`, 100, 900, true);
        if (typeof file.weight === 'number' && Number.isFinite(file.weight) && file.weight % 100 !== 0) error(`${fileField}.weight`, 'Font weight must be a multiple of 100.');
        oneOf(file.style, `${fileField}.style`, ['normal', 'italic']);
      });
    });
    if (isObject(design?.typography)) for (const key of ['fontFamily', 'monoFontFamily']) if (typeof design.typography[key] === 'string' && !families.has(design.typography[key])) error(`design.typography.${key}`, 'Choose Geist, GeistMono, an empty default, or a family declared in fonts.');
    const defines = config.flutterDefines;
    if (!isObject(defines)) error('flutterDefines', 'Must be an object of public build-time values.');
    else {
      for (const [key, value] of Object.entries(defines)) {
        const path = `flutterDefines.${key}`;
        if (!/^[A-Z][A-Z0-9_]*(?![\s\S])/.test(key)) error(path, 'Define names must be UPPER_SNAKE_CASE and start with a letter.');
        if (RESERVED_DEFINES.has(key) || key.startsWith('FIREBASE_')) error(path, 'This value is generated; configure app, design or native.firebase instead.');
        if (!['string', 'number', 'boolean'].includes(typeof value) || (typeof value === 'number' && !Number.isFinite(value))) error(path, 'Use a string, finite number or boolean; arrays, objects and null are unsupported.');
        if (/(?:SECRET|PASSWORD|PRIVATE_KEY|DATABASE|CONNECTION_STRING|ACCESS_TOKEN|CLIENT_SECRET)/.test(key)) warning(path, 'Build-time defines are public in the app. Keep server credentials and private keys in the server environment, outside this JSON.');
      }
      const api = defines.API_BASE_URL;
      if (typeof api !== 'string' || !/^https?:\/\/[^\s/?#]+(?:\/[^\s?#]*)?$/i.test(api)) warning('flutterDefines.API_BASE_URL', 'Set the public HTTPS API base URL before a customer release (for example https://api.customer.example).');
      else if (!api.toLowerCase().startsWith('https://')) warning('flutterDefines.API_BASE_URL', 'HTTP is suitable for local development only; use HTTPS for a customer release.');
      if (typeof api === 'string' && /(?:localhost|127\.0\.0\.1|example\.com|customer\.example)/i.test(api)) warning('flutterDefines.API_BASE_URL', 'This API URL looks like a placeholder or local development address; replace it for production.');
    }
    const contrasts = contrastChecks(config);
    for (const check of contrasts) if (!check.pass) warning(`design.${check.mode}.${check.foreground}`, `${check.label}: contrast is ${check.ratio.toFixed(2)}:1; aim for at least ${check.minimum}:1 for normal text.`);
    return {valid: errors.length === 0, errors, warnings, assets, contrasts};
  }

  const paletteHelp = {
    paper: 'Page background.', surface: 'Cards, dialogs and base surfaces.', surfaceSubtle: 'Quiet secondary surfaces.', surfaceHigh: 'Raised surfaces.',
    navigation: 'Navigation background.', navigationGlass: 'Translucent navigation background (ARGB allowed).', rail: 'Navigation rails and tracks.',
    glassTop: 'Top color of translucent glass.', glassBottom: 'Bottom color of translucent glass.',
    ink: 'Main text and icons.', textSecondary: 'Supporting text.', textTertiary: 'Quiet labels; keep readable at small sizes.',
    border: 'Standard outlines.', borderSubtle: 'Subtle separators.', borderEmphasis: 'Strong outlines.', controlEdge: 'Input and control edges.',
    fill: 'Primary actions and filled controls.', accent: 'Secondary brand accent and actions.', success: 'Successful states.', danger: 'Errors and destructive states.', warning: 'Warnings.', teal: 'Additional informational accent.',
    shadowAmbient: 'Soft ambient shadow; alpha first.', shadowLift: 'Raised-element shadow; alpha first.', skeletonBase: 'Loading placeholder base.', skeletonHighlight: 'Loading placeholder highlight.', sheenPeak: 'Shimmer highlight; alpha first.',
    onFill: 'Text and icons on primary fill.', onAccent: 'Text and icons on accent.',
    cardStart: 'Payment-card gradient start.', cardMiddle: 'Payment-card gradient middle.', cardEnd: 'Payment-card gradient end.', cardForeground: 'Payment-card text and icons; check every gradient stop.', cardDecoration: 'Payment-card decorative marks.', cardOverlay: 'Payment-card overlay; alpha first.',
    snackbar: 'Transient notification background.', atmospherePrimary: 'Main background glow; alpha first.', atmosphereMid: 'Middle background glow; alpha first.', atmosphereSecondary: 'Secondary background glow; alpha first.', loader: 'Loader indicator color.', heroStart: 'Feature-panel gradient start.', heroEnd: 'Feature-panel gradient end.', mutedStart: 'Subtle-panel gradient start.', mutedEnd: 'Subtle-panel gradient end.'
  };
  const descriptor = (path, label, type, help, extra = {}) => ({path, label, type, help, ...extra});
  const fieldDescriptors = {
    identity: [
      descriptor('app.name', 'App name', 'text', 'Customer-facing display name on the app, PWA and native launcher.', {required: true, maxLength: 60}),
      descriptor('app.id', 'Brand ID', 'text', 'A stable lowercase 2–64 character ID, for example customer-pay.', {required: true}),
      descriptor('app.description', 'App description', 'text', 'Short public description for web metadata.'),
      descriptor('app.supportEmail', 'Support email', 'email', 'Customer support address displayed in the app.'),
      descriptor('app.supportPhone', 'Support phone', 'tel', 'Optional public customer support number.'),
      descriptor('app.legalEntity', 'Legal entity', 'text', 'The customer’s company name for public app identity.'),
      descriptor('app.transferDashboardUrl', 'Transfer dashboard URL', 'url', 'Optional HTTPS destination for account transfers. Leave empty if unused.'),
      descriptor('flutterDefines.API_BASE_URL', 'API base URL', 'url', 'Public HTTPS address of the customer API. Do not include passwords or provider secrets.', {required: true}),
      descriptor('app.themeMode', 'Theme preference', 'select', 'Follow the device or force one mode. Configure both palettes even when one mode is forced.', {options: ['system', 'light', 'dark']}),
      descriptor('design.layout', 'Layout preset', 'select', 'example keeps the existing premium app layout; generic uses the generic layout. Both use your colors and identity.', {options: ['example', 'generic']})
    ],
    native: [
      descriptor('native.androidApplicationId', 'Android application ID', 'text', 'Use a customer-owned reverse-DNS ID such as com.customer.wallet. Keep it stable after store publication.', {required: true}),
      descriptor('native.iosBundleId', 'iOS bundle ID', 'text', 'Use the ID registered in the customer’s Apple developer account. Keep it stable after publication.', {required: true}),
      descriptor('native.icon', 'App icon file', 'asset', 'Required PNG/JPG/WebP/GIF; a square 1024 × 1024 image is recommended. Native launcher and PWA icons are generated from it.', {required: true, accept: '.png,.jpg,.jpeg,.webp,.gif'}),
      descriptor('native.iconBackground', 'Icon background', 'color', 'Opaque fill behind the native icon; required even when source artwork is transparent.', {opaque: true}),
      descriptor('native.firebase.android', 'Android Firebase file', 'asset', 'Optional google-services.json for this Android application ID. Push setup also requires server-side Firebase credentials.', {accept: '.json', optional: true}),
      descriptor('native.firebase.ios', 'iOS Firebase file', 'asset', 'Optional GoogleService-Info.plist for this iOS bundle ID. Both Firebase files must use the same project.', {accept: '.plist', optional: true})
    ],
    assets: [
      descriptor('design.assets.logo', 'Logo', 'asset', 'Required logo for light mode. PNG with transparency is usually easiest; SVG is not supported by this pipeline.', {required: true, accept: '.png,.jpg,.jpeg,.webp,.gif'}),
      descriptor('design.assets.logoDark', 'Dark-mode logo', 'asset', 'Optional alternate artwork. If omitted, the normal logo is reused.', {optional: true, accept: '.png,.jpg,.jpeg,.webp,.gif'}),
      descriptor('design.assets.splash', 'Splash artwork', 'asset', 'Optional launch artwork. If omitted, the logo is used.', {optional: true, accept: '.png,.jpg,.jpeg,.webp,.gif'}),
      descriptor('design.assets.loader', 'Loader artwork', 'asset', 'Optional artwork for the logo loader. If omitted, the logo is used. GIFs become a static first frame.', {optional: true, accept: '.png,.jpg,.jpeg,.webp,.gif'})
    ],
    typography: [
      descriptor('design.typography.fontFamily', 'App font', 'font', 'Geist is bundled. A custom family must have matching TTF/OTF files declared in fonts.', {options: ['Geist', 'GeistMono']}),
      descriptor('design.typography.monoFontFamily', 'Number / monospace font', 'font', 'GeistMono is bundled. Custom families must be declared in fonts.', {options: ['GeistMono', 'Geist']}),
      descriptor('design.typography.scale', 'Text size scale', 'number', '1 is standard. Check small screens and long translations after changing it.', {min: 0.75, max: 1.5, step: 0.05}),
      descriptor('fonts', 'Custom font files', 'json', 'Array of {family, files:[{path, weight, style}]}. Paths are relative to the JSON. Weights: 100–900 in steps of 100; styles: normal or italic. Include the font license with the handoff.')
    ],
    motion: [
      descriptor('design.shape.radiusScale', 'Corner radius scale', 'number', '0 is square; 1 is standard; 2 doubles the configured radii.', {min: 0, max: 2, step: 0.1}),
      descriptor('design.loader.style', 'Loader style', 'select', 'logo animates your artwork; circular uses a progress ring.', {options: ['logo', 'circular']}),
      descriptor('design.loader.durationMs', 'Loader cycle (ms)', 'number', 'Duration of one loader animation cycle; this does not change API request timeouts.', {min: 200, max: 10000, step: 100}),
      descriptor('design.motion.enabled', 'Enable animation', 'checkbox', 'Disable configurable decorative animation. Device reduced-motion settings are also respected.'),
      descriptor('design.motion.durationScale', 'Animation duration scale', 'number', '1 is standard; larger values animate more slowly.', {min: 0.1, max: 3, step: 0.1}),
      descriptor('design.splash.enabled', 'Show splash overlay', 'checkbox', 'Controls the app splash overlay. Native launch screens still use generated branding.'),
      descriptor('design.splash.backgroundLight', 'Light splash background', 'color', 'Opaque background for light-mode launch and splash.', {opaque: true}),
      descriptor('design.splash.backgroundDark', 'Dark splash background', 'color', 'Opaque background for dark-mode launch and splash.', {opaque: true}),
      descriptor('design.splash.minimumDurationMs', 'Minimum splash time (ms)', 'number', 'Shortest time to retain the splash overlay.', {min: 0, max: 10000, step: 100}),
      descriptor('design.splash.maximumDurationMs', 'Maximum splash time (ms)', 'number', 'Upper splash limit; must be at least the minimum. This is not an API timeout.', {min: 0, max: 30000, step: 100})
    ],
    palette: PALETTE_KEYS.map(key => descriptor(key, key.replace(/([A-Z])/g, ' $1').replace(/^./, c => c.toUpperCase()), 'color', paletteHelp[key], {optional: OPTIONAL_PALETTE_KEYS.includes(key)})),
    advanced: [descriptor('flutterDefines', 'Public build-time values', 'json', 'Preserved during import and export. Keys must be UPPER_SNAKE_CASE. Values may be strings, numbers or booleans. Do not add generated APP_* identity fields, FIREBASE_* values or private server credentials.')]
  };

  scope.BrandGuideEngine = Object.freeze({
    init: buildConfig, clone, buildConfig, validateConfig, makePalette, contrast, contrastChecks,
    fieldDescriptors, paletteKeys: Object.freeze([...PALETTE_KEYS]), requiredPaletteKeys: Object.freeze([...REQUIRED_PALETTE_KEYS]),
    optionalPaletteKeys: Object.freeze([...OPTIONAL_PALETTE_KEYS])
  });
})(globalThis);
