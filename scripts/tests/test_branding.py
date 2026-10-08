"""Brand configuration and generated platform assets, without Flutter tooling.

Run from the repository root: python3 -m unittest discover -s scripts/tests -v
Every generated file is confined to a temporary copy of the mobile project.
"""
from __future__ import annotations

import copy
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
MOBILE = ROOT / "mobile_flutter"
SPEC = importlib.util.spec_from_file_location(
    "prepare_mobile_brand", ROOT / "scripts/prepare-mobile-brand.py"
)
assert SPEC is not None and SPEC.loader is not None
branding = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(branding)
UNSET = object()


class VisibleHTML(HTMLParser):
    """Read displayed/accessibility text while preserving internal JS names."""
    def __init__(self):
        super().__init__()
        self.hidden = 0
        self.text = []

    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script"):
            self.hidden += 1
        for name, value in attrs:
            if value is not None and (name in ("aria-label", "alt", "title") or (tag == "meta" and name == "content")):
                self.text.append(value)

    def handle_endtag(self, tag):
        if tag in ("style", "script"):
            self.hidden -= 1

    def handle_data(self, data):
        if not self.hidden:
            self.text.append(data)


class BrandFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="brand-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.brand_dir = self.root / "customer"
        self.brand_dir.mkdir()
        self.config_path = self.brand_dir / "brand.json"
        for filename, shade in (("logo.png", "#274777"), ("dark.png", "#DDDDDD"),
                                ("splash.png", "#775533"), ("loader.png", "#331177"),
                                ("icon.png", "#557722")):
            Image.new("RGBA", (80, 60), shade).save(self.brand_dir / filename)
        palette = {role: "#102030" for role in branding.PALETTE}
        self.config = {
            "schemaVersion": 1,
            "app": {
                "name": "Copper Wallet",
                "id": "copper",
                "description": "Payments & transfers",
                "supportEmail": "support@example.test",
                "supportPhone": "+1234567890",
                "legalEntity": "Copper Example Ltd",
                "themeMode": "system",
                "transferDashboardUrl": "https://example.test/transfers",
            },
            "design": {
                "layout": "generic",
                "light": dict(palette, paper="#F7F8F9", fill="#223344", accent="#445566"),
                "dark": dict(palette, paper="#101112"),
                "typography": {"fontFamily": "Geist", "monoFontFamily": "GeistMono", "scale": 1},
                "shape": {"radiusScale": 1},
                "assets": {"logo": "logo.png", "logoDark": "dark.png", "splash": "splash.png", "loader": "loader.png"},
                "loader": {"style": "logo", "durationMs": 1200},
                "splash": {"enabled": True, "backgroundLight": "#F7F8F9", "backgroundDark": "#101112", "minimumDurationMs": 700, "maximumDurationMs": 12000},
                "motion": {"enabled": True, "durationScale": 1},
            },
            "native": {
                "androidApplicationId": "com.example.copper",
                "iosBundleId": "com.example.copper",
                "icon": "icon.png",
                "iconBackground": "#FFFFFF",
                "firebase": {},
            },
            "fonts": [],
            "flutterDefines": {"API_BASE_URL": "https://api.example.test", "DEMO_MODE": True},
        }

    def load(self, config=UNSET):
        self.config_path.write_text(json.dumps(self.config if config is UNSET else config), encoding="utf-8")
        return branding.load_config(self.config_path)

    def changed(self, path, value):
        result = copy.deepcopy(self.config)
        parent = result
        keys = path.split(".")
        for key in keys[:-1]:
            parent = parent[key]
        parent[keys[-1]] = value
        return result

    def reject(self, path, value):
        with self.subTest(path=path, value=value):
            with self.assertRaises(branding.ConfigError):
                self.load(self.changed(path, value))

    def mobile_copy(self):
        mobile = self.root / "mobile_flutter"
        mobile.mkdir()
        for name in ("android", "ios", "web", "assets"):
            shutil.copytree(MOBILE / name, mobile / name,
                            ignore=shutil.ignore_patterns("build", ".dart_tool", ".gradle", "Pods", ".symlinks", "ephemeral", "*.xcworkspace", "xcuserdata"))
        shutil.copyfile(MOBILE / "pubspec.yaml", mobile / "pubspec.yaml")
        return mobile

    def firebase_files(self, android_id="com.example.copper", ios_id="com.example.copper"):
        android = {
            "project_info": {"project_id": "example-project", "project_number": "123456789"},
            "client": [{
                "client_info": {"mobilesdk_app_id": "1:123456789:android:example", "android_client_info": {"package_name": android_id}},
                "api_key": [{"current_key": "test-android-key"}],
            }],
        }
        ios = {"BUNDLE_ID": ios_id, "PROJECT_ID": "example-project", "GCM_SENDER_ID": "123456789", "GOOGLE_APP_ID": "1:123456789:ios:example", "API_KEY": "test-ios-key"}
        (self.brand_dir / "google-services.json").write_text(json.dumps(android))
        (self.brand_dir / "GoogleService-Info.plist").write_bytes(plistlib.dumps(ios))
        self.config["native"]["firebase"] = {"android": "google-services.json", "ios": "GoogleService-Info.plist"}


