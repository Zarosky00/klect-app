import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'app.dart';
import 'core/storage/key_value_store.dart';
import 'core/supabase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  // "2 minutes ago" reads better than "2 min. ago" in the feed.
  timeago.setLocaleMessages('en', timeago.EnShortMessages());

  await KlectSupabase.initialize();
  final store = await PrefsKeyValueStore.load();

  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
      ],
      child: const KlectApp(),
    ),
  );
}
