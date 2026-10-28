import '../models/ocean_reading.dart';
import '../models/red_tide.dart';

/// Fetches ocean environment data. Real-time values are proxied through the
/// `ocean_service` Node app (deployed on Railway) so the Flutter Web build
/// never calls the NIFS API directly and hits its CORS restrictions.
abstract class OceanService {
  Future<OceanSnapshot> fetchSnapshot({
    required String stationCode,
    required String stationName,
    required String region,
    bool refresh = false,
  });

  Future<List<OceanObservation>> fetchRealtime({String? station});

  /// The newest NIFS 적조 속보 and the recent ones; `refresh` bypasses the
  /// server cache.
  Future<RedTideInfo> fetchRedTide({bool refresh = false});

  /// Lists the stations selectable as a "바다 위치" in MyPage — only those
  /// publishing a 중층 or 저층 reading (surface-only stations are excluded
  /// since farmed fish live below the surface, not at it).
  Future<List<OceanStation>> fetchStations();
}
