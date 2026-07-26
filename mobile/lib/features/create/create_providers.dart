import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../core/storage/key_value_store.dart';

/// The interest templates offered when a new shelf is created.
final createTemplatesProvider = FutureProvider<List<CollectionTemplate>>(
  (ref) => ref.watch(klectApiProvider).fetchCollectionTemplates(),
  name: 'createTemplates',
);

/// Remembers where the user last filed something.
///
/// The create flow has to be reachable in three taps from anywhere, and the
/// only way to make the third tap land on a form that is already correct is to
/// remember the last destination.
class CreateDefaults {
  /// Wraps the durable store.
  const CreateDefaults(this._store);

  static const String _collectionKey = 'klect.create.lastCollection';
  static const String _subcollectionKey = 'klect.create.lastSubcollection';

  final KeyValueStore _store;

  /// The collection the user last filed something into.
  String? get collectionId => _emptyToNull(_store.getString(_collectionKey));

  /// The subcollection the user last filed something into.
  String? get subcollectionId =>
      _emptyToNull(_store.getString(_subcollectionKey));

  /// Records a successful create.
  Future<void> remember({String? collectionId, String? subcollectionId}) async {
    if (collectionId != null) {
      await _store.setString(_collectionKey, collectionId);
    }
    if (subcollectionId != null) {
      await _store.setString(_subcollectionKey, subcollectionId);
    }
  }

  /// Forgets a destination that no longer exists.
  Future<void> forget() async {
    await _store.remove(_collectionKey);
    await _store.remove(_subcollectionKey);
  }

  static String? _emptyToNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;
}

/// The remembered create destination.
final createDefaultsProvider = Provider<CreateDefaults>(
  (ref) => CreateDefaults(ref.watch(keyValueStoreProvider)),
  name: 'createDefaults',
);

/// Common condition grades, offered as chips over the free-text column.
const List<String> kConditionOptions = <String>[
  'mint',
  'near mint',
  'excellent',
  'good',
  'fair',
  'poor',
];

/// Common rarity grades, offered as chips over the free-text column.
const List<String> kRarityOptions = <String>[
  'common',
  'uncommon',
  'rare',
  'very rare',
  'grail',
];

/// Currencies offered next to `purchase_price`.
const List<String> kCurrencyOptions = <String>[
  'USD',
  'EUR',
  'GBP',
  'JPY',
  'AUD',
  'CAD',
  'INR',
];
