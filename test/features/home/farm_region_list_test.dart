import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquaconnect_mvp/data/models/farm.dart';
import 'package:aquaconnect_mvp/data/models/risk_level.dart';
import 'package:aquaconnect_mvp/features/home/farm_region_list.dart';

Farm _farm(int i, String address, {String? contact}) => Farm(
      id: 'f$i',
      orgId: 'o',
      name: '테스트$i양식장',
      region: '정거장',
      address: address,
      nearestStationCode: 'c',
      nearestStationName: 'n',
      riskLevel: RiskLevel.good,
      headline: '',
      ownerContact: contact,
    );

Future<void> _pump(WidgetTester t, List<Farm> farms) async {
  await t.binding.setSurfaceSize(const Size(360, 800));
  await t.pumpWidget(ProviderScope(
    overrides: const [],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: FarmRegionList(farmsAsync: AsyncData(farms), onRetry: () {})))),
  ));
  await t.pumpAndSettle();
}

void main() {
  final farms = [
    for (var i = 0; i < 20; i++) _farm(i, '전남 고흥군 도양읍 $i', contact: '010-0000-${1000 + i}'),
    for (var i = 20; i < 30; i++) _farm(i, '전남 완도군 완도읍 $i'),
    for (var i = 30; i < 38; i++) _farm(i, '경남 통영시 산양읍 $i'),
    _farm(38, ''),
  ];

  testWidgets('collapsed by default, one region at a time', (t) async {
    await _pump(t, farms);
    expect(find.text('전체 39곳 · 4개 지역', findRichText: true), findsOneWidget);
    expect(find.textContaining('테스트'), findsNothing);
    await t.tap(find.text('고흥군'));
    await t.pumpAndSettle();
    expect(find.text('테스트0양식장'), findsOneWidget);
    await t.ensureVisible(find.text('완도군'));
    await t.tap(find.text('완도군'));
    await t.pumpAndSettle();
    expect(find.text('테스트0양식장'), findsNothing);
    expect(find.text('테스트20양식장'), findsOneWidget);
    expect(find.text('지역 미등록'), findsOneWidget);
  });

  testWidgets('menu selects region, search finds collapsed farms', (t) async {
    await _pump(t, farms);
    await t.tap(find.text('지역 전체'));
    await t.pumpAndSettle();
    expect(find.text('20곳'), findsNWidgets(2)); // 지역 행 + 메뉴
    await t.tap(find.text('통영시').last);
    await t.pumpAndSettle();
    expect(find.text('통영시'), findsWidgets);
    expect(find.text('테스트30양식장'), findsOneWidget);
    expect(find.text('테스트0양식장'), findsNothing);

    await t.tap(find.text('통영시').first); // header toggle? just reopen menu below
    await t.pumpAndSettle();
  });

  testWidgets('search across regions, chosung, clear', (t) async {
    await _pump(t, farms);
    await t.enterText(find.byType(TextField), '완도읍');
    await t.pumpAndSettle();
    expect(find.text('테스트25양식장'), findsOneWidget); // auto-opened single region
    await t.enterText(find.byType(TextField), '01000001005');
    await t.pumpAndSettle();
    expect(find.text('테스트5양식장'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'ㅌㅅㅌ');
    await t.pumpAndSettle();
    expect(find.text('고흥군'), findsOneWidget);
    await t.enterText(find.byType(TextField), '없는이름');
    await t.pumpAndSettle();
    expect(find.text('검색 결과가 없어요.'), findsOneWidget);
    await t.tap(find.byTooltip('검색어 지우기'));
    await t.pumpAndSettle();
    expect(find.text('고흥군'), findsOneWidget);
    expect(find.text('검색 결과가 없어요.'), findsNothing);
  });

  testWidgets('farm detail expands and empty state', (t) async {
    await _pump(t, farms);
    await t.tap(find.text('통영시'));
    await t.pumpAndSettle();
    await t.tap(find.text('테스트30양식장'));
    await t.pumpAndSettle();
    expect(find.text('상세 보기'), findsOneWidget);
    expect(find.text('미등록'), findsOneWidget);
    await t.tap(find.text('테스트31양식장'));
    await t.pumpAndSettle();
    expect(find.text('상세 보기'), findsOneWidget);
    await _pump(t, const []);
    expect(find.textContaining('등록된 양식장이 없어요'), findsOneWidget);
  });
}
