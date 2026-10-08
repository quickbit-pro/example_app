import '../../../core/api/auth_token_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/display_snapshot.dart';
import '../../../core/cache/display_snapshot_codecs.dart';
import '../../../core/models/banking_models.dart';
import '../../banking/application/banking_providers.dart';

typedef ActivityDisplayScope = ({String accountId, String cardId});

final activityDisplayProvider = StateNotifierProvider.family<
        DisplaySnapshotController<List<LedgerTransaction>>,
        DisplaySnapshot<List<LedgerTransaction>>,
        ActivityDisplayScope>(
    (ref, scope) => watchDisplaySnapshot(
          ref,
          source: scope.cardId.isNotEmpty
              ? activityCardTransactionsProvider(scope.cardId)
              : scope.accountId.isNotEmpty
                  ? activityAccountTransactionsProvider(scope.accountId)
                  : activityTransactionsProvider,
          name:
              'activity:${Uri.encodeComponent(scope.accountId)}:${Uri.encodeComponent(scope.cardId)}',
          encode: encodeActivity,
          decode: decodeActivity,
        ),
    dependencies: [
      activityTransactionsProvider,
      activityAccountTransactionsProvider,
      activityCardTransactionsProvider,
      displaySnapshotStorageProvider,
      displayCacheOwnerProvider,
      authSessionGenerationProvider,
      authTokenProvider,
    ]);
