import 'package:dio/dio.dart';
import '../../../core/identity/user_nickname.dart';
import 'package:flutter/material.dart';

/// Member of the same programme, as shown to another member: name and
/// initials, never the raw email or phone number.
class PeerUser {
  const PeerUser({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.initials,
    required this.avatarColor,
    this.nickname,
    this.maskedEmail,
    this.maskedPhone,
    this.isContact = false,
  });

  factory PeerUser.fromJson(Map<String, dynamic> json) {
    final first = _string(json, ['firstName', 'FirstName']);
    final last = _string(json, ['lastName', 'LastName']);
    return PeerUser(
      userId: _string(json, ['userId', 'UserId']),
      firstName: first,
      lastName: last,
      initials: _string(json, ['initials', 'Initials']).isEmpty
          ? _initialsOf(first, last)
          : _string(json, ['initials', 'Initials']),
      avatarColor: _color(_string(json, ['avatarColor', 'AvatarColor'])),
      nickname: _nullable(json, ['nickname', 'Nickname']),
      maskedEmail: _nullable(json, ['maskedEmail', 'MaskedEmail']),
      maskedPhone: _nullable(json, ['maskedPhone', 'MaskedPhone']),
      isContact: json['isContact'] == true || json['IsContact'] == true,
    );
  }

  final String userId;
  final String firstName;
  final String lastName;
  final String initials;
  final Color avatarColor;
  final String? nickname;
  final String? maskedEmail;
  final String? maskedPhone;
  final bool isContact;

  String get fullName =>
      [firstName, lastName].where((part) => part.isNotEmpty).join(' ');

  String get contactHint => [
        if (nickname?.isNotEmpty == true) '@$nickname',
        if (maskedEmail != null || maskedPhone != null)
          maskedEmail ?? maskedPhone!,
      ].join(' · ');

  PeerUser copyWith({bool? isContact}) => PeerUser(
        userId: userId,
        firstName: firstName,
        lastName: lastName,
        initials: initials,
        avatarColor: avatarColor,
        nickname: nickname,
        maskedEmail: maskedEmail,
        maskedPhone: maskedPhone,
        isContact: isContact ?? this.isContact,
      );
}

class PeerContact {
  const PeerContact({
    required this.id,
    required this.user,
    required this.addedAt,
    this.nickname,
  });

  factory PeerContact.fromJson(Map<String, dynamic> json) => PeerContact(
        id: _string(json, ['id', 'Id']),
        user: PeerUser.fromJson(_map(json['user'] ?? json['User'])),
        nickname: _nullable(json, ['nickname', 'Nickname']),
        addedAt: _date(json, ['addedAt', 'AddedAt']) ?? DateTime.now(),
      );

  final String id;
  final PeerUser user;
  final String? nickname;
  final DateTime addedAt;

  String get displayName =>
      nickname?.trim().isNotEmpty == true ? nickname!.trim() : user.fullName;
}

/// A completed or attempted transfer, from the viewer's point of view.
class PeerTransfer {
  const PeerTransfer({
    required this.id,
    required this.sent,
    required this.otherUser,
    required this.amount,
    required this.currency,
    required this.status,
    required this.fee,
    required this.createdAt,
    this.note,
    this.completedAt,
    this.paymentRequestId,
    this.errorMessage,
  });

  factory PeerTransfer.fromJson(Map<String, dynamic> json) => PeerTransfer(
        id: _string(json, ['id', 'Id']),
        sent: _string(json, ['type', 'Type']).toLowerCase() == 'sent',
        otherUser:
            PeerUser.fromJson(_map(json['otherUser'] ?? json['OtherUser'])),
        amount: _double(json, ['amount', 'Amount']),
        currency: _string(json, ['currency', 'Currency']).toUpperCase(),
        note: _nullable(json, ['note', 'Note']),
        status: _string(json, ['status', 'Status']).toLowerCase(),
        fee: _double(json, ['fee', 'Fee']),
        createdAt: _date(json, ['createdAt', 'CreatedAt']) ?? DateTime.now(),
        completedAt: _date(json, ['completedAt', 'CompletedAt']),
        paymentRequestId:
            _nullable(json, ['paymentRequestId', 'PaymentRequestId']),
        errorMessage: _nullable(json, ['errorMessage', 'ErrorMessage']),
      );

  final String id;
  final bool sent;
  final PeerUser otherUser;
  final double amount;
  final String currency;
  final String? note;
  final String status;
  final double fee;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? paymentRequestId;
  final String? errorMessage;

  bool get completed => status == 'completed';
}

/// "Request money": pending until the payer accepts, declines, or it expires.
class PeerPaymentRequest {
  const PeerPaymentRequest({
    required this.id,
    required this.sent,
    required this.otherUser,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.note,
    this.respondedAt,
    this.transferId,
  });

