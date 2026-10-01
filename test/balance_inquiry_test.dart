import 'package:flutter_test/flutter_test.dart';
import 'package:solaire_balance_display/mqtt_service.dart';

void main() {
  test('parses a full balance inquiry payload', () {
    final inquiry = BalanceInquiry.fromJson(const {
      'request_id': 'REQ-1',
      'card_id': 'CARD-00009',
      'patron_name': 'Juan Cruz',
      'points': 7910,
      'tickets': 2500,
      'tickets_won': 2,
      'status': 'OK',
      'timestamp': '2026-10-01T12:00:00.000Z',
    });

    expect(inquiry.isOk, isTrue);
    expect(inquiry.cardId, 'CARD-00009');
    expect(inquiry.patronName, 'Juan Cruz');
    expect(inquiry.points, 7910);
    expect(inquiry.tickets, 2500);
    expect(inquiry.ticketsWon, 2);
  });

  test('handles CARD_NOT_FOUND payload with nulls and zero balances', () {
    final inquiry = BalanceInquiry.fromJson(const {
      'request_id': 'REQ-2',
      'card_id': null,
      'patron_name': null,
      'points': 0,
      'tickets': 0,
      'tickets_won': 0,
      'status': 'CARD_NOT_FOUND',
      'timestamp': '2026-10-01T12:00:00.000Z',
    });

    expect(inquiry.isOk, isFalse);
    expect(inquiry.status, 'CARD_NOT_FOUND');
    expect(inquiry.cardId, isNull);
    expect(inquiry.points, 0);
  });

  test('tolerates missing fields and numeric strings', () {
    final inquiry = BalanceInquiry.fromJson(const {
      'status': 'OK',
      'points': '1234',
    });

    expect(inquiry.isOk, isTrue);
    expect(inquiry.points, 1234);
    expect(inquiry.tickets, 0);
    expect(inquiry.ticketsWon, 0);
    expect(inquiry.patronName, isNull);
  });
}
