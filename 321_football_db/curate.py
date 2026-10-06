"""
Hand-curated data that Wikidata does not give us in a usable shape.

    python curate.py            # apply (idempotent - safe to re-run)

1. CLUB NICKNAMES. club_aliases held only each club's own name, so typing
   "PSG", "Barça", "Spurs" or "Cimbom" found nothing. Wikidata's alias lists
   are too noisy to import wholesale (old sponsor names, other languages'
   transliterations), so the nicknames people actually type are listed here,
   keyed by QID so a rebuild re-applies them. Matching is on the normalized
   form, so "Barça" is stored as "barca" and also found by "barca".

2. NATIONALITY LABELS. players.nationality is the raw Wikidata country label:
   "Kingdom of the Netherlands", "United Kingdom of Great Britain and
   Ireland", "German Reich", even an unresolved genid URL. Collapse them to
   one clean name per country. The app shows these through a Turkish table
   (countryNamesTr in models.dart) that must cover every value left here.

Run as part of build_database.py (step 4), after enrich.
"""
from __future__ import annotations

import sys

import db

# QID -> nicknames. Only names people really type; the canonical name is
# already searchable. Short forms (GS, FB, BJK, PSG) are worth it: the team
# picker searches from 2 characters and ranks alias word-starts first.
NICKNAMES: dict[str, list[str]] = {
    # Spain
    "Q7156":   ["Barça", "Barca", "Barcelona", "FCB", "Blaugrana"],
    "Q8682":   ["Real Madrid", "Real", "Madrid", "Los Blancos"],
    "Q8701":   ["Atleti", "Atlético", "Atletico Madrid"],
    "Q8687":   ["Athletic Bilbao", "Bilbao"],
    "Q10333":  ["Valencia"],
    "Q10329":  ["Sevilla"],
    "Q8723":   ["Betis"],
    "Q12297":  ["Villarreal", "Yellow Submarine"],
    "Q10315":  ["La Real", "Sociedad"],
    "Q8780":   ["Espanyol"],
    "Q8749":   ["Celta Vigo", "Celta"],
    "Q8760":   ["Deportivo", "Depor"],
    # England
    "Q18656":  ["Man United", "Man Utd", "Manchester United", "United", "MUFC", "Red Devils"],
    "Q50602":  ["Man City", "Manchester City", "City", "MCFC"],
    "Q1130849": ["Liverpool", "LFC", "The Reds"],
    "Q9616":   ["Chelsea", "CFC", "The Blues"],
    "Q9617":   ["Arsenal", "The Gunners", "Gunners"],
    "Q18741":  ["Spurs", "Tottenham", "THFC"],
    "Q5794":   ["Everton", "The Toffees"],
    "Q18711":  ["Villa", "Aston Villa", "AVFC"],
    "Q18716":  ["Newcastle", "Toon", "The Magpies"],
    "Q18747":  ["West Ham", "Hammers", "The Hammers"],
    "Q19500":  ["Wolves", "Wolverhampton"],
    "Q19481":  ["Leicester", "The Foxes"],
    "Q1128631": ["Leeds", "Leeds United"],
    "Q18744":  ["West Brom", "WBA", "Baggies"],
    "Q19490":  ["Forest", "Nottingham Forest", "NFFC"],
    "Q18723":  ["QPR"],
    "Q19453":  ["Brighton", "Seagulls"],
    "Q19467":  ["Palace", "Crystal Palace"],
    "Q18708":  ["Fulham"],
    "Q18732":  ["Southampton", "Saints"],
    "Q19607":  ["Sheffield United", "Blades"],
    "Q19498":  ["Sheffield Wednesday", "Wednesday", "Owls"],
    "Q19446":  ["Blackburn", "Rovers"],
    "Q18739":  ["Sunderland", "Black Cats"],
    "Q19568":  ["Bournemouth", "Cherries"],
    # Scotland
    "Q19593":  ["Celtic", "The Bhoys"],
    "Q19597":  ["Rangers", "Gers"],
    # Italy
    "Q1422":   ["Juve", "Juventus", "Bianconeri", "Vecchia Signora"],
    "Q1543":   ["Milan", "Milan AC", "Rossoneri"],
    "Q631":    ["Inter", "Internazionale", "Nerazzurri"],
    "Q2641":   ["Napoli", "Partenopei"],
    "Q2739":   ["Roma", "Giallorossi"],
    "Q2609":   ["Lazio"],
    "Q2052":   ["Fiorentina", "Viola"],
    "Q1886":   ["Atalanta", "La Dea"],
    "Q2768":   ["Torino", "Toro", "Granata"],
    "Q1457":   ["Sampdoria", "Samp"],
    "Q2074":   ["Genoa"],
    "Q2693":   ["Parma"],
    "Q1893":   ["Bologna"],
    "Q2798":   ["Udinese"],
    # Germany
    "Q15789":  ["Bayern", "Bayern München", "Bayern Munchen", "FCB", "FC Bayern"],
    "Q41420":  ["BVB", "Dortmund", "Borussia"],
    "Q104761": ["Leverkusen", "Bayer", "Werkself"],
    "Q32494":  ["Schalke", "S04", "Königsblauen"],
    "Q101959": ["Gladbach", "Mönchengladbach", "Fohlen"],
    "Q51974":  ["HSV", "Hamburg"],
    "Q51976":  ["Werder", "Werder Bremen", "Bremen"],
    "Q38245":  ["Eintracht", "Frankfurt", "SGE"],
    "Q4512":   ["Stuttgart", "VfB"],
    "Q101859": ["Wolfsburg", "Die Wölfe"],
    "Q702455": ["Leipzig", "RBL"],
    "Q104770": ["Köln", "Koln", "Cologne", "FC Köln"],
    "Q102720": ["Hertha", "Hertha Berlin"],
    "Q22707":  ["Hoffenheim", "TSG"],
    "Q141971": ["Union Berlin", "Union"],
    "Q6463":   ["St. Pauli", "St Pauli"],
    "Q8466":   ["Kaiserslautern", "FCK", "Lautern"],
    # France
    "Q483020": ["PSG", "Paris", "Paris SG"],
    "Q132885": ["OM", "Marseille"],
    "Q704":    ["OL", "Lyon"],
    "Q180305": ["Monaco", "ASM"],
    "Q19516":  ["Lille", "LOSC"],
    "Q172476": ["Bordeaux"],
    "Q19521":  ["Saint-Étienne", "Saint Etienne", "ASSE", "Les Verts"],
    "Q185163": ["Nice"],
    "Q192071": ["Nantes"],
    "Q19509":  ["Rennes"],
    "Q191843": ["Lens"],
    # Portugal
    "Q128446": ["Porto", "FCP", "Dragões"],
    "Q131499": ["Benfica", "SLB", "Águias"],
    "Q75729":  ["Sporting", "Sporting Lisbon", "Sporting Lizbon", "SCP", "Leões"],
    "Q75684":  ["Braga"],
    # Netherlands
    "Q81888":  ["Ajax", "Ajax Amsterdam"],
    "Q11938":  ["PSV"],
    "Q134241": ["Feyenoord"],
    "Q191264": ["AZ"],
    "Q19603":  ["Twente"],
    # Turkey
    "Q495299": ["GS", "Galatasaray", "Cimbom", "Aslan"],
    "Q6601875": ["FB", "Fenerbahçe", "Fener", "Kanarya"],
    "Q172567": ["BJK", "Beşiktaş", "Kartal", "Kara Kartal"],
    "Q192641": ["TS", "Trabzon", "Fırtına"],
    "Q857938": ["Başakşehir", "Basaksehir", "İBFK"],
    "Q203573": ["Bursa", "Timsah"],
    # Belgium / Switzerland / Austria / Greece / Russia
    "Q187528": ["Anderlecht", "RSCA"],
    "Q190916": ["Club Brugge", "Brugge", "Bruges"],
    "Q189671": ["Basel", "FCB Basel"],
    "Q994811": ["Salzburg", "RB Salzburg"],
    "Q131215": ["Rapid", "Rapid Wien", "Rapid Vienna"],
    "Q4122219": ["Panathinaikos", "PAO"],
    "Q19628":  ["Olympiacos", "Olympiakos"],
    "Q201584": ["AEK"],
    "Q204888": ["PAOK"],
    "Q29108":  ["Zenit"],
    "Q176371": ["CSKA", "CSKA Moscow"],
    "Q29112":  ["Spartak"],
    # Brazil / Saudi Arabia / USA
    "Q17479":  ["Flamengo", "Fla", "Mengão"],
    "Q35933":  ["Corinthians", "Timão"],
    "Q80964":  ["Palmeiras", "Verdão"],
    "Q80955":  ["Santos", "Peixe"],
    "Q38568":  ["São Paulo", "Sao Paulo", "Tricolor"],
    "Q80987":  ["Fluminense", "Flu"],
    "Q5014111": ["Vasco", "Vasco da Gama"],
    "Q80958":  ["Botafogo"],
    "Q221695": ["Grêmio", "Gremio"],
    "Q80845":  ["Internacional", "Inter Porto Alegre"],
    "Q482764": ["Al Nassr", "Nassr"],
    "Q73965":  ["Al Hilal", "Hilal"],
    "Q309480": ["Al Ittihad", "Ittihad"],
    "Q16844931": ["Inter Miami", "Miami"],
    "Q204357": ["Galaxy", "LA Galaxy"],
}

