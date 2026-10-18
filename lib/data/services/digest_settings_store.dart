import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// "업무 알림 설정" — the member's 미완료된 업무 / 오늘 해야할 일 notification
/// preferences (they replaced the 하루 요약 / 주간 요약; field names are kept), chosen in
/// MyPage. The server sends the summaries (server/src/lib/digest.js), so in
/// the real app they live on the server ([RemoteDigestSettingsStore]); mock
/// mode keeps them on the device ([LocalDigestSettingsStore]).
class DigestSettings {
  const DigestSettings({
    required this.dailyEnabled,
    required this.dailyTime,
    required this.weeklyEnabled,
  });

  static const defaults = DigestSettings(
    dailyEnabled: true,
    dailyTime: TimeOfDay(hour: 8, minute: 30),
    weeklyEnabled: true,
  );

  /// 미완료된 업무 알림 on/off.
  final bool dailyEnabled;

  /// Korean time. One send time for both notifications.
  final TimeOfDay dailyTime;

  /// 오늘 해야할 일 알림 on/off (sent at [dailyTime] too).
  final bool weeklyEnabled;

  DigestSettings copyWith({bool? dailyEnabled, TimeOfDay? dailyTime, bool? weeklyEnabled}) {
    return DigestSettings(
      dailyEnabled: dailyEnabled ?? this.dailyEnabled,
      dailyTime: dailyTime ?? this.dailyTime,
      weeklyEnabled: weeklyEnabled ?? this.weeklyEnabled,
    );
  }

  /// "08:30" — the server's format.
  String get dailyTimeKey =>
      '${dailyTime.hour.toString().padLeft(2, '0')}:${dailyTime.minute.toString().padLeft(2, '0')}';

  factory DigestSettings.fromJson(Map<String, dynamic> json) {
    final parts = (json['dailyTime'] as String? ?? '08:30').split(':');
    return DigestSettings(
      dailyEnabled: json['dailyEnabled'] as bool? ?? defaults.dailyEnabled,
      dailyTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 8, minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 30),
      weeklyEnabled: json['weeklyEnabled'] as bool? ?? defaults.weeklyEnabled,
    );
  }

  Map<String, dynamic> toJson() => {'dailyEnabled': dailyEnabled, 'dailyTime': dailyTimeKey, 'weeklyEnabled': weeklyEnabled};
}

abstract class DigestSettingsStore {
  Future<DigestSettings> read();

  Future<DigestSettings> write(DigestSettings settings);
}

class RemoteDigestSettingsStore implements DigestSettingsStore {
  RemoteDigestSettingsStore({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  @override
  Future<DigestSettings> read() async =>
      DigestSettings.fromJson(await _api.get('/api/notifications/digest') as Map<String, dynamic>);

  @override
  Future<DigestSettings> write(DigestSettings settings) async =>
      DigestSettings.fromJson(await _api.put('/api/notifications/digest', body: settings.toJson()) as Map<String, dynamic>);
}

class LocalDigestSettingsStore implements DigestSettingsStore {
  static const _dailyEnabledKey = 'aquaconnect.digest.daily_enabled';
  static const _dailyHourKey = 'aquaconnect.digest.daily_hour';
  static const _dailyMinuteKey = 'aquaconnect.digest.daily_minute';
  static const _weeklyEnabledKey = 'aquaconnect.digest.weekly_enabled';

  @override
  Future<DigestSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = DigestSettings.defaults;
    return DigestSettings(
      dailyEnabled: prefs.getBool(_dailyEnabledKey) ?? defaults.dailyEnabled,
      dailyTime: TimeOfDay(
        hour: prefs.getInt(_dailyHourKey) ?? defaults.dailyTime.hour,
        minute: prefs.getInt(_dailyMinuteKey) ?? defaults.dailyTime.minute,
      ),
      weeklyEnabled: prefs.getBool(_weeklyEnabledKey) ?? defaults.weeklyEnabled,
    );
  }

  @override
  Future<DigestSettings> write(DigestSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyEnabledKey, settings.dailyEnabled);
    await prefs.setInt(_dailyHourKey, settings.dailyTime.hour);
    await prefs.setInt(_dailyMinuteKey, settings.dailyTime.minute);
    await prefs.setBool(_weeklyEnabledKey, settings.weeklyEnabled);
    return settings;
  }
}