  factory PeerPaymentRequest.fromJson(Map<String, dynamic> json) =>
      PeerPaymentRequest(
        id: _string(json, ['id', 'Id']),
        sent: _string(json, ['type', 'Type']).toLowerCase() == 'sent',
        otherUser:
            PeerUser.fromJson(_map(json['otherUser'] ?? json['OtherUser'])),
        amount: _double(json, ['amount', 'Amount']),
        currency: _string(json, ['currency', 'Currency']).toUpperCase(),
        note: _nullable(json, ['note', 'Note']),
        status: _string(json, ['status', 'Status']).toLowerCase(),
        createdAt: _date(json, ['createdAt', 'CreatedAt']) ?? DateTime.now(),
        expiresAt: _date(json, ['expiresAt', 'ExpiresAt']) ??
            DateTime.now().add(const Duration(days: 7)),
        respondedAt: _date(json, ['respondedAt', 'RespondedAt']),
        transferId: _nullable(json, ['transferId', 'TransferId']),
      );

  final String id;

  /// True when the viewer asked for the money; false when they were asked.
  final bool sent;
  final PeerUser otherUser;
  final double amount;
  final String currency;
  final String? note;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;
  final String? transferId;

  bool get pending => status == 'pending';
}

class PeerRequests {
  const PeerRequests({
    this.received = const [],
    this.sent = const [],
    this.history = const [],
  });

  factory PeerRequests.fromJson(Map<String, dynamic> json) => PeerRequests(
        received: _list(json['received'] ?? json['Received'])
            .map(PeerPaymentRequest.fromJson)
            .toList(),
        sent: _list(json['sent'] ?? json['Sent'])
            .map(PeerPaymentRequest.fromJson)
            .toList(),
        history: _list(json['history'] ?? json['History'])
            .map(PeerPaymentRequest.fromJson)
            .toList(),
      );

  final List<PeerPaymentRequest> received;
  final List<PeerPaymentRequest> sent;
  final List<PeerPaymentRequest> history;

  int get pendingCount => received.length + sent.length;
}

/// Daily quota, pacing and fee estimate for outgoing member transfers.
class PeerFeeInfo {
  const PeerFeeInfo({
    required this.freeTransfersPerDay,
    required this.transfersUsedToday,
    required this.freeTransfersRemaining,
    required this.feePercent,
    required this.feeAmount,
    required this.feeCurrency,
    required this.feeApplies,
    required this.isRateLimited,
    required this.rateLimitSecondsRemaining,
    required this.dailySendLimit,
    required this.sendsRemainingToday,
    required this.minAmount,
    required this.maxAmount,
    required this.currencies,
    this.nextTransferAllowedAt,
  });

  factory PeerFeeInfo.fromJson(Map<String, dynamic> json) => PeerFeeInfo(
        freeTransfersPerDay:
            _int(json, ['freeTransfersPerDay', 'FreeTransfersPerDay']),
        transfersUsedToday:
            _int(json, ['transfersUsedToday', 'TransfersUsedToday']),
        freeTransfersRemaining:
            _int(json, ['freeTransfersRemaining', 'FreeTransfersRemaining']),
        feePercent: _double(json, ['feePercent', 'FeePercent']),
        feeAmount: _double(json, ['feeAmount', 'FeeAmount']),
        feeCurrency:
            _string(json, ['feeCurrency', 'FeeCurrency']).toUpperCase(),
        feeApplies: json['feeApplies'] == true || json['FeeApplies'] == true,
        isRateLimited:
            json['isRateLimited'] == true || json['IsRateLimited'] == true,
        rateLimitSecondsRemaining: _int(
            json, ['rateLimitSecondsRemaining', 'RateLimitSecondsRemaining']),
        nextTransferAllowedAt:
            _date(json, ['nextTransferAllowedAt', 'NextTransferAllowedAt']),
        dailySendLimit: _int(json, ['dailySendLimit', 'DailySendLimit']),
        sendsRemainingToday:
            _int(json, ['sendsRemainingToday', 'SendsRemainingToday']),
        minAmount: _double(json, ['minAmount', 'MinAmount']),
        maxAmount: _double(json, ['maxAmount', 'MaxAmount']),
        currencies: [
          for (final entry in (json['currencies'] ?? json['Currencies']) is List
              ? (json['currencies'] ?? json['Currencies']) as List
              : const [])
            entry.toString().toUpperCase(),
        ],
      );

  final int freeTransfersPerDay;
  final int transfersUsedToday;
  final int freeTransfersRemaining;
  final double feePercent;
  final double feeAmount;
  final String feeCurrency;
  final bool feeApplies;
  final bool isRateLimited;
  final int rateLimitSecondsRemaining;
  final DateTime? nextTransferAllowedAt;
  final int dailySendLimit;
  final int sendsRemainingToday;
  final double minAmount;
  final double maxAmount;
  final List<String> currencies;
}

class PeerRespondResult {
  const PeerRespondResult({required this.request, this.transfer});

  factory PeerRespondResult.fromJson(Map<String, dynamic> json) =>
      PeerRespondResult(
        request: PeerPaymentRequest.fromJson(
            _map(json['request'] ?? json['Request'])),
        transfer: json['transfer'] == null && json['Transfer'] == null
            ? null
            : PeerTransfer.fromJson(_map(json['transfer'] ?? json['Transfer'])),
      );

