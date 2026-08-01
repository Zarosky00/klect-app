import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/design/tokens.g.dart';
import 'package:klect/ui/k_tab_pager.dart';

import 'support/test_harness.dart';

void main() {
  // ─────────────────────────────────────────────── the pure decisions ──

  group('commit threshold', () {
    test('commits on a quarter of the viewport', () {
      expect(
        tabPagerDragCommits(displacement: 100, velocity: 0, viewportWidth: 400),
        isTrue,
      );
      expect(
        tabPagerDragCommits(displacement: 99, velocity: 0, viewportWidth: 400),
        isFalse,
      );
    });

    test('commits on a fling however short the travel', () {
      expect(
        tabPagerDragCommits(
          displacement: 4,
          velocity: Drags.flingVelocityMin,
          viewportWidth: 400,
        ),
        isTrue,
      );
      expect(
        tabPagerDragCommits(
          displacement: 4,
          velocity: Drags.flingVelocityMin - 1,
          viewportWidth: 400,
        ),
        isFalse,
      );
    });

    test('settles back on the originating member below both thresholds', () {
      expect(
        tabPagerSettleIndex(
          originIndex: 1,
          length: 3,
          displacement: 40,
          velocity: 100,
          viewportWidth: 400,
        ),
        1,
      );
    });

    test('never wraps and never travels more than one member', () {
      // Past the last member.
      expect(
        tabPagerSettleIndex(
          originIndex: 2,
          length: 3,
          displacement: 900,
          velocity: 2000,
          viewportWidth: 400,
        ),
        2,
      );
      // Past the first member.
      expect(
        tabPagerSettleIndex(
          originIndex: 0,
          length: 3,
          displacement: -900,
          velocity: -2000,
          viewportWidth: 400,
        ),
        0,
      );
      // One member per drag, however far the finger went.
      expect(
        tabPagerSettleIndex(
          originIndex: 0,
          length: 6,
          displacement: 2400,
          velocity: 0,
          viewportWidth: 400,
        ),
        1,
      );
    });
  });

  group('indicator', () {
    test('tracks the page fraction linearly and stays on the rail', () {
      expect(tabPagerIndicatorPage(page: 0.5, length: 3), 0.5);
      expect(tabPagerIndicatorPage(page: -4, length: 3), 0);
      expect(tabPagerIndicatorPage(page: 9, length: 3), 2);
    });

    test('sits halfway between two labels at half a page', () {
      const rail = 400.0;
      const width = Space.s8;
      double at(double page) => tabPagerIndicatorOffset(
        page: page,
        length: 2,
        railWidth: rail,
        indicatorWidth: width,
      );
      expect(at(0), (rail / 2 - width) / 2);
      expect(at(1), rail / 2 + (rail / 2 - width) / 2);
      expect(at(0.5), closeTo((at(0) + at(1)) / 2, 0.001));
    });
  });

  test('overscroll travel is capped at the token allowance, both ends', () {
    double clamp(double value) => tabPagerClampedPixels(
      value: value,
      minScrollExtent: 0,
      maxScrollExtent: 800,
    );
    expect(clamp(-1000), -Drags.overscrollMax);
    expect(clamp(1800), 800 + Drags.overscrollMax);
    expect(clamp(400), 400);
  });

  test('settle and tap durations sit inside the ceiling', () {
    expect(
      tabPagerSettleDuration(reducedMotion: false),
      lessThanOrEqualTo(KDurations.deliberate),
    );
    expect(tabPagerSettleDuration(reducedMotion: true), KDurations.instant);
    expect(
      tabPagerTapDuration(reducedMotion: false).inMilliseconds,
      inInclusiveRange(160, KDurations.deliberate.inMilliseconds),
    );
    expect(tabPagerTapDuration(reducedMotion: true), KDurations.instant);
  });

  test('route parameters open a member, or degrade silently', () {
    const tabs = <KTabPagerTab>[
      KTabPagerTab(id: 'surf', label: 'Surf'),
      KTabPagerTab(id: 'pulse', label: 'Pulse'),
    ];
    int at(String? param, {int selected = 0}) => tabPagerInitialIndex(
      tabs: tabs,
      routeParam: param,
      selectedIndex: selected,
    );
    expect(at('pulse'), 1);
    expect(at('nope'), 0);
    expect(at(''), 0);
    expect(at(null, selected: 1), 1);
    expect(at(null, selected: 9), 1);
  });

  // ───────────────────────────────────────────────────── the widget ──

  const tabs = <KTabPagerTab>[
    KTabPagerTab(id: 'a', label: 'For you'),
    KTabPagerTab(id: 'b', label: 'Following'),
    KTabPagerTab(id: 'c', label: 'Nearby'),
  ];
  const viewport = 400.0;

  /// Pumps a pager whose selection the harness owns, mirroring real callers.
  Future<List<int>> pumpPager(
    WidgetTester tester, {
    List<KTabPagerTab> members = tabs,
    int initial = 0,
    bool reduced = false,
  }) async {
    final selections = <int>[];
    var selected = initial;
    await pumpKlect(
      tester,
      SizedBox(
        width: viewport,
        height: viewport,
        child: StatefulBuilder(
          builder: (context, setState) => KTabPager(
            tabs: members,
            selectedIndex: selected,
            onSelected: (index) {
              selections.add(index);
              setState(() => selected = index);
            },
            builder: (context, index) => SizedBox.expand(
              key: ValueKey<String>('page-$index'),
              child: Center(child: Text('page-$index')),
            ),
          ),
        ),
      ),
      disableAnimations: reduced,
    );
    await tester.pumpAndSettle();
    return selections;
  }

  /// A drag at a controlled speed: [dx] logical pixels over [steps] frames of
  /// [frame] each, so the release velocity is `dx / steps / frame`.
  Future<TestGesture> dragBy(
    WidgetTester tester,
    double dx, {
    int steps = 15,
    Duration frame = const Duration(milliseconds: 50),
    bool release = true,
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(frame);
    }
    if (release) {
      await gesture.up();
      await tester.pumpAndSettle();
    }
    return gesture;
  }

  testWidgets('renders one member across the full viewport at rest', (
    tester,
  ) async {
    await pumpPager(tester);
    expect(find.text('page-0'), findsOneWidget);
    expect(find.text('page-1'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('page-0'))).width,
      viewport,
    );
  });

  testWidgets('a drag past the commit distance selects the next member', (
    tester,
  ) async {
    final selections = await pumpPager(tester);
    // 150 px of 400 is past the quarter, at 200 px/s — under the fling floor.
    await dragBy(tester, -150);
    expect(selections, <int>[1]);
    expect(find.text('page-1'), findsOneWidget);
  });

  testWidgets('a short slow drag settles back and leaves the selection', (
    tester,
  ) async {
    final selections = await pumpPager(tester, initial: 1);
    // 60 px of 400 at 200 px/s: under both thresholds.
    await dragBy(tester, -60, steps: 6);
    expect(selections, isEmpty);
    expect(find.text('page-1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('page-1'))).dx,
      closeTo(tester.getTopLeft(find.byType(PageView)).dx, 0.5),
    );
  });

  testWidgets('an interrupted drag cannot leave a fractional page at rest', (
    tester,
  ) async {
    final selections = await pumpPager(tester);
    final pageLeft = tester.getTopLeft(find.byType(PageView)).dx;
    final gesture = await dragBy(tester, -140, release: false);

    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(selections, isEmpty);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('page-0'))).dx,
      closeTo(pageLeft, 0.5),
    );
  });

  testWidgets('a drag past the first member neither wraps nor overtravels', (
    tester,
  ) async {
    final selections = await pumpPager(tester);
    final origin = tester.getTopLeft(find.byType(PageView)).dx;
    await dragBy(tester, 300, steps: 30, release: false);
    final travelled =
        tester.getTopLeft(find.byKey(const ValueKey<String>('page-0'))).dx -
        origin;
    expect(travelled, lessThanOrEqualTo(Drags.overscrollMax + 0.5));
    expect(find.text('page-2'), findsNothing);
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
  });

  testWidgets('below two members no paging drag is accepted', (tester) async {
    await pumpPager(
      tester,
      members: const <KTabPagerTab>[KTabPagerTab(id: 'a', label: 'Only')],
    );
    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets('a label tap animates to that member', (tester) async {
    final selections = await pumpPager(tester);
    await tester.tap(find.text('Nearby'));
    await tester.pumpAndSettle();
    expect(selections, <int>[2]);
    expect(find.text('page-2'), findsOneWidget);
  });

  testWidgets('reduced motion changes page without sliding, inside 90 ms', (
    tester,
  ) async {
    final selections = await pumpPager(tester, reduced: true);
    final origin = tester
        .getTopLeft(find.byKey(const ValueKey<String>('page-0')))
        .dx;

    final gesture = await dragBy(tester, -150, release: false);
    // No slide transform: the page stays where it was while the finger moves.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey<String>('page-0'))).dx,
      closeTo(origin, 0.5),
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(KDurations.instant);
    expect(selections, <int>[1]);
    await tester.pumpAndSettle();
  });
}