class ValidationTests(BrandFixture):
    def test_complete_configuration_and_sample_are_valid(self):
        config, paths, firebase = self.load()
        self.assertEqual(config["app"]["themeMode"], "system")
        self.assertEqual(paths["logo"], (self.brand_dir / "logo.png").resolve())
        self.assertEqual(firebase, {})
        sample, _, _ = branding.load_config(MOBILE / "config/sample.json")
        self.assertNotIn("example", sample["app"]["name"].lower())
        self.assertNotIn("example", sample["native"]["androidApplicationId"].lower())

    def test_malformed_json_and_missing_config(self):
        for raw in ('{"schemaVersion":', '{"value": NaN}', '{"value": Infinity}', '{"value": -Infinity}'):
            with self.subTest(raw=raw):
                self.config_path.write_text(raw)
                with self.assertRaises(branding.ConfigError):
                    branding.load_config(self.config_path)
        with self.assertRaises(branding.ConfigError):
            branding.load_config(self.brand_dir / "absent.json")

    def test_schema_and_object_types(self):
        for value in ([], None, "brand", 1):
            with self.subTest(value=value):
                with self.assertRaises(branding.ConfigError):
                    self.load(value)
        for path, value in (("schemaVersion", True), ("schemaVersion", 2), ("schemaVersion", "1"),
                            ("app", []), ("design", None), ("native", "app"), ("fonts", {}),
                            ("flutterDefines", []), ("design.light", []), ("design.assets", []),
                            ("design.typography", 1), ("native.firebase", [])):
            self.reject(path, value)

    def test_unknown_fields_and_missing_required_palette_role(self):
        self.reject("app.unknown", "x")
        self.reject("design.unknown", {})
        self.reject("native.unknown", "x")
        for mode in ("light", "dark"):
            config = copy.deepcopy(self.config)
            del config["design"][mode]["accent"]
            with self.subTest(mode=mode), self.assertRaises(branding.ConfigError):
                self.load(config)

    def test_invalid_enums(self):
        for path, values in {
            "app.themeMode": ("auto", "", False),
            "design.layout": ("unknown", 1),
            "design.loader.style": ("spin", None),
        }.items():
            for value in values:
                self.reject(path, value)

    def test_invalid_colors_and_alpha_on_native_background(self):
        for value in ("red", "#FFF", "102030", "#GG1122", "#1234567", 123, None):
            self.reject("design.light.fill", value)
        self.reject("design.splash.backgroundLight", "#00123456")
        self.reject("native.iconBackground", "#99123456")
        config = self.changed("design.light.glassTop", "#66123456")
        self.load(config)

    def test_numeric_types_ranges_and_duration_order(self):
        limits = {
            "design.typography.scale": (0.8, 1.3),
            "design.shape.radiusScale": (0.65, 1.4),
            "design.loader.durationMs": (100, 10000),
            "design.splash.minimumDurationMs": (0, 10000),
            "design.splash.maximumDurationMs": (0, 30000),
            "design.motion.durationScale": (0.25, 3),
        }
        for path, (low, high) in limits.items():
            for value in (low - 1, high + 1, True, "1", None, float("inf")):
                self.reject(path, value)
        for path in ("design.loader.durationMs", "design.splash.minimumDurationMs", "design.splash.maximumDurationMs"):
            self.reject(path, 500.5)
        self.reject("design.splash.minimumDurationMs", 10001)
        self.reject("design.splash.maximumDurationMs", 699)
        self.reject("design.splash.enabled", 1)
        self.reject("design.motion.enabled", "true")

    def test_native_identifiers_and_app_strings(self):
        for path in ("native.androidApplicationId", "native.iosBundleId"):
            for value in ("single", "com..example", "com.example/other", "", None):
                self.reject(path, value)
        for value in ("", "UPPER", "bad id", "a", "x" * 65):
            self.reject("app.id", value)
        for value in ("", "bad\nname", 'bad"name', "$(injection)", "x" * 61):
            self.reject("app.name", value)

    def test_missing_invalid_and_unsupported_images(self):
        self.reject("design.assets.logo", "missing.png")
        self.reject("native.icon", "missing.png")
        (self.brand_dir / "broken.png").write_text("not a PNG")
        self.reject("design.assets.logo", "broken.png")
        (self.brand_dir / "vector.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        self.reject("design.assets.logo", "vector.svg")
        config = copy.deepcopy(self.config)
        del config["design"]["assets"]["logo"]
        with self.assertRaises(branding.ConfigError):
            self.load(config)

    def test_asset_paths_cannot_escape_configuration_directory(self):
        outside = self.root / "outside.png"
        Image.new("RGB", (4, 4)).save(outside)
        (self.brand_dir / "escape.png").symlink_to(outside)
        for value in ("../outside.png", str(outside), "escape.png", "..\\outside.png"):
            self.reject("design.assets.logo", value)
            self.reject("native.icon", value)

    def test_firebase_id_mismatch_rejected_on_both_platforms(self):
        for platform in ("android", "ios"):
            with self.subTest(platform=platform):
                self.firebase_files(android_id="com.other.customer" if platform == "android" else "com.example.copper",
                                    ios_id="com.other.customer" if platform == "ios" else "com.example.copper")
                with self.assertRaises(branding.ConfigError):
                    self.load()

    def test_firebase_files_must_share_project(self):
        self.firebase_files()
        path = self.brand_dir / "GoogleService-Info.plist"
        data = plistlib.loads(path.read_bytes())
        data["PROJECT_ID"] = "another-project"
        path.write_bytes(plistlib.dumps(data))
        with self.assertRaises(branding.ConfigError):
            self.load()

    def test_firebase_valid_identifiers_produce_explicit_defines(self):
        self.firebase_files()
        _, paths, defines = self.load()
        self.assertIn("firebase_android", paths)
        self.assertIn("firebase_ios", paths)
        self.assertEqual(defines["FIREBASE_PROJECT_ID"], "example-project")
        self.assertEqual(defines["FIREBASE_IOS_BUNDLE_ID"], "com.example.copper")

    def test_font_declarations_and_reserved_defines(self):
        shutil.copyfile(MOBILE / "assets/fonts/Geist-Regular.ttf", self.brand_dir / "custom.ttf")
        self.config["fonts"] = [{"family": "Custom Sans", "files": [{"path": "custom.ttf", "weight": 400, "style": "normal"}]}]
        for value in ("Geist", "bad: family", ""):
            config = copy.deepcopy(self.config)
            config["fonts"][0]["family"] = value
            with self.subTest(family=value), self.assertRaises(branding.ConfigError):
                self.load(config)
        for field, values in {"weight": (50, 1000, 450, True, 400.5), "style": ("bold", 1), "path": ("absent.ttf", "../custom.ttf")}.items():
            for value in values:
                config = copy.deepcopy(self.config)
                config["fonts"][0]["files"][0][field] = value
                with self.subTest(field=field, value=value), self.assertRaises(branding.ConfigError):
                    self.load(config)
        self.reject("design.typography.fontFamily", "Undeclared Family")
        for key in ("APP_NAME", "APP_DESIGN_JSON", "FIREBASE_PROJECT_ID", "lower_case"):
            self.reject("flutterDefines." + key, "override")
        self.reject("flutterDefines.COMPLEX_VALUE", {"nested": True})


class GenerationTests(BrandFixture):
    def generate(self, mobile=None):
        mobile = mobile or self.mobile_copy()
        config, paths, firebase = self.load()
        defines = branding.generate(config, paths, firebase, mobile=mobile)
        return mobile, defines

    def test_native_identity_icons_and_no_inherited_firebase(self):
        mobile = self.mobile_copy()
        (mobile / "android/app/google-services.json").write_text('{"old":true}')
        (mobile / "ios/Runner/GoogleService-Info.plist").write_bytes(plistlib.dumps({"OLD": True}))
        mobile, _ = self.generate(mobile)
        self.assertIn("applicationId=com.example.copper", (mobile / "android/app/brand.properties").read_text())
        gradle = (mobile / "android/app/build.gradle.kts").read_text()
        self.assertIn('applicationId = brandProperties.getProperty("applicationId")', gradle)
        self.assertIn('if (file("google-services.json").exists())', gradle)
        self.assertIn("Copper Wallet", (mobile / "android/app/src/main/res/values/brand.xml").read_text())
        self.assertIn('android:label="@string/brand_app_name"', (mobile / "android/app/src/main/AndroidManifest.xml").read_text())
        self.assertIn("BRAND_BUNDLE_ID = com.example.copper", (mobile / "ios/Flutter/Brand.xcconfig").read_text())
        info = plistlib.loads((mobile / "ios/Runner/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDisplayName"], "$(BRAND_APP_NAME)")
        self.assertIs(info["ITSAppUsesNonExemptEncryption"], False)
        pbx = (mobile / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = "$(BRAND_BUNDLE_ID)"', pbx)
        self.assertNotIn("GoogleService-Info.plist", pbx)
        self.assertFalse((mobile / "android/app/google-services.json").exists())
        self.assertFalse((mobile / "ios/Runner/GoogleService-Info.plist").exists())
        for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
            with Image.open(mobile / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png") as icon:
                self.assertEqual(icon.size, (size, size))
                self.assertEqual(icon.mode, "RGB")
        with Image.open(mobile / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png") as icon:
            self.assertEqual(icon.size, (1024, 1024))
            self.assertEqual(icon.mode, "RGB")

    def test_runtime_defines_and_assets_are_rewritten_for_flutter_bundle(self):
        mobile, defines = self.generate()
        stored = json.loads((mobile / ".dart_tool/branding/defines.json").read_text())
        self.assertEqual(defines, stored)
        self.assertEqual(stored["APP_NAME"], "Copper Wallet")
        self.assertEqual(stored["APP_THEME_MODE"], "system")
        self.assertEqual(stored["API_BASE_URL"], "https://api.example.test")
        self.assertEqual(stored["APP_LOGO_ASSET"], "assets/branding/logo.png")
        design = json.loads(stored["APP_DESIGN_JSON"])
        for key, filename in design["assets"].items():
            self.assertTrue(filename.startswith("assets/branding/"), key)
            self.assertTrue((mobile / filename).is_file(), key)
        self.assertNotIn(str(self.brand_dir), stored["APP_DESIGN_JSON"])
        self.assertTrue(all(value == "" for key, value in stored.items() if key.startswith("FIREBASE_")))
        self.assertEqual((mobile / "pubspec.yaml").read_text().count("    - assets/branding/"), 1)

    def test_sample_generates_without_customer_visible_example_branding(self):
        mobile = self.mobile_copy()
        config, paths, firebase = branding.load_config(MOBILE / "config/sample.json")
        branding.generate(config, paths, firebase, mobile=mobile)
        manifest = json.loads((mobile / "web/manifest.json").read_text())
        self.assertEqual(manifest["name"], config["app"]["name"])
        for name in ("web/index.html", "web/manifest.json", "android/app/src/main/res/values/brand.xml", "ios/Flutter/Brand.xcconfig", "ios/Runner/Info.plist", "ios/Runner/Base.lproj/LaunchScreen.storyboard"):
            source = (mobile / name).read_text()
            if name.endswith(".html"):
                parser = VisibleHTML()
                parser.feed(source)
                visible = " ".join(parser.text)
            else:
                visible = source
            with self.subTest(file=name):
                self.assertNotIn("example", visible.lower())
        self.assertFalse((mobile / "android/app/src/main/res/drawable/example_mark.xml").exists())
        for name, size in (("Icon-192", 192), ("Icon-512", 512), ("apple-touch-icon", 180)):
            with Image.open(mobile / f"web/icons/{name}.png") as icon:
                self.assertEqual(icon.size, (size, size))
        self.assertNotRegex((mobile / "web/index.html").read_text(), r"@@[A-Z_]+@@")

    def test_custom_fonts_packaged_and_stale_customer_assets_removed(self):
        shutil.copyfile(MOBILE / "assets/fonts/Geist-Regular.ttf", self.brand_dir / "custom.ttf")
        self.config["fonts"] = [{"family": "Custom Sans", "files": [{"path": "custom.ttf", "weight": 400, "style": "italic"}]}]
        self.config["design"]["typography"]["fontFamily"] = "Custom Sans"
        mobile = self.mobile_copy()
        folder = mobile / "assets/branding"
        folder.mkdir(exist_ok=True)
        (folder / "previous-customer.png").write_bytes(b"old customer logo")
        mobile, defines = self.generate(mobile)
        self.assertFalse((folder / "previous-customer.png").exists())
        self.assertEqual((folder / "font_0_0.ttf").read_bytes(), (self.brand_dir / "custom.ttf").read_bytes())
        pubspec = (mobile / "pubspec.yaml").read_text()
        self.assertIn('family: "Custom Sans"', pubspec)
        self.assertIn("asset: assets/branding/font_0_0.ttf", pubspec)
        self.assertIn("style: italic", pubspec)
        self.assertEqual(defines["APP_FONT_FAMILY"], "Custom Sans")
        shell = (mobile / "web/index.html").read_text()
        self.assertIn("@font-face", shell)
        self.assertIn("assets/assets/branding/font_0_0.ttf", shell)

    def test_disabled_splash_generates_transparent_native_launch_images(self):
        self.config["design"]["splash"]["enabled"] = False
        mobile, _ = self.generate()
        for name in ("android/app/src/main/res/drawable-mdpi/brand_splash.png", "android/app/src/main/res/drawable-xxxhdpi/brand_splash_android12.png", "ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png"):
            with self.subTest(file=name), Image.open(mobile / name) as image:
                self.assertEqual(image.getchannel("A").getextrema(), (0, 0))
        self.assertIn("display:none;", (mobile / "web/index.html").read_text())

    def test_forced_light_mode_applies_to_native_dark_appearance(self):
        self.config["app"]["themeMode"] = "light"
        mobile, defines = self.generate()
        self.assertEqual(defines["APP_THEME_MODE"], "light")
        self.assertIn("#F7F8F9", (mobile / "android/app/src/main/res/values-night/colors.xml").read_text())
        colors = json.loads((mobile / "ios/Runner/Assets.xcassets/BrandBackground.colorset/Contents.json").read_text())["colors"]
        self.assertEqual(colors[0]["color"], colors[1]["color"])
        manifest = json.loads((mobile / "web/manifest.json").read_text())
        self.assertEqual(manifest["background_color"], "#F7F8F9")

    def test_generation_is_idempotent(self):
        mobile, _ = self.generate()
        def snapshot():
            return {path.relative_to(mobile).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in mobile.rglob("*") if path.is_file()}
        before = snapshot()
        self.generate(mobile)
        self.assertEqual(before, snapshot())

    def test_firebase_files_install_and_can_be_removed_by_next_brand(self):
        self.firebase_files()
        mobile, defines = self.generate()
        self.assertEqual(defines["FIREBASE_ANDROID_API_KEY"], "test-android-key")
        self.assertTrue((mobile / "android/app/google-services.json").is_file())
        self.assertTrue((mobile / "ios/Runner/GoogleService-Info.plist").is_file())
        self.assertIn("GoogleService-Info.plist in Resources", (mobile / "ios/Runner.xcodeproj/project.pbxproj").read_text())
        self.config["native"]["firebase"] = {}
        _, defines = self.generate(mobile)
        self.assertEqual(defines["FIREBASE_ANDROID_API_KEY"], "")
        self.assertFalse((mobile / "ios/Runner/GoogleService-Info.plist").exists())


class WebFinalizationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="brand-web-tests-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        shutil.copyfile(MOBILE / "web/example_service_worker.js", self.directory / "example_service_worker.js")
        (self.directory / "branding").mkdir()
        (self.directory / "branding/logo.png").write_bytes(b"logo content")
        (self.directory / "index.html").write_text("<title>Example</title>")
        (self.directory / "app_bridges.js").write_text("window.example = true;")
        (self.directory / "main.dart.js").write_text("console.log('v1');")

    def worker(self):
        return (self.directory / "example_service_worker.js").read_text()

    def cache_name(self):
        return re.search(r"const CACHE_NAME = '([^']+)';", self.worker()).group(1)

    def test_version_tracks_application_and_brand_assets(self):
        branding.finalize_web(self.directory)
        first = self.cache_name()
        self.assertRegex(first, r"example-app-[a-f0-9]{20}")
        self.assertIn("'./branding/logo.png'", self.worker())
        self.assertIn("'./app_bridges.js'", self.worker())
        (self.directory / "main.dart.js").write_text("console.log('v2');")
        branding.finalize_web(self.directory)
        second = self.cache_name()
        self.assertNotEqual(first, second)
        (self.directory / "branding/logo.png").write_bytes(b"new logo")
        branding.finalize_web(self.directory)
        self.assertNotEqual(second, self.cache_name())

    def test_finalization_is_idempotent(self):
        branding.finalize_web(self.directory)
        first = self.worker()
        branding.finalize_web(self.directory)
        self.assertEqual(first, self.worker())
        self.assertEqual(self.worker().count("'./branding/logo.png'"), 1)
        self.assertEqual(self.worker().count("'./app_bridges.js'"), 1)

    def test_missing_web_build_or_worker_is_rejected(self):
        with self.assertRaises(branding.ConfigError):
            branding.finalize_web(self.directory / "missing")
        (self.directory / "example_service_worker.js").unlink()
        with self.assertRaises(branding.ConfigError):
            branding.finalize_web(self.directory)


if __name__ == "__main__":
    unittest.main()