# Raw Wikidata label -> clean label. None clears the value. Anything not
# listed is already clean. Historical states with no successor that fits a
# footballer's nationality (Soviet Union, Yugoslavia, Czechoslovakia, East
# Germany) are kept as they are - that IS what the record says.
NATIONALITY: dict[str, str | None] = {
    "Kingdom of the Netherlands": "Netherlands",
    "Kingdom of Denmark": "Denmark",
    "Kingdom of Italy": "Italy",
    "Republic of Venice": "Italy",
    "United Kingdom of Great Britain and Ireland": "United Kingdom",
    "England": "United Kingdom",
    "Scotland": "United Kingdom",
    "People's Republic of China": "China",
    "German Reich": "Germany",
    "German Empire": "Germany",
    "Weimar Republic": "Germany",
    "Nazi Germany": "Germany",
    "Kingdom of Bavaria": "Germany",
    "Socialist Federal Republic of Yugoslavia": "Yugoslavia",
    "Kingdom of Yugoslavia": "Yugoslavia",
    "Austria–Hungary": "Austria",
    "Zaire": "Democratic Republic of the Congo",
    "Pahlavi Iran": "Iran",
    "Ottoman Empire": "Turkey",
    "Chechnya": "Russia",
}


def apply_nicknames(conn) -> tuple[int, list[str]]:
    added, missing = 0, []
    for qid, names in NICKNAMES.items():
        row = conn.execute(
            "SELECT club_id FROM clubs WHERE wikidata_qid = ? AND is_reserve_or_b_team = 0",
            (qid,)).fetchone()
        if row is None:
            missing.append(qid)
            continue
        before = conn.total_changes
        for name in names:
            db.add_club_alias(conn, row["club_id"], name)
        added += conn.total_changes - before
    return added, missing


def apply_nationality(conn) -> int:
    changed = 0
    for raw, clean in NATIONALITY.items():
        cur = conn.execute("UPDATE players SET nationality = ? WHERE nationality = ?",
                           (clean, raw))
        changed += cur.rowcount
    # Unresolved Wikidata blank nodes leak through as URLs - not a country.
    cur = conn.execute("UPDATE players SET nationality = NULL WHERE nationality LIKE 'http%'")
    return changed + cur.rowcount


def main() -> int:
    conn = db.connect()
    added, missing = apply_nicknames(conn)
    relabelled = apply_nationality(conn)
    conn.commit()
    print(f"  club nicknames: {added} added ({sum(map(len, NICKNAMES.values()))} listed)")
    if missing:
        print(f"  !! {len(missing)} nickname QID(s) not found: {', '.join(missing)}")
    print(f"  nationality labels: {relabelled} player rows relabelled")
    conn.close()
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
