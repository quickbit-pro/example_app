import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/peer/data/peer_transfers_api.dart';
import 'package:mobile_flutter/features/peer/presentation/peer_widgets.dart';

void main() {
  group('peer models', () {
    test('parses a received request with masked counterparty', () {
      final request = PeerPaymentRequest.fromJson({
        'id': 'req-1',
        'type': 'received',
        'otherUser': {
          'userId': 'u-2',
          'firstName': 'Ana',
          'lastName': 'Kovač',
          'initials': 'AK',
          'avatarColor': '#27D7C2',
          'maskedEmail': 'an***@x.io',
        },
        'amount': '42.5',
        'currency': 'usdc',
        'note': 'Dinner',
        'status': 'Pending',
        'createdAt': '2026-09-04T08:00:00Z',
        'expiresAt': '2026-09-11T08:00:00Z',
      });

      expect(request.sent, isFalse);
      expect(request.pending, isTrue);
      expect(request.amount, 42.5);
      expect(request.currency, 'USDC');
      expect(request.otherUser.fullName, 'Ana Kovač');
      expect(request.otherUser.avatarColor, const Color(0xFF27D7C2));
      expect(request.otherUser.contactHint, 'an***@x.io');
    });

    test('parses fee info and transfers', () {
      final fee = PeerFeeInfo.fromJson({
        'freeTransfersPerDay': 10,
        'transfersUsedToday': 10,
        'freeTransfersRemaining': 0,
        'feePercent': 1,
        'feeAmount': 0.5,
        'feeCurrency': 'USD',
        'feeApplies': true,
        'isRateLimited': true,
        'rateLimitSecondsRemaining': 7,
        'dailySendLimit': 50,
        'sendsRemainingToday': 40,
        'minAmount': 0.01,
        'maxAmount': 1000000,
        'currencies': ['USD', 'USDC', 'USDT'],
      });
      expect(fee.feeApplies, isTrue);
      expect(fee.isRateLimited, isTrue);
      expect(fee.rateLimitSecondsRemaining, 7);
      expect(fee.currencies, ['USD', 'USDC', 'USDT']);

      final transfer = PeerTransfer.fromJson({
        'id': 't-1',
        'type': 'sent',
        'otherUser': {'userId': 'u-3', 'firstName': 'Bo', 'lastName': ''},
        'amount': 12,
        'currency': 'USD',
        'status': 'completed',
        'fee': 0,
        'createdAt': '2026-09-04T08:00:00Z',
      });
      expect(transfer.sent, isTrue);
      expect(transfer.completed, isTrue);
      expect(transfer.otherUser.initials, 'B');
    });

    test('confirmation payload carries the method and password', () {
      expect(const PeerConfirmation.biometric().toJson(), {
        'confirmationMethod': 'biometric',
      });
      expect(const PeerConfirmation.password('pw').toJson(), {
        'confirmationMethod': 'password',
        'password': 'pw',
      });
    });
  });

  group('peer formatting', () {
    test('money renders two decimals with the right symbol', () {
      expect(peerMoney('USD', 1234.5), r'$1,234.50');
      expect(peerMoney('USDC', 12), '12.00 USDC');
      expect(peerMoney('usdt', -3.456), '-3.46 USDT');
    });

    test('relative time and expiry read naturally', () {
      final now = DateTime(2026, 9, 4, 12);
      expect(
          peerRelativeTime(now.subtract(const Duration(seconds: 20)), now: now),
          'Just now');
      expect(
          peerRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
          '5m ago');
      expect(peerRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
          '3h ago');
      expect(peerRelativeTime(now.subtract(const Duration(days: 2)), now: now),
          '2d ago');
      expect(peerRelativeTime(DateTime(2026, 1, 15), now: now), '15 Jan');
      expect(
          peerExpiresIn(now.add(const Duration(days: 6, hours: 2)), now: now),
          'Expires in 6d');
      expect(peerExpiresIn(now.subtract(const Duration(minutes: 1)), now: now),
          'Expired');
    });
  });
}
