import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ocean_reading.dart';
import '../models/red_tide.dart';
import 'ocean_service.dart';

/// Talks to the `server/` API's `/api/ocean/*` routes, which wrap the NIFS
/// `risaList` OpenAPI so Flutter Web never hits it (and its CORS policy)
/// directly.
///
/// `risaList` only reports the current water temperature per station; 적조
/// 속보 come from `/api/ocean/redtide` (NIFS `redtideList`/`redtideDetail`).
/// See `server/README.md` for the API contract.
class RailwayOceanService implements OceanService {
  RailwayOceanService({required String baseUrl, http.Client? client})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  /// Preference order when a station reports more than one depth: farmed
  /// fish live at mid/bottom depth, not the surface, so 저층 (bottom) wins
  /// over 중층 (mid) wins over 표층 (surface) whenever more than one is
  /// available for the same station.
  static const _layerPriority = ['저층', '중층', '표층'];

  OceanObservation? _pickPreferred(List<OceanObservation> observations) {
    final withTemp = observations.where((o) => o.waterTempC != null).toList();
    for (final layer in _layerPriority) {
      for (final o in withTemp) {
        if (o.layer == layer) return o;
      }
    }
    return withTemp.isEmpty ? null : withTemp.first;
  }

  @override
  Future<List<OceanObservation>> fetchRealtime({String? station}) async {
    final uri = Uri.parse('$_baseUrl/api/ocean/realtime').replace(
      queryParameters: station == null ? null : {'station': station},
    );
    final response = await _client.get(uri, headers: const {'Accept': 'application/json'});
    if (response.statusCode != 200) {
      throw Exception('실시간 수온 조회 실패 (HTTP ${response.statusCode})');
    }
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((e) => OceanObservation.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<OceanSnapshot> fetchSnapshot({
    required String stationCode,
    required String stationName,
    required String region,
    bool refresh = false,
  }) async {
    final observations = await fetchRealtime(station: stationCode);
    final picked = _pickPreferred(observations);

    if (picked == null) {
      throw Exception('$stationName 관측소의 수온 데이터를 찾을 수 없습니다.');
    }

    return OceanSnapshot(
      region: region,
      stationName: picked.stationName,
      waterTemp: picked.waterTempC!,
      layer: picked.layer,
      observedAt: parseObservationTime(picked.observedDate, picked.observedTime),
      fetchedAt: DateTime.now(),
      source: 'NIFS RISA (실시간 수온) · NIFS 적조정보',
    );
  }

  @override
  Future<RedTideInfo> fetchRedTide({bool refresh = false}) async {
    final uri = Uri.parse('$_baseUrl/api/ocean/redtide').replace(queryParameters: refresh ? {'refresh': '1'} : null);
    final response = await _client.get(uri, headers: const {'Accept': 'application/json'});
    if (response.statusCode != 200) {
      throw Exception('적조 정보 조회 실패 (HTTP ${response.statusCode})');
    }
    return RedTideInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<List<OceanStation>> fetchStations() async {
    final observations = await fetchRealtime();
    final byCode = <String, (String name, Set<String> layers)>{};
    for (final o in observations) {
      if (o.stationCode == '-' || o.waterTempC == null) continue;
      byCode.putIfAbsent(o.stationCode, () => (o.stationName, <String>{})).$2.add(o.layer);
    }
    final stations = byCode.entries.map((e) {
      final layers = sortLayersTopDown(e.value.$2);
      final info = oceanStationCatalog[e.key];
      return info != null
          ? OceanStation.fromCatalog(info, layers: layers)
          : OceanStation(code: e.key, name: e.value.$1, layers: layers);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return stations;
  }
}
