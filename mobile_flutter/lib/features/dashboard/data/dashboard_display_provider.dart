import '../../../core/api/auth_token_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/display_snapshot.dart';
import '../../../core/cache/display_snapshot_codecs.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_providers.dart';

final dashboardDisplayProvider = StateNotifierProvider<
        DisplaySnapshotController<HoppaDashboardSnapshot>,
        DisplaySnapshot<HoppaDashboardSnapshot>>(
    (ref) => watchDisplaySnapshot(
          ref,
          source: hoppaDashboardProvider,
          name: 'home',
          encode: encodeHoppaDashboardSnapshot,
          decode: decodeHoppaDashboardSnapshot,
        ),
    dependencies: [
      hoppaDashboardProvider,
      displaySnapshotStorageProvider,
      displayCacheOwnerProvider,
      authSessionGenerationProvider,
      authTokenProvider,
    ]);
