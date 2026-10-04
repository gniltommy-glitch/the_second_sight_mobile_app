/// Vietnamese voice-command parsing for hands-free navigation.
///
/// Pure Dart (no Flutter) so it can be unit tested.
library;

enum VoiceCommand { go, stop, where, repeat, unknown }

class VoiceIntent {
  final VoiceCommand command;

  /// Destination phrase for [VoiceCommand.go], e.g. "chợ bến thành".
  final String? destination;
  const VoiceIntent(this.command, [this.destination]);

  @override
  String toString() => 'VoiceIntent($command, $destination)';
}

const _accents = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

/// Lowercase and strip Vietnamese diacritics ("Điểm Đến" → "diem den").
String fold(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    var out = ch;
    for (final e in _accents.entries) {
      if (e.value.contains(ch)) {
        out = e.key;
        break;
      }
    }
    b.write(out);
  }
  return b.toString();
}

// Phrases (accent-folded) that introduce the destination. Longest first.
const _destMarkers = [
  'diem den cua toi la',
  'diem den hom nay la',
  'diem den la',
  'diem den',
  'noi den la',
  'noi den',
  'dan duong den',
  'dan duong toi',
  'chi duong den',
  'chi duong toi',
  'dua toi den',
  'dua toi toi',
  'dua toi ve',
  'dua toi',
  'toi muon di den',
  'toi muon di toi',
  'toi muon den',
  'toi muon toi',
  'toi muon ve',
  'toi muon di',
  'muon di den',
  'muon di',
  'di den',
  'di toi',
  'di ve',
  'den',
  'toi',
  've',
];

// Filler words that may precede/follow the actual place name.
final _leadingFiller = RegExp(
  r'^(aurealia oi|aurealia|aurelia oi|aurelia|oi|hom nay|bay gio|lam on|xin hay|hay|cho toi|giup toi|toi|di)\s+',
);
final _trailingFiller = RegExp(
  r'\s+(nhe|nha|di|a|voi|giup toi|duoc khong|lam on|ngay)$',
);

/// Parse what the user said into a [VoiceIntent].
VoiceIntent parseIntent(String raw) {
  final original = raw.trim().replaceAll(RegExp(r'[.,!?;:]'), ' ');
  final words = original.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final origWords = words.toList();
  final foldedWords = origWords.map(fold).toList();
  var folded = foldedWords.join(' ');
  if (RegExp(r'^(aurelia|aurealia)( oi)?$').hasMatch(folded)) {
    return const VoiceIntent(VoiceCommand.unknown);
  }
  if (folded.isEmpty) return const VoiceIntent(VoiceCommand.unknown);

  bool has(List<String> keys) =>
      keys.any((k) => RegExp('(^| )$k( |\$)').hasMatch(folded));

  if (has(['dung lai', 'ket thuc', 'huy hanh trinh', 'dung dan duong']) ||
      const {'dung', 'dung di', 'huy', 'thoi'}.contains(folded)) {
    return const VoiceIntent(VoiceCommand.stop);
  }
  if (has(['toi dang o dau', 'day la dau', 'vi tri cua toi'])) {
    return const VoiceIntent(VoiceCommand.where);
  }
  if (has(['lap lai', 'noi lai'])) {
    return const VoiceIntent(VoiceCommand.repeat);
  }

  // Find the first destination marker and take everything after it.
  var start = -1;
  for (final m in _destMarkers) {
    final mw = m.split(' ');
    for (var i = 0; i + mw.length <= foldedWords.length; i++) {
      var ok = true;
      for (var j = 0; j < mw.length; j++) {
        if (foldedWords[i + j] != mw[j]) {
          ok = false;
          break;
        }
      }
      // Marker must be followed by at least one word ("nhà tôi" ≠ "tới").
      if (ok && i + mw.length < foldedWords.length) {
        start = i + mw.length;
        break;
      }
    }
    if (start >= 0) break;
  }

  // No marker: treat the whole utterance as a place name.
  var dest = (start >= 0 ? origWords.sublist(start) : origWords).join(' ');
  // Drop "còn nơi đi là …" / "từ …" (origin is always GPS).
  dest = dest
      .split(
        RegExp(
          r'\s+(còn |con |và |va )?(nơi đi|noi di|điểm đi|diem di|xuất phát|xuat phat|đi từ|di tu)(\s|$)',
          caseSensitive: false,
        ),
      )
      .first;

  // Strip fillers (compare folded, cut original by word count).
  var w = dest.split(' ').where((x) => x.isNotEmpty).toList();
  while (w.isNotEmpty) {
    final f = fold(w.join(' '));
    final lead = _leadingFiller.firstMatch('$f ');
    if (lead != null && w.length > 1) {
      final n = lead.group(0)!.trim().split(' ').length;
      w = w.sublist(n);
      continue;
    }
    final trail = _trailingFiller.firstMatch(f);
    if (trail != null && w.length > 1) {
      final n = trail.group(0)!.trim().split(' ').length;
      w = w.sublist(0, w.length - n);
      continue;
    }
    if (const {'là', 'la'}.contains(w.first.toLowerCase()) && w.length > 1) {
      w = w.sublist(1);
      continue;
    }
    break;
  }
  dest = w.join(' ').trim();
  folded = fold(dest);
  if (dest.length < 2 || const {'la', 'den', 'toi', 'di'}.contains(folded)) {
    return const VoiceIntent(VoiceCommand.unknown);
  }
  return VoiceIntent(VoiceCommand.go, dest);
}
