import '../../../core/models/banking_models.dart';

/// A failed attempt remains in Activity, but its amount did not move. Numeric
/// provider states are deliberately not guessed across different products.
bool transactionHasFailed(LedgerTransaction transaction) => const {
      'failed',
      // Hoppa's card ledger says "fail" for a declined purchase.
      'fail',
      'declined',
      'rejected',
      'cancelled',
      'canceled',
      'reverted',
    }.contains(_normalized(transaction.status.isEmpty
        ? transaction.subtitle
        : transaction.status));

/// True only when the API identifies a conversion or movement between the
/// customer's own balances. These remain in Activity, but do not represent
/// money entering or leaving the customer's total holdings.
bool transactionIsInternalMovement(LedgerTransaction transaction) {
  final type = _normalized(transaction.rawType);
  // A conversion/funding fee is an actual cost, even when its metadata points
  // to the internal operation that incurred it. Transfers to another member
  // or to the programme master are also external to this customer's holdings.
  if (transaction.type == TransactionType.fee ||
      type.contains('fee') ||
      _externalTransferTypes.contains(type)) {
    return false;
  }
  if (_internalMovementTypes.contains(type)) return true;
  return _hasInternalOperation(transaction.metadata);
}

bool _hasInternalOperation(Object? value) {
  if (value is Map) {
    // Hoppa's Equals FX ledger legs are typed deposit/withdrawal, with
    // source=exchange alongside provider=equalsmoney. Source alone is not
    // enough: a deposit from an external exchange can be a real inflow.
    final fields = {
      for (final entry in value.entries)
        _normalized(entry.key.toString()): entry.value,
    };
    if (_normalized(fields['provider']?.toString() ?? '') == 'equalsmoney' &&
        _normalized(fields['source']?.toString() ?? '') == 'exchange') {
      return true;
    }
    for (final entry in value.entries) {
      final key = _normalized(entry.key.toString());
      if (_internalFlagKeys.contains(key) && entry.value == true) return true;
      if (_operationKeys.contains(key) &&
          entry.value is String &&
          _internalOperations.contains(_normalized(entry.value as String))) {
        return true;
      }
      if (_hasInternalOperation(entry.value)) return true;
    }
  } else if (value is Iterable) {
    return value.any(_hasInternalOperation);
  }
  return false;
}

String _normalized(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

const _internalMovementTypes = {
  'exchange',
  'conversion',
  'currencyconversion',
  'currencyexchange',
  'fx',
  'fxtrade',
  'fxconversion',
  'fxexchange',
  'cryptoexchange',
  'cryptotoquantum',
  'cryptotoquantumtransfer',
  'quantumtocryptoexchange',
  'cardtopup',
  'autocardtopup',
  'cardload',
  'cardloading',
  'cardunload',
  'balancetransfer',
};

const _internalOperations = {
  ..._internalMovementTypes,
  'quantumtocrypto',
  'usdtocrypto',
  'internaltransfer',
  'ownaccounttransfer',
  'owntransfer',
  'budgettransfer',
  'cardfunding',
};

const _operationKeys = {'operation', 'operationtype', 'transfertype'};
const _internalFlagKeys = {'isinternaltransfer', 'isowntransfer'};
const _externalTransferTypes = {
  'p2psend',
  'p2preceive',
  'peersend',
  'peerreceive',
  'transfertomaster',
  'transferfrommaster',
  'usertomastertransfer',
  'mastertousertransfer',
};
