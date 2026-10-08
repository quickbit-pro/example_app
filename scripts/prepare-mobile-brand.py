#!/usr/bin/env python3
"""Validate one brand file, then generate Flutter, Android, iOS and web branding.

Asset and font paths are relative to the configuration file, confined to its
folder. No files change until validation (including native Firebase IDs) passes.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import html
import json
import math
from pathlib import Path
import plistlib
import re
import shutil
import sys
from xml.sax.saxutils import escape

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
MOBILE = ROOT / 'mobile_flutter'
PALETTE = set('paper surface surfaceSubtle surfaceHigh navigation navigationGlass rail glassTop glassBottom ink textSecondary textTertiary border borderSubtle borderEmphasis controlEdge fill accent success danger warning teal shadowAmbient shadowLift skeletonBase skeletonHighlight sheenPeak onFill cardStart cardEnd cardMiddle cardForeground cardDecoration cardOverlay onAccent snackbar atmospherePrimary atmosphereMid atmosphereSecondary loader heroStart heroEnd mutedStart mutedEnd'.split())
OPTIONAL_PALETTE = set('onAccent snackbar atmospherePrimary atmosphereMid atmosphereSecondary loader cardMiddle cardForeground cardDecoration cardOverlay'.split())
REQUIRED_PALETTE = PALETTE - OPTIONAL_PALETTE
ASSETS = {'logo', 'logoDark', 'splash', 'loader'}
COLOR_RE = re.compile(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
FONT_BEGIN = '  # BEGIN GENERATED BRAND FONTS'
FONT_END = '  # END GENERATED BRAND FONTS'


class ConfigError(ValueError):
    pass


def check(ok, message):
    if not ok:
        raise ConfigError(message)


def obj(value, label, keys):
    check(isinstance(value, dict), f'{label} must be an object')
    check(not set(value) - set(keys), f'{label}: unknown keys: {sorted(set(value) - set(keys))}')
    return value


def string(value, label, required=False):
    check(isinstance(value, str), f'{label} must be a string')
    check(not required or bool(value.strip()), f'{label} must not be empty')
    check(not any(ord(c) < 32 for c in value), f'{label} must not contain control characters')
    return value


def color(value, label, opaque=False):
    check(isinstance(value, str) and COLOR_RE.fullmatch(value), f'{label} must be #RRGGBB or #AARRGGBB')
    check(not opaque or len(value) == 7 or value[1:3].upper() == 'FF', f'{label} must be opaque')
    return value.upper()


def number(value, label, low, high, integer=False):
    check(type(value) in (int, float) and math.isfinite(value), f'{label} must be a finite number')
    check(not integer or type(value) is int, f'{label} must be an integer')
    check(low <= value <= high, f'{label} must be between {low} and {high}')


def enum(value, label, choices):
    check(isinstance(value, str) and value in choices, f'{label} must be one of {", ".join(choices)}')


def asset_path(base, value, label, suffixes):
    string(value, label, required=True)
    relative = Path(value)
    check(not relative.is_absolute() and '..' not in relative.parts and '\\' not in value,
          f'{label} must be a relative path without parent traversal')
    resolved = (base / relative).resolve()
    check(resolved.is_relative_to(base.resolve()), f'{label} escapes the config folder')
    check(resolved.is_file(), f'{label} file not found: {value}')
    check(resolved.suffix.lower() in suffixes, f'{label} unsupported file type; expected {sorted(suffixes)}')
    return resolved


def image_path(base, value, label):
    path = asset_path(base, value, label, {'.png', '.jpg', '.jpeg', '.webp', '.gif'})
    try:
        with Image.open(path) as image:
            check(0 < image.width <= 8192 and 0 < image.height <= 8192, f'{label}: dimensions must be at most 8192 pixels')
            image.verify()
    except (OSError, Image.DecompressionBombError) as error:
        raise ConfigError(f'{label}: invalid image: {error}') from error
    return path


def load_config(path):
    try:
        config = json.loads(path.read_text(), parse_constant=lambda value: (_ for _ in ()).throw(ConfigError(f'Invalid JSON number: {value}')))
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigError(f'Cannot read config: {error}') from error
    obj(config, 'config', {'schemaVersion', 'app', 'design', 'native', 'fonts', 'flutterDefines'})
    check(type(config.get('schemaVersion')) is int and config['schemaVersion'] == 1, 'schemaVersion must be 1')
    app = obj(config.get('app'), 'app', {'name', 'id', 'description', 'supportEmail', 'supportPhone', 'legalEntity', 'themeMode', 'transferDashboardUrl'})
    for key in ('name', 'id'):
        string(app.get(key), f'app.{key}', required=True)
    check(re.fullmatch(r'[a-z][a-z0-9_-]{1,63}', app['id']), 'app.id must be a lowercase identifier (2-64 characters)')
    check(len(app['name']) <= 60 and not re.search(r'[$#"\\;]', app['name']) and '//' not in app['name'], 'app.name contains unsupported native build characters or exceeds 60 characters')
    for key in ('description', 'supportEmail', 'supportPhone', 'legalEntity', 'transferDashboardUrl'):
        string(app.setdefault(key, ''), f'app.{key}')
    enum(app.setdefault('themeMode', 'system'), 'app.themeMode', ('system', 'light', 'dark'))
    design = obj(config.get('design'), 'design', {'layout', 'light', 'dark', 'typography', 'shape', 'assets', 'loader', 'splash', 'motion'})
    enum(design.setdefault('layout', 'example'), 'design.layout', ('example', 'generic'))
    for mode in ('light', 'dark'):
        palette = obj(design.get(mode), f'design.{mode}', PALETTE)
        check(REQUIRED_PALETTE <= set(palette), f'design.{mode} is missing palette keys: {sorted(REQUIRED_PALETTE - set(palette))}')
        for key, value in palette.items():
            color(value, f'design.{mode}.{key}')
    typography = obj(design.setdefault('typography', {}), 'design.typography', {'fontFamily', 'monoFontFamily', 'scale'})
    for key in ('fontFamily', 'monoFontFamily'):
        string(typography.setdefault(key, ''), f'design.typography.{key}')
    number(typography.setdefault('scale', 1), 'design.typography.scale', 0.75, 1.5)
    shape = obj(design.setdefault('shape', {}), 'design.shape', {'radiusScale'})
    number(shape.setdefault('radiusScale', 1), 'design.shape.radiusScale', 0, 2)
    assets = obj(design.setdefault('assets', {}), 'design.assets', ASSETS)
    check('logo' in assets, 'design.assets.logo is required')
    paths = {}
    for key, value in assets.items():
        paths[key] = image_path(path.parent, value, f'design.assets.{key}')
    loader = obj(design.setdefault('loader', {}), 'design.loader', {'style', 'durationMs'})
    enum(loader.setdefault('style', 'logo'), 'design.loader.style', ('circular', 'logo'))
    number(loader.setdefault('durationMs', 1200), 'design.loader.durationMs', 200, 10000, integer=True)
    splash = obj(design.setdefault('splash', {}), 'design.splash', {'enabled', 'backgroundLight', 'backgroundDark', 'minimumDurationMs', 'maximumDurationMs'})
    check(type(splash.setdefault('enabled', True)) is bool, 'design.splash.enabled must be a boolean')
    for mode in ('Light', 'Dark'):
        color(splash.setdefault(f'background{mode}', design[mode.lower()]['paper']), f'design.splash.background{mode}', opaque=True)
    number(splash.setdefault('minimumDurationMs', 700), 'design.splash.minimumDurationMs', 0, 10000, integer=True)
    number(splash.setdefault('maximumDurationMs', 12000), 'design.splash.maximumDurationMs', 0, 30000, integer=True)
    check(splash['minimumDurationMs'] <= splash['maximumDurationMs'], 'splash minimumDurationMs must not exceed maximumDurationMs')
    motion = obj(design.setdefault('motion', {}), 'design.motion', {'enabled', 'durationScale'})
    check(type(motion.setdefault('enabled', True)) is bool, 'design.motion.enabled must be a boolean')
    number(motion.setdefault('durationScale', 1), 'design.motion.durationScale', 0.1, 3)
    native = obj(config.get('native'), 'native', {'androidApplicationId', 'iosBundleId', 'icon', 'iconBackground', 'firebase'})
    for key, pattern in [('androidApplicationId', r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+'), ('iosBundleId', r'[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*)+')]:
        check(isinstance(native.get(key), str) and re.fullmatch(pattern, native[key]), f'native.{key} must be a reverse-DNS application identifier')
    paths['icon'] = image_path(path.parent, native.get('icon'), 'native.icon')
    color(native.setdefault('iconBackground', design['light']['fill']), 'native.iconBackground', opaque=True)
    firebase = obj(native.setdefault('firebase', {}), 'native.firebase', {'android', 'ios'})
    firebase_data = {}
    for platform in ('android', 'ios'):
        if platform not in firebase:
            continue
        value = firebase[platform]
        fpath = asset_path(path.parent, value, f'native.firebase.{platform}', {'.json'} if platform == 'android' else {'.plist'})
        try:
            data = json.loads(fpath.read_text()) if platform == 'android' else plistlib.loads(fpath.read_bytes())
            if platform == 'android':
                check(isinstance(data, dict), 'Android Firebase config must be an object')
                clients = [c for c in data.get('client', []) if c.get('client_info', {}).get('android_client_info', {}).get('package_name') == native['androidApplicationId']]
                check(bool(clients), 'Android Firebase config does not contain native.androidApplicationId')
                client = clients[0]
                firebase_data.update(FIREBASE_PROJECT_ID=data['project_info']['project_id'], FIREBASE_MESSAGING_SENDER_ID=data['project_info']['project_number'], FIREBASE_ANDROID_APP_ID=client['client_info']['mobilesdk_app_id'], FIREBASE_ANDROID_API_KEY=client['api_key'][0]['current_key'])
            else:
                check(data.get('BUNDLE_ID') == native['iosBundleId'], 'iOS Firebase config BUNDLE_ID does not match native.iosBundleId')
                if 'FIREBASE_PROJECT_ID' in firebase_data:
                    check(firebase_data['FIREBASE_PROJECT_ID'] == data['PROJECT_ID'] and str(firebase_data['FIREBASE_MESSAGING_SENDER_ID']) == str(data['GCM_SENDER_ID']), 'Android and iOS Firebase files must use the same project')
                firebase_data.update(FIREBASE_PROJECT_ID=data['PROJECT_ID'], FIREBASE_MESSAGING_SENDER_ID=data['GCM_SENDER_ID'], FIREBASE_IOS_APP_ID=data['GOOGLE_APP_ID'], FIREBASE_IOS_API_KEY=data['API_KEY'], FIREBASE_IOS_BUNDLE_ID=data['BUNDLE_ID'])
        except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError) as error:
            raise ConfigError(f'Invalid native.firebase.{platform}: {error}') from error
        for key, value in firebase_data.items():
            check(isinstance(value, (str, int)) and str(value).strip(), f'{key} must not be empty in native Firebase config')
        paths[f'firebase_{platform}'] = fpath
    fonts = config.setdefault('fonts', [])
    check(isinstance(fonts, list), 'fonts must be an array')
    families = set()
    for i, font in enumerate(fonts):
        obj(font, f'fonts[{i}]', {'family', 'files'})
        family = string(font.get('family'), f'fonts[{i}].family', required=True)
        check(re.fullmatch(r'[A-Za-z][A-Za-z0-9 _-]*', family) and family not in families | {'Geist', 'GeistMono'}, 'Font families must be unique, and must not replace bundled Geist/GeistMono')
        families.add(family)
        check(isinstance(font.get('files'), list) and bool(font['files']), f'fonts[{i}].files must be a nonempty array')
        for j, entry in enumerate(font['files']):
            obj(entry, f'fonts[{i}].files[{j}]', {'path', 'weight', 'style'})
            paths[f'font_{i}_{j}'] = asset_path(path.parent, entry.get('path'), f'fonts[{i}].files[{j}].path', {'.ttf', '.otf'})
            number(entry.setdefault('weight', 400), 'font weight', 100, 900, integer=True)
            check(entry['weight'] % 100 == 0, 'font weight must be a multiple of 100')
            enum(entry.setdefault('style', 'normal'), 'font style', ('normal', 'italic'))
    for key in ('fontFamily', 'monoFontFamily'):
        check(typography[key] in families | {'', 'Geist', 'GeistMono'}, f'design.typography.{key} must name a bundled family or a family declared in fonts')
    defines = obj(config.setdefault('flutterDefines', {}), 'flutterDefines', config.get('flutterDefines', {}).keys() if isinstance(config.get('flutterDefines', {}), dict) else [])
    reserved = {'APP_NAME', 'APP_BRAND_ID', 'APP_THEME_MODE', 'APP_DESIGN_JSON', 'APP_FONT_FAMILY', 'APP_LOGO_ASSET', 'APP_PRIMARY_COLOR', 'APP_ACCENT_COLOR', 'APP_LOGIN_BACKGROUND_COLOR', 'APP_RADIUS_SCALE', 'SUPPORT_EMAIL', 'SUPPORT_PHONE', 'LEGAL_ENTITY', 'ACCOUNT_TRANSFER_DASHBOARD_URL'}
    for key, value in defines.items():
        check(re.fullmatch(r'[A-Z][A-Z0-9_]*', key), 'flutterDefines keys must be UPPER_SNAKE_CASE')
        check(key not in reserved and not key.startswith('FIREBASE_'), f'{key} is generated; configure app, design or native.firebase instead')
        check(type(value) in (str, int, float, bool) and (not isinstance(value, float) or math.isfinite(value)), f'flutterDefines.{key} must be a scalar')
    return config, paths, firebase_data


def write(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding='utf-8')


def write_json(path, data):
    write(path, json.dumps(data, indent=2, ensure_ascii=False) + '\n')


def css_color(value):
    return value if len(value) == 7 else '#' + value[3:] + value[1:3]


def rgb(value):
    return '#' + value[-6:]


def js_json(value):
    return json.dumps(value, ensure_ascii=True).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')


def square_image(source, size, background=None, fraction=1):
    with Image.open(source) as opened:
        image = opened.convert('RGBA')
    image = ImageOps.contain(image, (round(size * fraction), round(size * fraction)), Image.Resampling.LANCZOS)
    result = Image.new('RGBA', (size, size), background or (0, 0, 0, 0))
    result.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
    return result.convert('RGB') if background else result


def save_image(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format='PNG', optimize=True)


def generate(config, paths, firebase_data, mobile=MOBILE):
    design = copy.deepcopy(config['design'])
    app, native = config['app'], config['native']
    bundle = mobile / 'assets/branding'
    bundle.mkdir(parents=True, exist_ok=True)
    # This folder is exclusively generated. Old customer assets must not ship.
    for old in bundle.iterdir():
        if old.is_file():
            old.unlink()
    for key in ASSETS & paths.keys():
        filename = key + '.png'
        # Flutter also receives a static first frame; animation is owned by
        # the configurable loader and therefore respects reduced motion.
        with Image.open(paths[key]) as asset_image:
            save_image(asset_image.convert('RGBA'), bundle / filename)
        design['assets'][key] = 'assets/branding/' + filename
    font_yaml = [FONT_BEGIN]
    for i, font in enumerate(config['fonts']):
        font_yaml.extend([f'    - family: {json.dumps(font["family"])}', '      fonts:'])
        for j, entry in enumerate(font['files']):
            filename = f'font_{i}_{j}' + paths[f'font_{i}_{j}'].suffix.lower()
            shutil.copyfile(paths[f'font_{i}_{j}'], bundle / filename)
            font_yaml.extend([f'        - asset: assets/branding/{filename}', f'          weight: {entry["weight"]}', f'          style: {entry["style"]}'])
    font_yaml.append(FONT_END)
    pubspec_path = mobile / 'pubspec.yaml'
    pubspec = pubspec_path.read_text()
    if '    - assets/branding/\n' not in pubspec:
        pubspec = pubspec.replace('    - assets/crypto/\n', '    - assets/crypto/\n    - assets/branding/\n')
    pubspec = re.sub(r'  # BEGIN GENERATED BRAND FONTS.*?  # END GENERATED BRAND FONTS\n?', '', pubspec, flags=re.S)
    write(pubspec_path, pubspec.rstrip() + '\n' + '\n'.join(font_yaml) + '\n')
    defines = {key: '' for key in ('FIREBASE_PROJECT_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_API_KEY', 'FIREBASE_ANDROID_API_KEY', 'FIREBASE_ANDROID_APP_ID', 'FIREBASE_IOS_API_KEY', 'FIREBASE_IOS_APP_ID', 'FIREBASE_IOS_BUNDLE_ID')}
    defines.update(firebase_data)
    defines.update(config['flutterDefines'])
    defines.update(APP_NAME=app['name'], APP_BRAND_ID=app['id'], APP_THEME_MODE=app['themeMode'], SUPPORT_EMAIL=app['supportEmail'], SUPPORT_PHONE=app['supportPhone'], LEGAL_ENTITY=app['legalEntity'], ACCOUNT_TRANSFER_DASHBOARD_URL=app['transferDashboardUrl'], APP_FONT_FAMILY=design['typography']['fontFamily'], APP_RADIUS_SCALE=str(design['shape']['radiusScale']), APP_LOGO_ASSET=design['assets']['logo'], APP_PRIMARY_COLOR=rgb(design['light']['fill'])[1:], APP_ACCENT_COLOR=rgb(design['light']['accent'])[1:], APP_DESIGN_JSON=json.dumps(design, separators=(',', ':')))
    write_json(mobile / '.dart_tool/branding/defines.json', defines)
    generate_android(mobile, native, app, design, paths)
    generate_ios(mobile, native, app, design, paths)
    generate_web(mobile, native, app, design, paths)
    return defines


def generate_android(mobile, native, app, design, paths):
    android = mobile / 'android/app'
    res = android / 'src/main/res'
    write(android / 'brand.properties', '# Generated by prepare-mobile-brand.py\napplicationId=' + native['androidApplicationId'] + '\n')
    label = escape(app['name']).replace("'", "\\'")
    write(res / 'values/brand.xml', f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="brand_app_name">{label}</string>\n</resources>\n')
    manifest = android / 'src/main/AndroidManifest.xml'
    write(manifest, re.sub(r'android:label="[^"]*"', 'android:label="@string/brand_app_name"', manifest.read_text(), count=1))
    gradle = android / 'build.gradle.kts'
    source = gradle.read_text().replace('    id("com.google.gms.google-services")\n', '')
    if 'val brandProperties' not in source:
        source = 'import java.util.Properties\n\n' + source
        source = source.replace('val playUploadStoreFile', 'val brandProperties = Properties().apply {\n    file("brand.properties").inputStream().use { load(it) }\n}\n// Firebase belongs to the selected customer only.\nif (file("google-services.json").exists()) {\n    apply(plugin = "com.google.gms.google-services")\n}\n\nval playUploadStoreFile', 1)
    source = re.sub(r'applicationId = [^\n]+', 'applicationId = brandProperties.getProperty("applicationId")', source)
    write(gradle, source)
    for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
        save_image(square_image(paths['icon'], round(48 * scale), rgb(native['iconBackground']), .8), res / f'mipmap-{density}/ic_launcher.png')
        save_image(square_image(paths['icon'], round(108 * scale), fraction=.55), res / f'mipmap-{density}/ic_launcher_foreground.png')
        for mode in ('light', 'dark'):
            actual_mode = mode if app['themeMode'] == 'system' else app['themeMode']
            source = paths.get('splash', paths.get('logoDark' if actual_mode == 'dark' else 'logo', paths['logo']))
            splash = square_image(source, round(96 * scale))
            if not design['splash']['enabled']:
                splash = Image.new('RGBA', splash.size)
            folder = f'drawable-night-{density}' if mode == 'dark' else f'drawable-{density}'
            save_image(splash, res / f'{folder}/brand_splash.png')
    for old in [res / 'drawable/example_mark.xml', res / 'drawable-v31/example_splash_icon.xml', res / 'drawable-v31/example_splash_mark.xml']:
        old.unlink(missing_ok=True)
    write(res / 'values/ic_launcher_background.xml', f'<resources><color name="ic_launcher_background">{rgb(native["iconBackground"])}</color></resources>\n')
    for mode, folder in [('Light', 'values'), ('Dark', 'values-night')]:
        actual_mode = mode if app['themeMode'] == 'system' else app['themeMode'].title()
        write(res / f'{folder}/colors.xml', f'<resources><color name="brand_launch_background">{rgb(design["splash"]["background" + actual_mode])}</color></resources>\n')
    launch = '<?xml version="1.0" encoding="utf-8"?>\n<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n    <item android:drawable="@color/brand_launch_background"/>\n    <item><bitmap android:gravity="center" android:src="@drawable/brand_splash"/></item>\n</layer-list>\n'
    for folder in ('drawable', 'drawable-v21'):
        write(res / f'{folder}/launch_background.xml', launch)
    for folder in ('values', 'values-night'):
        styles = res / f'{folder}/styles.xml'
        write(styles, styles.read_text().replace('?android:colorBackground', '@color/brand_launch_background'))
    write(res / 'values-v31/styles.xml', '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <style name="LaunchTheme" parent="@android:style/Theme.DeviceDefault.NoActionBar">\n        <item name="android:windowSplashScreenBackground">@color/brand_launch_background</item>\n        <item name="android:windowSplashScreenAnimatedIcon">@drawable/brand_splash_android12</item>\n        <item name="android:windowSplashScreenIconBackgroundColor">@color/brand_launch_background</item>\n        <item name="android:windowBackground">@drawable/launch_background</item>\n    </style>\n</resources>\n')
    for mode in ('light', 'dark'):
        actual_mode = mode if app['themeMode'] == 'system' else app['themeMode']
        source = paths.get('splash', paths.get('logoDark' if actual_mode == 'dark' else 'logo', paths['logo']))
        android12 = square_image(source, 1152, fraction=1 / 3)
        if not design['splash']['enabled']:
            android12 = Image.new('RGBA', android12.size)
        folder = 'drawable-night-xxxhdpi' if mode == 'dark' else 'drawable-xxxhdpi'
        save_image(android12, res / f'{folder}/brand_splash_android12.png')
    firebase_path = android / 'google-services.json'
    if 'firebase_android' in paths:
        shutil.copyfile(paths['firebase_android'], firebase_path)
    else:
        firebase_path.unlink(missing_ok=True)


def generate_ios(mobile, native, app, design, paths):
    ios = mobile / 'ios'
    runner = ios / 'Runner'
    write(ios / 'Flutter/Brand.xcconfig', '// Generated by prepare-mobile-brand.py\nBRAND_BUNDLE_ID = ' + native['iosBundleId'] + '\nBRAND_APP_NAME = ' + app['name'] + '\n')
    for name in ('Debug', 'Release'):
        xcconfig = ios / f'Flutter/{name}.xcconfig'
        source = xcconfig.read_text()
        if '#include "Brand.xcconfig"' not in source:
            write(xcconfig, source.rstrip() + '\n#include "Brand.xcconfig"\n')
    info_path = runner / 'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info['CFBundleDisplayName'] = '$(BRAND_APP_NAME)'
    info['CFBundleName'] = '$(BRAND_APP_NAME)'
    # App Store Connect export compliance: the app only uses exempt (HTTPS) encryption.
    info.setdefault('ITSAppUsesNonExemptEncryption', False)
    info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    pbx_path = ios / 'Runner.xcodeproj/project.pbxproj'
    pbx = pbx_path.read_text()
    pbx = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;', lambda m: 'PRODUCT_BUNDLE_IDENTIFIER = "' + (native['iosBundleId'] + '.RunnerTests' if 'RunnerTests' in m[0] else '$(BRAND_BUNDLE_ID)') + '";', pbx)
    pbx = '\n'.join(line for line in pbx.split('\n') if 'GoogleService-Info.plist' not in line)
    firebase_path = runner / 'GoogleService-Info.plist'
    if 'firebase_ios' in paths:
        shutil.copyfile(paths['firebase_ios'], firebase_path)
        pbx = pbx.replace('/* Begin PBXBuildFile section */', '/* Begin PBXBuildFile section */\n\t\tF1A100012F12345678900001 /* GoogleService-Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = F1A100022F12345678900002 /* GoogleService-Info.plist */; };')
        pbx = pbx.replace('/* Begin PBXFileReference section */', '/* Begin PBXFileReference section */\n\t\tF1A100022F12345678900002 /* GoogleService-Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "GoogleService-Info.plist"; sourceTree = "<group>"; };')
        pbx = pbx.replace('\t\t\t\t97C146FA1CF9000F007C117D /* Main.storyboard */,', '\t\t\t\tF1A100022F12345678900002 /* GoogleService-Info.plist */,\n\t\t\t\t97C146FA1CF9000F007C117D /* Main.storyboard */,')
        pbx = pbx.replace('\t\t\t\t97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,', '\t\t\t\tF1A100012F12345678900001 /* GoogleService-Info.plist in Resources */,\n\t\t\t\t97C147011CF9000F007C117D /* LaunchScreen.storyboard in Resources */,')
    else:
        firebase_path.unlink(missing_ok=True)
    write(pbx_path, pbx)
    icons = runner / 'Assets.xcassets/AppIcon.appiconset'
    contents = json.loads((icons / 'Contents.json').read_text())
    for item in contents['images']:
        size = round(float(item['size'].split('x')[0]) * float(item['scale'].rstrip('x')))
        save_image(square_image(paths['icon'], size, rgb(native['iconBackground']), .8), icons / item['filename'])
    launch = runner / 'Assets.xcassets/LaunchImage.imageset'
    images = []
    for scale in (1, 2, 3):
        for dark in (False, True):
            filename = ('LaunchImageDark' if dark else 'LaunchImage') + (f'@{scale}x' if scale > 1 else '') + '.png'
            actual_dark = dark if app['themeMode'] == 'system' else app['themeMode'] == 'dark'
            source = paths.get('splash', paths.get('logoDark' if actual_dark else 'logo', paths['logo']))
            splash = square_image(source, 96 * scale)
            if not design['splash']['enabled']:
                splash = Image.new('RGBA', splash.size)
            save_image(splash, launch / filename)
            entry = {'idiom': 'universal', 'filename': filename, 'scale': f'{scale}x'}
            if dark:
                entry['appearances'] = [{'appearance': 'luminosity', 'value': 'dark'}]
            images.append(entry)
    write_json(launch / 'Contents.json', {'images': images, 'info': {'version': 1, 'author': 'xcode'}})
    colors = []
    for mode in ('Light', 'Dark'):
        actual_mode = mode if app['themeMode'] == 'system' else app['themeMode'].title()
        value = rgb(design['splash']['background' + actual_mode])[1:]
        components = {key: str(int(value[index:index + 2], 16) / 255) for index, key in [(0, 'red'), (2, 'green'), (4, 'blue')]}
        entry = {'idiom': 'universal', 'color': {'color-space': 'srgb', 'components': dict(components, alpha='1.000')}}
        if mode == 'Dark':
            entry['appearances'] = [{'appearance': 'luminosity', 'value': 'dark'}]
        colors.append(entry)
    write_json(runner / 'Assets.xcassets/BrandBackground.colorset/Contents.json', {'colors': colors, 'info': {'version': 1, 'author': 'xcode'}})
    storyboard = runner / 'Base.lproj/LaunchScreen.storyboard'
    source = re.sub(r'<color key="backgroundColor"[^>]*/>', '<color key="backgroundColor" name="BrandBackground"/>', storyboard.read_text())
    source = re.sub(r'\s*<namedColor name="BrandBackground">.*?</namedColor>', '', source, flags=re.S)
    source = source.replace('<resources>', '<resources>\n        <namedColor name="BrandBackground"><color red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/></namedColor>')
    write(storyboard, source)


def generate_web(mobile, native, app, design, paths):
    web = mobile / 'web'
    folder = web / 'branding'
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.iterdir():
        if old.is_file():
            old.unlink()
    for key, fallback in [('logo', 'logo'), ('logoDark', 'logo'), ('splash', 'logo'), ('loader', 'logo'), ('loaderDark', 'logo')]:
        source = (paths.get('loader', paths.get('logoDark', paths['logo'])) if key == 'loaderDark' else paths.get(key, paths[fallback]))
        # PNG makes image use independent from source encoding and metadata.
        with Image.open(source) as source_image:
            save_image(source_image.convert('RGBA'), folder / f'{key}.png')
    for name, size in [('Icon-192', 192), ('Icon-512', 512), ('Icon-maskable-192', 192), ('Icon-maskable-512', 512), ('apple-touch-icon', 180)]:
        fraction = .6 if 'maskable' in name else .8
        save_image(square_image(paths['icon'], size, rgb(native['iconBackground']), fraction), web / f'icons/{name}.png')
    save_image(square_image(paths['icon'], 48, rgb(native['iconBackground']), .8), web / 'favicon.png')
    splash = design['splash']
    mode = 'Light' if app['themeMode'] == 'light' else 'Dark'
    manifest = {'name': app['name'], 'short_name': app['name'], 'id': './', 'start_url': '.', 'display': 'standalone', 'background_color': rgb(splash['background' + mode]), 'theme_color': rgb(splash['background' + mode]), 'description': app['description'], 'orientation': 'portrait-primary', 'prefer_related_applications': False, 'categories': ['finance', 'business'], 'icons': [{'src': f'icons/{name}.png', 'sizes': f'{size}x{size}', 'type': 'image/png', **({'purpose': 'maskable'} if 'maskable' in name else {})} for name, size in [('Icon-192', 192), ('Icon-512', 512), ('Icon-maskable-192', 192), ('Icon-maskable-512', 512)]]}
    write_json(web / 'manifest.json', manifest)
    root_css = []
    for palette_mode in ('light', 'dark'):
        palette = design[palette_mode]
        font_family = json.dumps(design['typography']['fontFamily']) + ', ' if design['typography']['fontFamily'] else ''
        root_css.append(f'html[data-brand-theme="{palette_mode}"] {{ color-scheme: {palette_mode}; --brand-background: {css_color(splash["background" + palette_mode.title()])}; --brand-ink: {css_color(palette["ink"])}; --brand-fill: {css_color(palette["fill"])}; --brand-on-fill: {css_color(palette["onFill"])}; --brand-loader: {css_color(palette.get("loader", palette["fill"]))}; --brand-font: {font_family}system-ui, sans-serif; }}')
    font_css = []
    for i, font in enumerate(config_fonts_from_design_context(mobile)):
        font_css.append(font)
    # The loading shell uses only local assets. Native launch screens are static.
    template = (ROOT / 'scripts/branding/index.template.html').read_text()
    duration = round(design['loader']['durationMs'] * design['motion']['durationScale'])
    loader_class = 'loader-circular' if design['loader']['style'] == 'circular' else 'loader-logo'
    if not design['motion']['enabled']:
        loader_class += ' no-motion'
    values = {'APP_NAME': html.escape(app['name']), 'DESCRIPTION': html.escape(app['description'], quote=True), 'BOOT_CONFIG': js_json({'name': app['name'], 'id': app['id'], 'theme': app['themeMode'], 'backgroundLight': rgb(splash['backgroundLight']), 'backgroundDark': rgb(splash['backgroundDark'])}), 'THEME_COLOR': rgb(splash['background' + mode]), 'ROOT_CSS': '\n    '.join(root_css + font_css), 'DURATION': str(max(1, duration)), 'LOADER_CLASS': loader_class, 'SPLASH_STYLE': '' if splash['enabled'] else 'display:none;', 'LOGO_SRC': 'branding/splash.png' if 'splash' in paths else 'branding/logo.png', 'LOGO_DARK_SRC': 'branding/splash.png' if 'splash' in paths else 'branding/logoDark.png'}
    for key, value in values.items():
        template = template.replace('@@' + key + '@@', value)
    write(web / 'index.html', template)
    recovery = web / 'app_recovery.js'
    source = recovery.read_text().replace('background:#171333;color:#fff;', 'background:var(--brand-background);color:var(--brand-ink);').replace('font:16px system-ui;', 'font:16px var(--brand-font,system-ui);').replace('background:#7b6cf6;color:white;', 'background:var(--brand-fill);color:var(--brand-on-fill);')
    write(recovery, source)


def config_fonts_from_design_context(mobile):
    # Generated pubspec is also the authoritative font list. Web splash uses
    # the Flutter-bundled font URLs, so there is only one font payload.
    source = (mobile / 'pubspec.yaml').read_text()
    family = None
    asset = None
    entries = []
    for line in source.splitlines() + ['  # End']:
        match = re.match(r'    - family: (.+)', line)
        if match:
            family = match[1].strip('"')
        match = re.match(r'        - asset: (.+)', line)
        if match:
            asset = match[1]
        match = re.match(r'          weight: (.+)', line)
        if match and family and asset:
            entries.append('@font-face { font-family: ' + json.dumps(family) + '; src: url("assets/' + asset + '"); font-weight: ' + match[1] + '; font-display: swap; }')
        match = re.match(r'          style: (.+)', line)
        if match and entries:
            entries[-1] = entries[-1][:-2] + 'font-style: ' + match[1] + '; }'
    return entries


def finalize_web(directory):
    check(directory.is_dir(), f'Web build directory does not exist: {directory}')
    worker = directory / 'example_service_worker.js'
    check(worker.is_file(), 'Web build does not contain example_service_worker.js')
    digest = hashlib.sha256()
    # Cache changes with deployed content, even if only application code changes.
    for path in sorted(directory.rglob('*')):
        if path.is_file() and path != worker:
            digest.update(path.relative_to(directory).as_posix().encode())
            digest.update(path.read_bytes())
    source = re.sub(r"const CACHE_NAME = '[^']+';", f"const CACHE_NAME = 'example-app-{digest.hexdigest()[:20]}';", worker.read_text())
    shell_extras = ["  './app_bridges.js',"] + [f"  './{path.relative_to(directory).as_posix()}'," for path in sorted((directory / 'branding').glob('*')) if path.is_file()]
    source = re.sub(r'\n  // BEGIN GENERATED BRAND CACHE.*?  // END GENERATED BRAND CACHE', '', source, flags=re.S)
    source = source.replace('const APP_SHELL = [', 'const APP_SHELL = [\n  // BEGIN GENERATED BRAND CACHE\n' + '\n'.join(shell_extras) + '\n  // END GENERATED BRAND CACHE')
    write(worker, source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', nargs='?', type=Path)
    parser.add_argument('--check', action='store_true', help='Validate only; do not change files')
    parser.add_argument('--finalize-web', type=Path, help='Version the service worker after a Flutter web build')
    args = parser.parse_args()
    try:
        if args.finalize_web:
            finalize_web(args.finalize_web.resolve())
            return 0
        check(args.config is not None, 'A brand configuration file is required')
        config, paths, firebase_data = load_config(args.config.resolve())
        if not args.check:
            generate(config, paths, firebase_data)
        print(('Validated' if args.check else 'Prepared') + f' {config["app"]["name"]}: {config["native"]["androidApplicationId"]} / {config["native"]["iosBundleId"]}')
        return 0
    except (ConfigError, OSError) as error:
        print(f'Brand configuration error: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
