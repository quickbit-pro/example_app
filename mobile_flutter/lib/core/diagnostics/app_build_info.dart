import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'client_environment.dart';

class AppBuildInfo {
  const AppBuildInfo(
      {required this.version, this.buildNumber = '', this.revision = ''});

  static const compiled = AppBuildInfo(
    version: String.fromEnvironment('APP_VERSION'),
    buildNumber: String.fromEnvironment('APP_BUILD_NUMBER'),
    revision: String.fromEnvironment('APP_BUILD_REVISION'),
  );

  final String version;
  final String buildNumber;
  final String revision;

  String get label {
    final name = version.isEmpty ? 'Version unavailable' : 'v$version';
    final build = buildNumber.isEmpty ? '' : '+$buildNumber';
    final source = revision.isEmpty ? '' : ' · $revision';
    return '$name$build$source';
  }
}

final appBuildInfoProvider = FutureProvider<AppBuildInfo>((ref) async {
  // Release builders embed these values in the executable. An older cached
  // web app must never borrow the newest release's version.json information.
  if (AppBuildInfo.compiled.version.isNotEmpty) return AppBuildInfo.compiled;
  try {
    final info = await PackageInfo.fromPlatform();
    return AppBuildInfo(
        version: info.version,
        buildNumber: info.buildNumber,
        revision: AppBuildInfo.compiled.revision);
  } catch (_) {
    return AppBuildInfo.compiled;
  }
});

final clientEnvironmentProvider =
    Provider<String>((ref) => currentClientEnvironment());
