import 'package:chord_trainer/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading then chord trainer UI', (WidgetTester tester) async {
    await tester.pumpWidget(const ChordTrainerApp());
    expect(find.text('Loading chords…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Chord Trainer'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);
  });
}
