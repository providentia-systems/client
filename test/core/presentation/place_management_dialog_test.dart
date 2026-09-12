import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/presentation/place_management_dialog.dart';

void main() {
  testWidgets(
    'location editor creates, renames, removes and restores without losing identity',
    (tester) async {
      final changes = ValueNotifier(0);
      addTearDown(changes.dispose);
      var entries = <PlaceDetails>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PlaceManagementDialog(
                    title: 'Locations',
                    singular: 'location',
                    detailLabel: 'Kind',
                    listenable: changes,
                    detailOptions: const ['pantry', 'shelf'],
                    entries: () => entries,
                    save: (value) async {
                      entries = [
                        PlaceDetails(
                          id: value.id ?? 'location',
                          name: value.name,
                          detail: value.detail,
                          archived: value.archived,
                          revision: (value.revision ?? 0) + 1,
                        ),
                      ];
                      changes.value++;
                      return true;
                    },
                  ),
                ),
                child: const Text('Manage'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing added yet.'), findsOneWidget);
      await tester.tap(find.text('Add location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter a name.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Pantry');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(entries.single.revision, 1);
      await tester.tap(find.text('Pantry'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Cupboard');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('shelf').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(entries.single.name, 'Cupboard');
      expect(entries.single.detail, 'shelf');
      expect(entries.single.archived, isTrue);
      expect(entries.single.id, 'location');
      expect(entries.single.revision, 2);
      await tester.tap(find.text('Cupboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(entries.single.archived, isFalse);
      expect(entries.single.revision, 3);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'store editor preserves failed edits and cancellation disposes safely',
    (tester) async {
      final changes = ValueNotifier(0);
      addTearDown(changes.dispose);
      PlaceDetails? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceManagementDialog(
              title: 'Stores',
              singular: 'store',
              detailLabel: 'Location',
              listenable: changes,
              entries: () => const [
                PlaceDetails(
                  id: 'store',
                  name: 'Grocer',
                  detail: 'Town',
                  revision: 4,
                ),
              ],
              save: (value) async {
                saved = value;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Grocer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Market');
      await tester.enterText(find.byType(TextField).last, 'City');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.name, 'Market');
      expect(saved?.detail, 'City');
      expect(saved?.revision, 4);
      expect(find.textContaining('could not be saved'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
