import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

void main() {
  for (final pascalCase in [false, true]) {
    test('back artwork accepts API casing ($pascalCase) and null front fields',
        () {
      String key(String value) =>
          pascalCase ? value[0].toUpperCase() + value.substring(1) : value;
      final card = PaymentCard.fromJson({
        'id': 42,
        key('cardImageUrl'): null,
        'cardTypeMetadata': {
          key('cardImageUrl'): '/uploads/front.webp',
          key('cardBackImageUrl'): '/uploads/back.webp',
          key('cardBackThumbnailUrl'): '/uploads/back-thumb.webp',
          key('cardBackPreviewUrl'): '/uploads/back-preview.webp',
        },
      });
      expect(
          card.artworkUrl, 'https://dashboard.hoppa.global/uploads/front.webp');
      expect(card.cardBackImageUrl,
          'https://dashboard.hoppa.global/uploads/back.webp');
      expect(card.cardBackThumbnailUrl,
          'https://dashboard.hoppa.global/uploads/back-thumb.webp');
      expect(card.cardBackPreviewUrl,
          'https://dashboard.hoppa.global/uploads/back-preview.webp');
      expect(card.secureArtworkUrl, card.cardBackImageUrl);
    });
  }
  test('back falls through image, preview, thumbnail, then existing front', () {
    for (final fields in [
      {'cardBackPreviewUrl': 'https://cdn.example/back-preview.png'},
      {'cardBackThumbnailUrl': 'https://cdn.example/back-thumb.png'},
      {'cardImageUrl': 'https://cdn.example/front.png'},
    ]) {
      final card = PaymentCard.fromJson({'id': 1, ...fields});
      expect(card.secureArtworkUrl, fields.values.single);
    }
    final empty = PaymentCard.fromJson({
      'CardBackImageUrl': null,
      'CardBackPreviewUrl': null,
      'CardBackThumbnailUrl': null
    });
    expect(empty.secureArtworkUrl, isEmpty);
  });

  test('PaymentCard reads artwork from nested card-type metadata', () {
    final card = PaymentCard.fromJson({
      'id': 42,
      'cardTypeId': 7,
      'maskedCardNumber': '**** 4242',
      'cardTypeMetadata': {
        'id': 7,
        'name': 'Quantum Black',
        'cardImageUrl': 'https://cdn.example.com/card.png',
        'cardThumbnailUrl': 'https://cdn.example.com/card-thumb.png',
        'cardImageAlt': 'Quantum Black card',
        'cardTextColor': '#F8FAFC',
        'cardNetwork': 'Visa',
      },
    });

    expect(card.cardTypeId, 7);
    expect(card.cardTypeName, 'Quantum Black');
    expect(card.artworkUrl, 'https://cdn.example.com/card.png');
    expect(card.cardThumbnailUrl, 'https://cdn.example.com/card-thumb.png');
    expect(card.cardTextColor, '#F8FAFC');
    expect(card.network, 'Visa');
  });

  test('PaymentCard accepts a markdown-wrapped artwork URL', () {
    final card = PaymentCard.fromJson({
      'id': 43,
      'cardImageUrl':
          '[https://hoppa.global/images/black-card.png](https://hoppa.global/images/black-card.png)',
    });

    expect(
      card.artworkUrl,
      'https://hoppa.global/images/black-card.png',
    );
  });

  test('PaymentCard reads a top-level Hoppa card network', () {
    final card = PaymentCard.fromJson({
      'id': 46,
      'CardNetwork': 'MasterCard',
    });

    expect(card.network, 'MasterCard');
  });

  test('PaymentCard reads lowercase cardNetwork from the Hoppa cards list', () {
    final card = PaymentCard.fromJson({
      'id': 253,
      'userId': 10466,
      'externalCardId': '3847b57a-05e3-4fb0-8c84-58eced6db2fb',
      'cardNumber': '5371000000003191',
      'cardNetwork': 'mastercard',
      'currency': 'USD',
      'status': 'active',
    });

    expect(card.network, 'mastercard');
  });

  test('PaymentCard derives Mastercard from the provider card number', () {
    final card = PaymentCard.fromJson({
      'id': 47,
      'cardNumber': '5371000000003191',
    });

    expect(card.network, 'Mastercard');
  });

  test('PaymentCard resolves Hoppa relative artwork URLs', () {
    final card = PaymentCard.fromJson({
      'id': 44,
      'cardImageUrl': '/uploads/cards/hoppa-virtual.png',
    });

    expect(
      card.artworkUrl,
      'https://dashboard.hoppa.global/uploads/cards/hoppa-virtual.png',
    );
  });

  test('card detail keeps issuer artwork from the enriched list card', () {
    final detail = PaymentCard.fromJson({
      'id': 45,
      'balance': {'currency': 'USD', 'minorUnits': 1250},
    });
    final listCard = PaymentCard.fromJson({
      'id': 45,
      'cardTypeId': 104,
      'cardImageUrl': 'https://cdn.example.com/hoppa.png',
      'cardBackImageUrl': 'https://cdn.example.com/hoppa-back.png',
      'cardTextColor': '#111827',
    });

    final merged = detail.withFallback(listCard);
    expect(merged.artworkUrl, 'https://cdn.example.com/hoppa.png');
    expect(merged.cardTextColor, '#111827');
    expect(merged.backArtworkUrl, 'https://cdn.example.com/hoppa-back.png');
    expect(merged.balance.minorUnits, 1250);
  });
}
