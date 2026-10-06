"""
Name normalization — how a typed answer becomes something we can match.

This matters more than it looks. A player racing a 10-second clock will type
"ozil", "Ozil", "Özil", "OZIL" or "özil", and every one of those has to hit
the same row. Turkish players are the hard case, because Turkish has a
dotted/dotless i distinction that Python's default .lower() mangles
("İ".lower() produces "i" plus a combining dot, which then does NOT equal
"i"). We handle those characters explicitly before falling back to Unicode
decomposition.
"""

from __future__ import annotations

import re
import unicodedata

# Characters that must be mapped before generic Unicode decomposition,
# either because decomposition gets them wrong (Turkish dotless i, Nordic
# ø/å, German ß) or because there is no decomposition at all (Polish ł).
_EXPLICIT_MAP = {
    "İ": "i", "I": "i", "ı": "i",   # Turkish dotted/dotless i
    "Ş": "s", "ş": "s",
    "Ğ": "g", "ğ": "g",
    "Ç": "c", "ç": "c",
    "Ö": "o", "ö": "o",
    "Ü": "u", "ü": "u",
    "ß": "ss",
    "Ø": "o", "ø": "o",
    "Æ": "ae", "æ": "ae",
    "Œ": "oe", "œ": "oe",
    "Å": "a", "å": "a",
    "Ł": "l", "ł": "l",
    "Đ": "d", "đ": "d",
    "Ð": "d", "ð": "d",
    "Þ": "th", "þ": "th",
    "Ñ": "n", "ñ": "n",
}

_PUNCT_RE = re.compile(r"[^\w\s]", re.UNICODE)
_WHITESPACE_RE = re.compile(r"\s+")


def normalize_name(name: str | None) -> str:
    """
    Fold a name down to a plain lowercase ASCII-ish key.

        "Wesley Sneijder"      -> "wesley sneijder"
        "Mesut Özil"           -> "mesut ozil"
        "İlkay Gündoğan"       -> "ilkay gundogan"
        "N'Golo Kanté"         -> "ngolo kante"
        "Gheorghe Hagi "       -> "gheorghe hagi"
    """
    if not name:
        return ""

    # 1. Explicit character mapping first (before NFKD, which would ruin some).
    chars = [_EXPLICIT_MAP.get(ch, ch) for ch in name]
    text = "".join(chars)

    # 2. Unicode decomposition, then drop the combining accent marks.
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))

    # 3. Lowercase, strip punctuation, collapse whitespace.
    text = text.lower()
    text = _PUNCT_RE.sub("", text)
    text = _WHITESPACE_RE.sub(" ", text).strip()
    return text


def surname_key(name: str | None) -> str:
    """
    The last token of a normalized name.

    Most players are known by one name in conversation ("Sneijder",
    "Ronaldinho", "Hagi"), and under time pressure that's what people type.
    Used as a secondary, lower-confidence match after exact matching fails.
    """
    normalized = normalize_name(name)
    if not normalized:
        return ""
    return normalized.split()[-1]


def name_variants(full_name: str) -> set[str]:
    """
    Every string we're willing to accept as referring to this player.

    Deliberately conservative: full name, surname, and first-initial forms.
    We do NOT generate fuzzy/edit-distance variants here — that belongs at
    query time where we can rank candidates, not in the stored alias table
    where a bad variant would silently make a wrong answer count as right.
    """
    variants: set[str] = set()
    normalized = normalize_name(full_name)
    if not normalized:
        return variants

    variants.add(normalized)
    tokens = normalized.split()

    if len(tokens) >= 2:
        variants.add(tokens[-1])                          # "sneijder"
        variants.add(f"{tokens[0][0]} {tokens[-1]}")      # "w sneijder"
        variants.add(f"{tokens[0]} {tokens[-1]}")         # "wesley sneijder"

    return {v for v in variants if len(v) >= 3}


if __name__ == "__main__":
    samples = [
        "Wesley Sneijder", "Mesut Özil", "İlkay Gündoğan", "N'Golo Kanté",
        "Zlatan Ibrahimović", "Robert Lewandowski", "Hakan Şükür",
        "Emre Belözoğlu", "Gheorghe Hagi", "Ronaldinho",
    ]
    for sample in samples:
        print(f"{sample:25} -> {normalize_name(sample):25} | surname: {surname_key(sample)}")
