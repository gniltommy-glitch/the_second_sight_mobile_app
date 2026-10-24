/// Vietnamese voice-command parsing for hands-free navigation.
///
/// Pure Dart (no Flutter) so it can be unit tested.
library;

enum VoiceCommand {
  go,
  stop,
  where,
  repeat,
  remaining,
  call,
  shareLocation,
  endCall,
  cancelEmergency,
  unknown,
}

class VoiceIntent {
  final VoiceCommand command;

  /// Destination phrase for [VoiceCommand.go], e.g. "chợ bến thành".
  final String? destination;

  /// Recipient for [VoiceCommand.call] or [VoiceCommand.shareLocation], e.g. "Mẹ", "115", "tất cả".
  final String? recipient;

  const VoiceIntent(this.command, [this.destination, this.recipient]);

  @override
  String toString() => 'VoiceIntent($command, dest: $destination, rec: $recipient)';
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

// Markers that indicate sharing GPS location. Longest first.
const _shareMarkers = [
  'chia se vi tri cho',
  'chia se vi tri toi',
  'chia se vi tri',
  'chia se toa do cho',
  'chia se toa do',
  'chia se gps cho',
  'chia se gps toi',
  'chia se gps',
  'gui vi tri cho',
  'gui vi tri toi',
  'gui vi tri',
  'gui toa do cho',
  'gui toa do',
  'gui gps cho',
  'gui gps',
  'ban vi tri cho',
  'ban vi tri',
  'ban gps cho',
  'ban gps',
];

// Markers that indicate a phone call. Longest first.
const _callMarkers = [
  'goi dien thoai cho',
  'goi dien cho',
  'dien thoai cho',
  'dien cho',
  'goi cho',
  'goi ngay cho',
  'goi ngay',
  'goi',
];

// Filler words that may precede/follow the actual place name.
final _leadingFiller = RegExp(
  r'^(aurealia oi|aurealia|aurelia oi|aurelia|oi|hom nay|bay gio|lam on|xin hay|hay|cho toi|giup toi|toi|di)\s+',
);
final _trailingFiller = RegExp(
  r'\s+(nhe|nhé|nha|di|đi|a|ạ|voi|với|giup toi|giúp tôi|duoc khong|được không|lam on|làm ơn|ngay)$',
  caseSensitive: false,
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

  // 1. Cancel Emergency Flow
  if (has(['huy khan cap', 'dung khan cap', 'toi on', 'khong can giup', 'khong can nua'])) {
    return const VoiceIntent(VoiceCommand.cancelEmergency);
  }

  // 2. End Call
  if (has([
    'ket thuc cuoc goi',
    'dung cuoc goi',
    'ngat cuoc goi',
    'tat cuoc goi',
    'dung goi',
    'tat may',
    'ngat may',
    'ket thuc goi',
  ])) {
    return const VoiceIntent(VoiceCommand.endCall);
  }

  // 3. Navigation Controls
  if (has(['dung lai', 'ket thuc', 'huy hanh trinh', 'dung dan duong']) ||
      const {'dung', 'dung di', 'huy', 'thoi'}.contains(folded)) {
    return const VoiceIntent(VoiceCommand.stop);
  }
  if (has(['toi dang o dau', 'day la dau', 'vi tri cua toi'])) {
    return const VoiceIntent(VoiceCommand.where);
  }
  if (has(['lap lai', 'noi lai', 'nhac lai'])) {
    return const VoiceIntent(VoiceCommand.repeat);
  }

  if (has(['con bao xa', 'bao xa nua', 'khoang cach con lai'])) {
    return const VoiceIntent(VoiceCommand.remaining);
  }

  // Strip leading wake/filler words to parse clean command
  var cleanWords = origWords;
  var cleanFoldedWords = foldedWords;
  final lead = _leadingFiller.firstMatch('$folded ');
  if (lead != null) {
    final n = lead.group(0)!.trim().split(RegExp(r'\s+')).length;
    if (n < origWords.length) {
      cleanWords = origWords.sublist(n);
      cleanFoldedWords = foldedWords.sublist(n);
    }
  }

  // 4. Share Location Command
  for (final m in _shareMarkers) {
    final mw = m.split(' ');
    for (var i = 0; i + mw.length <= cleanFoldedWords.length; i++) {
      var ok = true;
      for (var j = 0; j < mw.length; j++) {
        if (cleanFoldedWords[i + j] != mw[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        final start = i + mw.length;
        var recipient = '';
        if (start < cleanWords.length) {
          recipient = cleanWords.sublist(start).join(' ');
          recipient = recipient.replaceAll(_trailingFiller, '').trim();
        }
        return VoiceIntent(
          VoiceCommand.shareLocation,
          null,
          recipient.isEmpty ? null : recipient,
        );
      }
    }
  }

  // 5. Direct Phone Call Command
  if (!cleanFoldedWords.join(' ').startsWith('goi lai')) {
    for (final m in _callMarkers) {
      final mw = m.split(' ');
      if (mw.length <= cleanFoldedWords.length) {
        var ok = true;
        for (var j = 0; j < mw.length; j++) {
          if (cleanFoldedWords[j] != mw[j]) {
            ok = false;
            break;
          }
        }
        if (ok && mw.length < cleanWords.length) {
          var recipient = cleanWords.sublist(mw.length).join(' ');
          recipient = recipient.replaceAll(_trailingFiller, '').trim();
          if (recipient.isNotEmpty) {
            return VoiceIntent(VoiceCommand.call, null, recipient);
          }
        }
      }
    }
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

// ─── Destination confirmation ────────────────────────────────────

/// Answer to "Bạn muốn đến … đúng không?".
enum YesNo { yes, no, cancel, unclear }

// Accent-folded phrases. Order of checks matters: affirmations that contain a
// cancel/negation word ("đi thôi", "không sai") → cancel → negations →
// affirmations, so "không phải" is never read as "phải" and "không đúng"
// never as "đúng".
const _strongYes = ['di thoi', 'khong sai'];
const _cancelWords = [
  'huy',
  'thoi',
  'dung lai',
  'bo qua',
  'khong di nua',
  'khong di dau',
];
const _noWords = [
  'khong',
  'sai',
  'nham',
  'cho khac',
  'cai khac',
  'noi khac',
  'chua dung',
  'khong phai',
];
const _yesWords = [
  'co',
  'dung',
  'dung roi',
  'phai',
  'phai roi',
  'vang',
  'da',
  'u',
  'um',
  'uh',
  'ok',
  'oke',
  'okay',
  'dong y',
  'chinh xac',
  'duoc',
  'chuan',
  'yes',
];

/// Classify a spoken reply to a yes/no confirmation question.
YesNo parseYesNo(String raw) {
  final words = fold(raw)
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .trim()
      .split(RegExp(r'\s+'));
  final text = ' ${words.join(' ')} ';
  if (text.trim().isEmpty) return YesNo.unclear;
  bool has(List<String> phrases) => phrases.any((p) => text.contains(' $p '));
  if (has(_strongYes)) return YesNo.yes;
  if (has(_cancelWords)) return YesNo.cancel;
  if (has(_noWords)) return YesNo.no;
  if (has(_yesWords)) return YesNo.yes;
  return YesNo.unclear;
}

/// "850 mét" / "1,2 ki-lô-mét", rounded the way a person would say it.
String spokenDistance(double meters) {
  if (meters < 1000) {
    final rounded = meters < 100
        ? (meters / 10).round() * 10
        : (meters / 50).round() * 50;
    return '${rounded < 10 ? 10 : rounded} mét';
  }
  final km = (meters / 100).round() / 10;
  final text = km == km.roundToDouble()
      ? km.toStringAsFixed(0)
      : km.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ki-lô-mét';
}

/// Confirmation sentence for one candidate.
///
/// [sameName] is how many search results share this name; when > 1 the user
/// is told so, because "đúng không?" alone hides that other places exist.
/// [alternative] phrases follow-up candidates as "Vậy có phải … không?".
String confirmQuestion(
  String name, {
  String address = '',
  double? distanceM,
  int sameName = 1,
  bool alternative = false,
}) {
  final where = address.isEmpty ? '' : ' tại $address';
  final far = distanceM == null || !distanceM.isFinite
      ? ''
      : ', cách khoảng ${spokenDistance(distanceM)}';
  if (alternative) return 'Vậy có phải $name$where$far không?';
  final count = sameName > 1 ? 'Có $sameName nơi tên $name. ' : '';
  return '${count}Bạn muốn đến $name$where$far, đúng không?';
}

/// Only a wake phrase at the beginning of an utterance activates Aurelia.
/// Returns null for unrelated speech, or the command after the phrase.
String? wakeCommand(String raw) {
  final words = raw
      .trim()
      .replaceAll(RegExp(r'[.,!?;:]'), ' ')
      .split(RegExp(r'\s+'));
  final text = words.map(fold).join(' ');
  final match = RegExp(
    r'^(?:(?:hey|hay|hei) (?:aurelia|aurealia|auralia|au re lia|o re lia)|(?:aurelia|aurealia|auralia|au re lia|o re lia) oi)( |$)',
  ).firstMatch(text);
  if (match == null) return null;
  return words.skip(match.group(0)!.trim().split(' ').length).join(' ');
}
