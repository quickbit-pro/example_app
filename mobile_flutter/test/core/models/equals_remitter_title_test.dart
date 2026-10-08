import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

void main() {
  Map<String, dynamic> transaction(Map<String, dynamic> metadata,
          {String type = 'deposit', num amount = 20}) =>
      {
        'id': 'incoming',
        'type': type,
        'amount': amount,
        'currency': 'EUR',
        'title': 'UK.OBIE.SEPACreditTransfer',
        'metadata': metadata,
      };
  const sender = {
    'provider': 'equalsmoney',
    'source': 'external_credit',
    'remitterName': 'Igor Lavrih',
    'paymentMethod': 'UK.OBIE.SEPACreditTransfer'
  };

  test('incoming Equals title uses sender and preserves payment method', () {
    final row = LedgerTransaction.fromJson(transaction(sender));
    expect(row.title, 'Igor Lavrih');
    expect(row.metadata['paymentMethod'], 'UK.OBIE.SEPACreditTransfer');
  });
  test('supports PascalCase and serialized metadata', () {
    final row = LedgerTransaction.fromJson({
      ...transaction({}),
      'Metadata':
          '{"Provider":"equalsmoney","Source":"external_credit","RemitterName":"Sender GmbH"}',
    });
    expect(row.title, 'Sender GmbH');
    final flat = LedgerTransaction.fromJson({
      ...transaction({}),
      'Provider': 'EqualsMoney',
      'RemitterName': 'Sender GmbH',
    });
    expect(flat.title, 'Sender GmbH');
  });
  test('does not relabel outgoing fees or internal movements as deposits', () {
    for (final row in [
      transaction(sender, type: 'withdrawal', amount: -20),
      transaction(sender, type: 'fee', amount: -1),
      transaction({...sender, 'source': 'budget_transfer'}),
      transaction({...sender, 'provider': 'interlace'}),
      transaction({...sender, 'remitterName': '  '}),
    ]) {
      expect(LedgerTransaction.fromJson(row).title, isNot('Igor Lavrih'));
    }
  });
}