  final PeerPaymentRequest request;
  final PeerTransfer? transfer;
}

/// How the customer confirmed a money-moving action on this device.
class PeerConfirmation {
  const PeerConfirmation.biometric()
      : method = 'biometric',
        password = null;

  const PeerConfirmation.password(this.password) : method = 'password';

  final String method;
  final String? password;

  Map<String, Object?> toJson() => {
        'confirmationMethod': method,
        if (password != null) 'password': password,
      };
}

class PeerTransfersApi {
  PeerTransfersApi(this._dio);

  final Dio _dio;

  static const _base = '/api/v1/mobile/peer-transfers';

  Future<PeerUser> lookupQuery(String value) {
    final query = value.trim();
    final problem = recipientLookupProblem(query);
    if (problem != null) throw FormatException(problem);
    if (isNicknameLookup(query)) {
      return lookup(nickname: normalizeNickname(query));
    }
    return query.contains('@')
        ? lookup(email: query)
        : lookup(phoneNumber: query);
  }

  Future<PeerUser> lookup(
      {String? email, String? phoneNumber, String? nickname}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/lookup',
      data: {
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phoneNumber != null && phoneNumber.isNotEmpty)
          'phoneNumber': phoneNumber,
      },
    );
    return PeerUser.fromJson(response.data ?? const {});
  }

  Future<PeerFeeInfo> feeInfo({double? amount, String? currency}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_base/fee-info',
      queryParameters: {
        if (amount != null) 'amount': amount,
        if (currency != null) 'currency': currency,
      },
    );
    return PeerFeeInfo.fromJson(response.data ?? const {});
  }

  Future<PeerTransfer> send({
    required String recipientUserId,
    required double amount,
    required String currency,
    required PeerConfirmation confirmation,
    String? note,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/send',
      data: {
        'recipientUserId': recipientUserId,
        'amount': amount,
        'currency': currency,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        ...confirmation.toJson(),
      },
    );
    return PeerTransfer.fromJson(response.data ?? const {});
  }

  Future<List<PeerTransfer>> recent({int limit = 20}) async {
    final response = await _dio.get<List<dynamic>>(
      '$_base/recent',
      queryParameters: {'limit': limit},
    );
    return _list(response.data).map(PeerTransfer.fromJson).toList();
  }

  Future<PeerRequests> requests() async {
    final response = await _dio.get<Map<String, dynamic>>('$_base/requests');
    return PeerRequests.fromJson(response.data ?? const {});
  }

  Future<PeerPaymentRequest> requestMoney({
    required String fromUserId,
    required double amount,
    required String currency,
    String? note,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/requests',
      data: {
        'fromUserId': fromUserId,
        'amount': amount,
        'currency': currency,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return PeerPaymentRequest.fromJson(response.data ?? const {});
  }

  Future<PeerRespondResult> respond({
    required String requestId,
    required bool accept,
    PeerConfirmation? confirmation,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/requests/$requestId/respond',
      data: {
        'action': accept ? 'accept' : 'decline',
        if (confirmation != null) ...confirmation.toJson(),
      },
    );
    return PeerRespondResult.fromJson(response.data ?? const {});
  }

  Future<PeerPaymentRequest> cancelRequest(String requestId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/requests/$requestId/cancel',
    );
    return PeerPaymentRequest.fromJson(response.data ?? const {});
  }

  Future<List<PeerContact>> contacts() async {
    final response = await _dio.get<List<dynamic>>('$_base/contacts');
    return _list(response.data).map(PeerContact.fromJson).toList();
  }

  Future<PeerContact> addContact(String userId, {String? nickname}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_base/contacts',
      data: {
        'userId': userId,
        if (nickname != null && nickname.trim().isNotEmpty)
          'nickname': nickname.trim(),
      },
    );
    return PeerContact.fromJson(response.data ?? const {});
  }

  Future<void> removeContact(String contactId) =>
      _dio.delete<void>('$_base/contacts/$contactId');
}

// ─── JSON helpers ───────────────────────────────────────────────────────────

String _string(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) return value.toString();
  }
  return '';
}

String? _nullable(Map<String, dynamic> json, List<String> keys) {
  final value = _string(json, keys).trim();
  return value.isEmpty ? null : value;
}

double _double(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

int _int(Map<String, dynamic> json, List<String> keys) =>
    _double(json, keys).round();

DateTime? _date(Map<String, dynamic> json, List<String> keys) {
  final value = _nullable(json, keys);
  return value == null ? null : DateTime.tryParse(value)?.toLocal();
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _list(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

Color _color(String hex) {
  final cleaned = hex.replaceFirst('#', '').trim();
  final parsed =
      int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
  return parsed == null ? const Color(0xFF7B6CF6) : Color(parsed);
}

String _initialsOf(String first, String last) {
  final a = first.isEmpty ? '' : first[0].toUpperCase();
  final b = last.isEmpty ? '' : last[0].toUpperCase();
  final initials = '$a$b';
  return initials.isEmpty ? '?' : initials;
}
