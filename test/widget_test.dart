import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabeef_mobile/features/capture/domain/health_intent.dart';
import 'package:vinabeef_mobile/features/capture/presentation/widgets.dart';

void main() {
  testWidgets('status chip distinguishes pending from accepted', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          IntentStatusChip(IntentStatus.pendingSync),
          IntentStatusChip(IntentStatus.accepted),
          IntentStatusChip(IntentStatus.needsReview),
        ]),
      ),
    ));
    expect(find.text('Pending sync'), findsOneWidget);
    expect(find.text('Accepted by server'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
  });
}
