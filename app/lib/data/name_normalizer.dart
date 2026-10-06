import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Dart port of `names.py`. MUST stay behaviourally identical to it: the
/// `normalized_name` / `normalized_alias` columns in the shipped database were
/// produced by that Python module, so any divergence here means a perfectly
/// good answer stops matching and the player is told "we don't have that
/// player" about someone we plainly do have.
///
/// `test/name_parity_test.dart` checks this against 36,767 name/normalized
/// pairs exported from the real database. Run it after touching this file.
///
/// Python does `unicodedata.normalize('NFKD', text)` and then drops every
/// character with a nonzero canonical combining class. Dart has no
/// `unicodedata`, so this uses `unorm_dart` for the decomposition and the
/// range table below for the combining-class test.
///
/// A Latin-only fold (the `diacritic` package, say) is NOT sufficient and was
/// tried first: NFKD also decomposes Cyrillic и-breve, Greek accented vowels,
/// Arabic hamza-carriers and Hangul syllables, none of which such a table
/// touches. The parity test caught all of them.

/// Characters mapped before decomposition, either because decomposition gets
/// them wrong (Turkish dotless i, Nordic o-slash, German eszett) or because
/// there is no decomposition at all (Polish l-stroke).
const Map<String, String> _explicitMap = {
  'İ': 'i', 'I': 'i', 'ı': 'i', // Turkish dotted/dotless i
  'Ş': 's', 'ş': 's',
  'Ğ': 'g', 'ğ': 'g',
  'Ç': 'c', 'ç': 'c',
  'Ö': 'o', 'ö': 'o',
  'Ü': 'u', 'ü': 'u',
  'ß': 'ss',
  'Ø': 'o', 'ø': 'o',
  'Æ': 'ae', 'æ': 'ae',
  'Œ': 'oe', 'œ': 'oe',
  'Å': 'a', 'å': 'a',
  'Ł': 'l', 'ł': 'l',
  'Đ': 'd', 'đ': 'd',
  'Ð': 'd', 'ð': 'd',
  'Þ': 'th', 'þ': 'th',
  'Ñ': 'n', 'ñ': 'n',
};

