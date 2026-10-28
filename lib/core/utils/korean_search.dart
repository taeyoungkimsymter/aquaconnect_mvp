import '../../data/models/farm.dart';

/// Search that works the way Korean users type: spaces and case are ignored,
/// a query of initial consonants matches ("ㅇㄷ" → 완도), and so does a
/// syllable still being composed at the end ("완ㄷ" → 완도).

const _initials = [
  'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', //
  'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
];

bool _isSyllable(int c) => c >= 0xAC00 && c <= 0xD7A3;

bool _isInitialJamo(String ch) => _initials.contains(ch);

String? _initialOf(String ch) {
  final c = ch.codeUnitAt(0);
  return _isSyllable(c) ? _initials[(c - 0xAC00) ~/ 588] : null;
}

String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Whether [query] occurs in [text] under the rules above.
bool koreanMatches(String text, String query) {
  final q = _normalize(query);
  if (q.isEmpty) return true;
  final t = _normalize(text);
  if (t.contains(q)) return true;
  final tc = t.split('');
  final qc = q.split('');
  outer:
  for (var start = 0; start + qc.length <= tc.length; start++) {
    for (var i = 0; i < qc.length; i++) {
      final want = qc[i];
      final have = tc[start + i];
      if (want == have) continue;
      if (_isInitialJamo(want) && _initialOf(have) == want) continue;
      continue outer;
    }
    return true;
  }
  return false;
}

/// A farm matches on its name, address, region, nearest station or 담당자.
bool farmMatches(Farm farm, String query) => [
      farm.name,
      farm.address,
      farm.region,
      farm.nearestStationName,
      farm.assignedMemberName ?? '',
    ].any((field) => koreanMatches(field, query));

/// [farms] matching [query], best first: names that start with it, then
/// names that contain it, then the rest (address/담당자 hits).
List<Farm> searchFarms(Iterable<Farm> farms, String query) {
  final q = query.trim();
  final list = farms.toList();
  if (q.isEmpty) return list;
  int rank(Farm f) {
    final name = _normalize(f.name);
    final nq = _normalize(q);
    if (name.startsWith(nq)) return 0;
    if (koreanMatches(f.name, q)) return 1;
    return 2;
  }

  // Ties keep the incoming order (List.sort isn't stable).
  final hits = [for (final (i, f) in list.indexed) if (farmMatches(f, q)) (i, rank(f), f)];
  hits.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
  return [for (final h in hits) h.$3];
}
