import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/notification_providers.dart';
import 'core/providers/repository_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class AquaConnectApp extends ConsumerStatefulWidget {
  const AquaConnectApp({super.key});

  @override
  ConsumerState<AquaConnectApp> createState() => _AquaConnectAppState();
}

class _AquaConnectAppState extends ConsumerState<AquaConnectApp> {
  StreamSubscription<Map<String, String?>>? _pushMessages;

  @override
  void initState() {
    super.initState();
    // Messages from push_sw.js: refresh the 알림함 when a push lands, and
    // open the right screen when its notification is tapped while the app
    // is already open.
    _pushMessages = ref.read(webPushServiceProvider).workerMessages().listen((message) {
      ref.invalidate(notificationFeedProvider);
      final link = message['link'];
      if (message['type'] == 'aquaconnect-open' && link != null) openAppLink(ref.read(routerProvider), link);
    });
  }

  @override
  void dispose() {
    _pushMessages?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // After every sign-in (including a restored session), make sure this
    // browser — if it already allowed notifications — is registered to the
    // member now signed in.
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.valueOrNull == null && next.valueOrNull != null) {
        ref.read(pushControllerProvider).syncIfGranted();
      }
    });

    return MaterialApp.router(
      title: 'AquaConnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