/// Inclusive code-point ranges whose members have a NONZERO canonical
/// combining class — exactly what `unicodedata.combining(ch)` reports as
/// truthy, which is Python's test for "drop this".
///
/// Not every combining mark qualifies: U+034F COMBINING GRAPHEME JOINER and
/// most Indic vowel signs have combining class 0 and Python KEEPS them, so
/// stripping all marks by general category would over-strip. These ranges are
/// the class-nonzero ones, script by script.
const List<List<int>> _combiningRanges = [
  [0x0300, 0x034E], // combining diacriticals (0x034F is class 0 - excluded)
  [0x0350, 0x036F],
  [0x0483, 0x0487], // Cyrillic
  [0x0591, 0x05BD], // Hebrew points
  [0x05BF, 0x05BF],
  [0x05C1, 0x05C2],
  [0x05C4, 0x05C5],
  [0x05C7, 0x05C7],
  [0x0610, 0x061A], // Arabic
  [0x064B, 0x065F],
  [0x0670, 0x0670],
  [0x06D6, 0x06DC],
  [0x06DF, 0x06E4],
  [0x06E7, 0x06E8],
  [0x06EA, 0x06ED],
  [0x0711, 0x0711], // Syriac
  [0x0730, 0x074A],
  [0x07EB, 0x07F3], // NKo
  [0x0816, 0x0819], // Samaritan
  [0x081B, 0x0823],
  [0x0825, 0x0827],
  [0x0829, 0x082D],
  [0x0859, 0x085B], // Mandaic
  [0x08E3, 0x08FF], // Arabic extended
  [0x093C, 0x093C], // Devanagari nukta
  [0x094D, 0x094D], // virama
  [0x0951, 0x0954],
  [0x09BC, 0x09BC], // Bengali
  [0x09CD, 0x09CD],
  [0x0A3C, 0x0A3C], // Gurmukhi
  [0x0A4D, 0x0A4D],
  [0x0ABC, 0x0ABC], // Gujarati
  [0x0ACD, 0x0ACD],
  [0x0B3C, 0x0B3C], // Oriya
  [0x0B4D, 0x0B4D],
  [0x0BCD, 0x0BCD], // Tamil
  [0x0C4D, 0x0C4D], // Telugu
  [0x0C55, 0x0C56],
  [0x0CBC, 0x0CBC], // Kannada
  [0x0CCD, 0x0CCD],
  [0x0D4D, 0x0D4D], // Malayalam
  [0x0DCA, 0x0DCA], // Sinhala
  [0x0E38, 0x0E3A], // Thai
  [0x0E48, 0x0E4B],
  [0x0EB8, 0x0EB9], // Lao
  [0x0EC8, 0x0ECB],
  [0x0F18, 0x0F19], // Tibetan
  [0x0F35, 0x0F35],
  [0x0F37, 0x0F37],
  [0x0F39, 0x0F39],
  [0x0F71, 0x0F84],
  [0x0F86, 0x0F87],
  [0x0FC6, 0x0FC6],
  [0x1037, 0x1037], // Myanmar
  [0x1039, 0x103A],
  [0x108D, 0x108D],
  [0x135D, 0x135F], // Ethiopic
  [0x1714, 0x1714], // Tagalog
  [0x1734, 0x1734], // Hanunoo
  [0x17D2, 0x17D2], // Khmer
  [0x17DD, 0x17DD],
  [0x18A9, 0x18A9], // Mongolian
  [0x1939, 0x193B], // Limbu
  [0x1A17, 0x1A18], // Buginese
  [0x1A60, 0x1A60], // Tai Tham
  [0x1A75, 0x1A7C],
  [0x1A7F, 0x1A7F],
  [0x1AB0, 0x1ABD], // combining diacriticals extended
  [0x1B34, 0x1B34], // Balinese
  [0x1B44, 0x1B44],
  [0x1B6B, 0x1B73],
  [0x1BAA, 0x1BAB], // Sundanese
  [0x1BE6, 0x1BE6], // Batak
  [0x1BF2, 0x1BF3],
  [0x1C37, 0x1C37], // Lepcha
  [0x1CD0, 0x1CD2], // Vedic
  [0x1CD4, 0x1CE0],
  [0x1CE2, 0x1CE8],
  [0x1CED, 0x1CED],
  [0x1CF4, 0x1CF4],
  [0x1CF8, 0x1CF9],
  [0x1DC0, 0x1DF9], // combining diacriticals supplement
  [0x1DFB, 0x1DFF],
  [0x20D0, 0x20DC], // combining marks for symbols
  [0x20E1, 0x20E1],
  [0x20E5, 0x20F0],
  [0x2CEF, 0x2CF1], // Coptic
  [0x2D7F, 0x2D7F], // Tifinagh
  [0x2DE0, 0x2DFF], // Cyrillic extended
  [0x302A, 0x302F], // CJK tone marks
  [0x3099, 0x309A], // Japanese voiced sound marks
  [0xA66F, 0xA66F],
  [0xA674, 0xA67D],
  [0xA69E, 0xA69F],
  [0xA6F0, 0xA6F1],
  [0xA806, 0xA806],
  [0xA8C4, 0xA8C4],
  [0xA8E0, 0xA8F1],
  [0xA92B, 0xA92D],
  [0xA953, 0xA953],
  [0xA9B3, 0xA9B3],
  [0xA9C0, 0xA9C0],
  [0xAAB0, 0xAAB0],
  [0xAAB2, 0xAAB4],
  [0xAAB7, 0xAAB8],
  [0xAABE, 0xAABF],
  [0xAAC1, 0xAAC1],
  [0xAAF6, 0xAAF6],
  [0xABED, 0xABED],
  [0xFB1E, 0xFB1E], // Hebrew point judeo-spanish varika
  [0xFE20, 0xFE2F], // combining half marks
];

bool _isCombining(int cp) {
  var lo = 0;
  var hi = _combiningRanges.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final range = _combiningRanges[mid];
    if (cp < range[0]) {
      hi = mid - 1;
    } else if (cp > range[1]) {
      lo = mid + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Python's `[^\w\s]` with re.UNICODE keeps letters, digits and underscore.
final RegExp _punct = RegExp(r'[^\p{L}\p{N}_\s]', unicode: true);
final RegExp _whitespace = RegExp(r'\s+');

/// Fold a name down to a plain lowercase ASCII-ish key.
///
///     "Wesley Sneijder"  -> "wesley sneijder"
///     "Mesut Özil"       -> "mesut ozil"
///     "İlkay Gündoğan"   -> "ilkay gundogan"
///     "N'Golo Kanté"     -> "ngolo kante"
String normalizeName(String? name) {
  if (name == null || name.isEmpty) return '';

  // 1. Explicit character mapping first (before decomposition, which would
  //    ruin some of these).
  final mapped = StringBuffer();
  for (final ch in name.split('')) {
    mapped.write(_explicitMap[ch] ?? ch);
  }

  // 2. NFKD, then drop the combining marks it produced.
  final decomposed = unorm.nfkd(mapped.toString());
  final stripped = StringBuffer();
  for (final rune in decomposed.runes) {
    if (!_isCombining(rune)) stripped.writeCharCode(rune);
  }

  // 3. Lowercase, strip punctuation, collapse whitespace.
  var text = stripped.toString().toLowerCase();
  text = text.replaceAll(_punct, '');
  text = text.replaceAll(_whitespace, ' ').trim();
  return text;
}

/// The last token of a normalized name. Under time pressure most people type
/// the one name a player is known by ("Sneijder", "Hagi", "Ronaldinho").
String surnameKey(String? name) {
  final normalized = normalizeName(name);
  if (normalized.isEmpty) return '';
  return normalized.split(' ').last;
}
