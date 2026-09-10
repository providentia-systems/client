import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/home_profile_page.dart';
import 'package:providentia/features/homes/presentation/member_permissions_page.dart';
import 'package:providentia/features/profile/account_profile_page.dart';
import 'package:providentia/features/profile/profile_port.dart';

void main() {
  testWidgets(
    'home profile preserves revision and normalizes stored map coordinates on save',
    (tester) async {
      _largeViewport(tester);
      final port = _ProfilePort();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeProfilePage(port: port, homeId: 'home-a', mayEdit: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('-22.560000, 17.080000'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'Updated home description',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save home profile'));
      await tester.pumpAndSettle();
      final saved = port.calls.singleWhere(
        (call) => call.operation == 'updateHomeProfile',
      );
      expect(saved.path, <String, String>{'homeId': 'home-a'});
      expect(saved.body, <String, Object?>{
        'description': 'Updated home description',
        'countryCode': 'NA',
        'stateId': 3,
        'cityId': 4,
        'latitude': -22.56,
        'longitude': 17.08,
        'expectedRevision': 7,
      });
      expect(
        port.calls.where((call) => call.operation == 'getHomeProfile'),
        hasLength(2),
      );
    },
  );

  testWidgets('home profile read access has no editing or photo affordance', (
    tester,
  ) async {
    _largeViewport(tester);
    final port = _ProfilePort();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeProfilePage(port: port, homeId: 'home-a', mayEdit: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save home profile'), findsNothing);
    expect(find.text('Choose and crop photo'), findsNothing);
    expect(find.byTooltip('Remove location'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Description'))
          .enabled,
      isFalse,
    );
    for (final label in <String>['Country', 'Region', 'City', 'Map location']) {
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, label)).onTap,
        isNull,
      );
    }
    expect(port.calls.map((call) => call.operation), <String>[
      'getHomeProfile',
      'getHomeImage',
    ]);
  });

  testWidgets(
    'member overrides inherit and deny while disabled home features cannot be allowed',
    (tester) async {
      _largeViewport(tester);
      final port = _ProfilePort();
      await _openPage(
        tester,
        MemberPermissionsPage(
          port: port,
          home: HomeSummary(
            id: 'home-a',
            name: 'Home',
            locale: 'en-NA',
            currency: 'NAD',
            timezone: 'Africa/Windhoek',
            role: HomeRole.owner,
            revision: 1,
            effectivePermissions: const <String>{
              HomePermissions.permissionsManage,
            },
            access: const <String, Object?>{
              'features': <String, bool>{
                'inventory.write': true,
                'ai.use': false,
              },
              'delegablePermissions': <String>['inventory.write', 'ai.use'],
            },
          ),
          member: HomeMembership(
            userId: 'member-a',
            displayName: 'Member A',
            role: HomeRole.member,
            revision: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stock = find.widgetWithText(ListTile, 'inventory.write');
      final ai = find.widgetWithText(ListTile, 'ai.use');
      final aiDropdown = tester.widget<DropdownButton<String>>(
        find.descendant(of: ai, matching: find.byType(DropdownButton<String>)),
      );
      expect(
        aiDropdown.items!.singleWhere((item) => item.value == 'allow').enabled,
        isFalse,
      );
      expect(find.text('Currently disabled for this home'), findsOneWidget);
      final stockDropdown = find.descendant(
        of: stock,
        matching: find.byType(DropdownButton<String>),
      );
      expect(
        tester.widget<DropdownButton<String>>(stockDropdown).value,
        'deny',
      );
      await tester.tap(stockDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inherit').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save permissions'));
      await tester.pumpAndSettle();
      final saved = port.calls.singleWhere(
        (call) => call.operation == 'updateMemberPermissionOverrides',
      );
      expect(saved.path, <String, String>{
        'homeId': 'home-a',
        'userId': 'member-a',
      });
      expect(saved.body, <String, Object?>{
        'permissions': <String, Object?>{},
        'expectedRevision': 5,
      });
    },
  );

  testWidgets(
    'onboarding requires acceptance of the displayed country policy version',
    (tester) async {
      _largeViewport(tester);
      final port = _ProfilePort();
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfilePage(
            port: port,
            onboarding: true,
            onChanged: () async {
              changed++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Namibia'), findsOneWidget);
      expect(
        find.text(
          'Operators with assigned access can review household records.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'),
        ' New Person ',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Complete account setup'),
      );
      await tester.pumpAndSettle();
      expect(
        port.calls.where(
          (call) => call.operation == 'completeAccountOnboarding',
        ),
        isEmpty,
      );
      expect(
        find.text('Select your country and accept its privacy notice.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Complete account setup'),
      );
      await tester.pump();
      // Successful onboarding waits for the parent to replace this screen.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      final saved = port.calls.singleWhere(
        (call) => call.operation == 'completeAccountOnboarding',
      );
      expect(saved.body?['displayName'], 'New Person');
      expect(saved.body?['countryCode'], 'NA');
      expect(saved.body?['timezone'], 'Africa/Windhoek');
      expect(saved.body?['policyAccepted'], isTrue);
      expect(saved.body?['policyId'], 'policy-na');
      expect(saved.body?['policyRevision'], 4);
      expect(saved.body?['expectedRevision'], 2);
      expect(changed, 1);
    },
  );

  testWidgets('onboarding still requires a nonblank display name', (
    tester,
  ) async {
    _largeViewport(tester);
    final port = _ProfilePort();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountProfilePage(
          port: port,
          onboarding: true,
          onChanged: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Your name'),
      '   ',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(
      find.widgetWithText(FilledButton, 'Complete account setup'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enter your name.'), findsOneWidget);
    expect(
      port.calls.where((call) => call.operation == 'completeAccountOnboarding'),
      isEmpty,
    );
  });

  testWidgets(
    'selected locations and city-only clearing survive save and reopen',
    (tester) async {
      _largeViewport(tester);
      final port = _ProfilePort(onboarded: true);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfilePage(port: port, onChanged: () async {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Region (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khomas'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'City (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Windhoek'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
      await tester.pumpAndSettle();

      final saved = port.calls.singleWhere(
        (call) => call.operation == 'updateAccountProfile',
      );
      expect(saved.body, containsPair('stateId', 1));
      expect(saved.body, containsPair('cityId', 2));
      expect(
        port.calls.where((call) => call.operation == 'getAccountProfile'),
        hasLength(2),
      );
      expect(find.text('Khomas'), findsOneWidget);
      expect(find.text('Windhoek'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear city'));
      await tester.pumpAndSettle();
      expect(find.text('Khomas'), findsOneWidget);
      expect(find.text('Windhoek'), findsNothing);
      expect(find.text('Not selected'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
      await tester.pumpAndSettle();

      final cityCleared = port.calls
          .where((call) => call.operation == 'updateAccountProfile')
          .last;
      expect(cityCleared.body, containsPair('stateId', 1));
      expect(cityCleared.body, containsPair('cityId', null));
      expect(
        port.calls.where((call) => call.operation == 'getAccountProfile'),
        hasLength(3),
      );
      expect(find.text('Khomas'), findsOneWidget);
      expect(find.text('Not selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear region'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
      await tester.pumpAndSettle();
      final cleared = port.calls
          .where((call) => call.operation == 'updateAccountProfile')
          .last;
      expect(cleared.body, containsPair('stateId', null));
      expect(cleared.body, containsPair('cityId', null));
      expect(find.text('Not selected'), findsNWidgets(2));
    },
  );

  testWidgets(
    'failed saved-location lookups show honest IDs and remain clearable',
    (tester) async {
      _largeViewport(tester);
      final port = _ProfilePort(onboarded: true)
        ..stateId = 1
        ..cityId = 2
        ..failLocationLookups = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfilePage(port: port, onChanged: () async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved region unavailable (ID 1)'), findsOneWidget);
      expect(find.text('Saved city unavailable (ID 2)'), findsOneWidget);
      expect(find.text('Region selected'), findsNothing);
      expect(find.text('City selected'), findsNothing);

      await tester.tap(find.byTooltip('Clear city'));
      await tester.pumpAndSettle();
      expect(find.text('Saved region unavailable (ID 1)'), findsOneWidget);
      expect(find.text('Saved city unavailable (ID 2)'), findsNothing);
      expect(find.text('Not selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear region'));
      await tester.pumpAndSettle();
      expect(find.text('Saved region unavailable (ID 1)'), findsNothing);
      expect(find.text('Not selected'), findsNWidgets(2));
    },
  );

  testWidgets(
    'older profile responses resolve saved names with country and state scope',
    (tester) async {
      _largeViewport(tester);
      final port = _ProfilePort(onboarded: true)
        ..stateId = 1
        ..cityId = 2;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfilePage(port: port, onChanged: () async {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Khomas'), findsOneWidget);
      expect(find.text('Windhoek'), findsOneWidget);
      final stateCall = port.calls.singleWhere(
        (call) => call.operation == 'listCountryStates',
      );
      final cityCall = port.calls.singleWhere(
        (call) => call.operation == 'listCountryCities',
      );
      expect(stateCall.path, <String, String>{'countryCode': 'NA'});
      expect(stateCall.query, isNot(contains('stateId')));
      expect(cityCall.path, <String, String>{'countryCode': 'NA'});
      expect(cityCall.query, containsPair('stateId', '1'));
    },
  );

  testWidgets(
    'country change clears optional locations but still requires its policy',
    (tester) async {
      _largeViewport(tester);
      final port = _ProfilePort(onboarded: true)
        ..stateId = 1
        ..cityId = 2
        ..stateName = 'Khomas'
        ..cityName = 'Windhoek';
      await tester.pumpWidget(
        MaterialApp(
          home: AccountProfilePage(port: port, onChanged: () async {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ListTile, 'Country'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Botswana'));
      await tester.pumpAndSettle();
      expect(find.text('Not selected'), findsNWidgets(2));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
      await tester.pumpAndSettle();

      final saved = port.calls.singleWhere(
        (call) => call.operation == 'updateAccountProfile',
      );
      expect(saved.body, containsPair('countryCode', 'BW'));
      expect(saved.body, containsPair('stateId', null));
      expect(saved.body, containsPair('cityId', null));
      expect(saved.body, containsPair('policyAccepted', true));
    },
  );

  testWidgets('profile edits retain the verified primary login address', (
    tester,
  ) async {
    _largeViewport(tester);
    final port = _ProfilePort(onboarded: true);
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountProfilePage(
          port: port,
          onChanged: () async {
            changed++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Primary email'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Use default avatar'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Your name'),
      'Updated Person',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
    await tester.pumpAndSettle();
    final saved = port.calls.singleWhere(
      (call) => call.operation == 'updateAccountProfile',
    );
    expect(saved.body?['displayName'], 'Updated Person');
    expect(saved.body?.containsKey('email'), isFalse);
    expect(saved.body?.containsKey('policyAccepted'), isFalse);
    expect(changed, 1);
  });
}

Future<void> _openPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => page),
            ),
            child: const Text('Open page'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open page'));
  await tester.pumpAndSettle();
}

void _largeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 2000);
  addTearDown(tester.view.reset);
}

final class _ProfilePort implements ProfilePort {
  _ProfilePort({this.onboarded = false});
  final bool onboarded;
  String countryCode = 'NA';
  int? stateId;
  int? cityId;
  String? stateName;
  String? cityName;
  bool failLocationLookups = false;
  final List<
    ({
      String operation,
      Map<String, String>? path,
      Map<String, String>? query,
      ProfileRecord? body,
    })
  >
  calls = [];
  @override
  Future<Object?> call(
    String operation, {
    Map<String, String>? path,
    Map<String, String>? query,
    ProfileRecord? body,
  }) async {
    calls.add((
      operation: operation,
      path: path,
      query: query,
      body: body == null ? null : Map<String, Object?>.from(body),
    ));
    if (operation == 'updateAccountProfile' ||
        operation == 'completeAccountOnboarding') {
      countryCode = '${body!['countryCode']}';
      stateId = body['stateId'] as int?;
      cityId = body['cityId'] as int?;
      stateName = stateId == 1 ? 'Khomas' : null;
      cityName = cityId == 2 ? 'Windhoek' : null;
    }
    if (failLocationLookups &&
        (operation == 'listCountryStates' ||
            operation == 'listCountryCities')) {
      throw const ProfileFailure('Location reference unavailable.');
    }
    return switch (operation) {
      'getHomeProfile' => <String, Object?>{
        'description': 'My home',
        'countryCode': 'NA',
        'stateId': 3,
        'cityId': 4,
        'latitude': '-22.560000',
        'longitude': '17.080000',
        'revision': 7,
        'avatarRevision': 1,
      },
      'getHomeImage' => null,
      'getMemberPermissionOverrides' => <String, Object?>{
        'permissions': <String, Object?>{'inventory.write': false},
        'revision': 5,
      },
      'getAccountProfile' => <String, Object?>{
        'displayName': 'Person',
        'countryCode': countryCode,
        'stateId': stateId,
        'cityId': cityId,
        if (stateName != null) 'stateName': stateName,
        if (cityName != null) 'cityName': cityName,
        'onboardingComplete': onboarded,
        'timezone': 'Africa/Windhoek',
        'locale': 'en-NA',
        'revision': 2,
        'avatarSource': 'default',
        'avatarRevision': 1,
        'emails': <ProfileRecord>[
          <String, Object?>{
            'id': 'email-1',
            'email': 'person@example.test',
            'primary': true,
          },
        ],
      },
      'listAvailableCountries' => <String, Object?>{
        'data': <ProfileRecord>[
          <String, Object?>{
            'code': 'NA',
            'name': 'Namibia',
            'defaultTimezone': 'Africa/Windhoek',
            'defaultCurrency': 'NAD',
          },
          <String, Object?>{
            'code': 'BW',
            'name': 'Botswana',
            'defaultTimezone': 'Africa/Gaborone',
            'defaultCurrency': 'BWP',
          },
        ],
      },
      'listCountryStates' => <String, Object?>{
        'data': <ProfileRecord>[
          <String, Object?>{'id': 1, 'name': 'Khomas'},
        ],
      },
      'listCountryCities' => <String, Object?>{
        'data': <ProfileRecord>[
          <String, Object?>{'id': 2, 'name': 'Windhoek'},
        ],
      },
      'getCountryPrivacyPolicy' => <String, Object?>{
        'id': 'policy-na',
        'revision': 4,
        'title': 'Privacy notice',
        'body': 'Operators with assigned access can review household records.',
      },
      _ => <String, Object?>{},
    };
  }
}
