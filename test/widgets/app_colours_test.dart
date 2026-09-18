// test/widgets/app_colours_test.dart - one colour map, read by the menu, the drawer, the screen
// headings and the slot actions (ID-112, ID-118).
//
// What is pinned here is that there is ONE source. The menu and the drawer each used to colour
// themselves, which is how the same screen came to look like two different things depending on
// which way you opened it.
import 'package:cfg_pia_wg/app_colors.dart';
import 'package:cfg_pia_wg/app_shell.dart';
import 'package:cfg_pia_wg/session_controller.dart';
import 'package:cfg_pia_wg/widgets/app_button.dart';
import 'package:cfg_pia_wg/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SessionController _quietController() =>
    SessionController(tickInterval: const Duration(hours: 1), clipboardWriter: (_) async {});

void main() {
  test('every destination has a colour, and the screens are told apart by it', () {
    for (final d in AppDestination.values) {
      expect(kDestinationColours[d], isNotNull, reason: '${d.routeName} has no colour');
      expect(destinationColour(d), kDestinationColours[d]);
    }
    // SETTINGS and ABOUT deliberately share the utility grey; everything else is its own colour.
    final distinct = AppDrawer.destinations.map(destinationColour).toSet();
    expect(distinct, hasLength(AppDrawer.destinations.length - 1));
  });

  test('every slot action verb has a colour, and DELETE alone is red', () {
    for (final label in ['CREATE', 'CREATE/EDIT', 'ENABLE', 'EDIT', 'DISABLE', 'DELETE', 'VIEW ROUTER WATCHDOG LOG']) {
      expect(kSlotActionColours[label], isNotNull, reason: label);
    }
    expect(slotActionColour('DELETE'), kError);
    expect(kSlotActionColours.values.where((c) => c == kError), hasLength(1));
    // A verb keeps the colour of the thing it acts on.
    expect(slotActionColour('EDIT'), destinationColour(AppDestination.manageRouter));
    expect(slotActionColour('CREATE/EDIT'), destinationColour(AppDestination.watchdog));
    expect(slotActionColour('DISABLE'), destinationColour(AppDestination.deviceAssignment));
    expect(slotActionColour('SOMETHING NEW'), kHighlight, reason: 'an unnamed verb is never invisible');
  });

  testWidgets('the drawer colours each row from the same map, without an outline', (tester) async {
    final c = _quietController();
    await tester.pumpWidget(PiaWgApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app_hamburger')));
    await tester.pumpAndSettle();

    for (final d in AppDrawer.destinations) {
      final tile = tester.widget<ListTile>(find.byKey(Key('drawer_${d.routeName}')));
      expect(tile.iconColor, destinationColour(d), reason: '${d.routeName} icon');
      expect(tile.textColor, destinationColour(d), reason: '${d.routeName} label');
      expect(tile.shape, isNull, reason: 'the drawer is a list: no outline is added');
    }

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('a button takes its verb colour, and a disabled one still greys out', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          AppButton(keyValue: 'live', label: 'EDIT', colour: slotActionColour('EDIT'), onPressed: () {}),
          AppButton(keyValue: 'dead', label: 'EDIT', colour: slotActionColour('EDIT'), onPressed: null),
        ]),
      ),
    ));

    Color border(String key) =>
        tester.widget<OutlinedButton>(find.byKey(Key(key))).style!.side!.resolve(<WidgetState>{})!.color;
    expect(border('live'), kManageColour);
    expect(border('dead'), kHint, reason: 'a dead button never reads as live');
  });
}
