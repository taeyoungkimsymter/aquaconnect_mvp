import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Design tokens for the farm-side shared report page (green palette,
/// distinct from the institute app's blue one).
class SharedTokens {
  SharedTokens._();

  static const maxWidth = 480.0;

  static const primary = Color(0xFF0F6E56);
  static const secondary = Color(0xFF1C9C82);
  static const accent = Color(0xFF1C9C82);
  static const amber = Color(0xFFE8A33D);
  static const urgent = Color(0xFFD85A30);

  static const outerBg = Color(0xFFDCE7E2);
  static const bg = Color(0xFFEEF4F1);
  static const card = Colors.white;
  static const line = Color(0xFFE1EAE6);
  static const text = Color(0xFF16241E);
  static const textSub = Color(0xFF5B6E66);
  static const scrim = Color(0x8C0C1626);
}

Future<void> launchExternal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
