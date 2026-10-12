import 'package:chord_trainer/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('loads the catalog and shows the home screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ChordTrainerApp());
    expect(find.text('טוען אקורדים…'), findsOneWidget);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Chord Trainer'), findsOneWidget);
    expect(find.text('ההתקדמות שלך'), findsOneWidget);
    expect(find.text('אימון אקורד בודד'), findsOneWidget);
  });
}
