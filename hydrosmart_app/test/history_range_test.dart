import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrosmart_app/models/history_range.dart';
import 'package:hydrosmart_app/models/telemetry_sample.dart';
import 'package:hydrosmart_app/widgets/history_analytics_card.dart';

void main() {
  test('averages readings in the selected time bucket', () {
    final start = DateTime(2026, 11, 27, 10);
    final result = aggregateTelemetry([
      TelemetrySample(time: start, tds: 680, waterPct: 40),
      TelemetrySample(
        time: start.add(const Duration(minutes: 2)),
        tds: 700,
        waterPct: 42,
      ),
      TelemetrySample(
        time: start.add(const Duration(minutes: 6)),
        tds: 720,
        waterPct: 44,
      ),
    ], HistoryRange.hours24);

    expect(result, hasLength(2));
    expect(result.first.tds, 690);
    expect(result.first.waterPct, 41);
    expect(result.last.tds, 720);
  });

  test('keeps missing water as null and excludes invalid TDS', () {
    final start = DateTime(2026, 11, 27, 10);
    final result = aggregateTelemetry([
      TelemetrySample(time: start, tds: 20, waterPct: null),
      TelemetrySample(
        time: start.add(const Duration(minutes: 1)),
        tds: 700,
        waterPct: null,
      ),
    ], HistoryRange.hours24);

    expect(result, hasLength(1));
    expect(result.single.tds, 700);
    expect(result.single.waterPct, isNull);
  });

  testWidgets('renders the selected history range and TDS target', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryAnalyticsCard(
            samples: [
              TelemetrySample(
                time: now.subtract(const Duration(minutes: 5)),
                tds: 680,
                waterPct: 54,
              ),
              TelemetrySample(time: now, tds: 700, waterPct: 55),
            ],
            range: HistoryRange.hours24,
            loading: false,
            error: null,
            onRangeChanged: (_) {},
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Grafik perkembangan'), findsOneWidget);
    expect(find.text('Target nutrisi 600–800 ppm'), findsOneWidget);
    expect(find.text('30 hari'), findsOneWidget);
  });
}
