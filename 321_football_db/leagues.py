"""
The league registry — the full scope of the 321 Football Challenge database.

WHY THERE ARE (mostly) NO HARDCODED QIDs HERE
---------------------------------------------
Wikidata Q-numbers are easy to get subtly wrong, and a wrong one fails in the
worst possible way: the scraper runs happily for an hour and fills your
database with the wrong competition's clubs. So instead of pasting in ~23
Q-numbers, this file describes each league in human terms (name, country,
tier) and `resolve_leagues.py` looks each one up against live Wikidata,
verifies it's a football league in the right country, and writes the
confirmed QIDs to leagues_resolved.json for you to eyeball once.

Q9448 (Premier League) is the one pre-filled hint, because it's verified.
Anything else you already know, you can add as `qid_hint` — the resolver
still validates hints rather than trusting them.

ADDING A LEAGUE
---------------
Append a League(...) entry. Nothing else needs to change; the resolver and
the scrapers both iterate this list.
"""

from dataclasses import dataclass, field


@dataclass
class League:
    key: str                     # stable internal id, used in logs and the DB
    name: str                    # English label as it appears on Wikidata
    country: str                 # human-readable, for logs
    country_qid: str             # used to disambiguate same-named leagues
    tier: int                    # 1 = top flight, 2 = second division
    region: str
    aliases: list[str] = field(default_factory=list)  # other labels to try
    qid_hint: str | None = None  # verified QIDs only; still validated
    explicitly_requested: bool = False  # part of your original spec


# Country QIDs used for disambiguation. "Serie A" and "Premier League" exist
# in several countries; matching on country is what keeps them apart.
COUNTRIES = {
    "England": "Q21",
    "Scotland": "Q22",
    "Spain": "Q29",
    "Italy": "Q38",
    "Germany": "Q183",
    "France": "Q142",
    "Turkey": "Q43",
    "Netherlands": "Q55",
    "Portugal": "Q45",
    "Belgium": "Q31",
    "Russia": "Q159",
    "Greece": "Q41",
    "Austria": "Q40",
    "Switzerland": "Q39",
    "United States": "Q30",
    "Brazil": "Q155",
    "Saudi Arabia": "Q851",
    "Argentina": "Q414",
    "Mexico": "Q96",
}


LEAGUES: list[League] = [
    # ---------------------------------------------------------------- tier 1
    League("eng_pl", "Premier League", "England", COUNTRIES["England"], 1, "Europe",
           aliases=["English Premier League", "FA Premier League"],
           qid_hint="Q9448", explicitly_requested=True),

    League("esp_laliga", "La Liga", "Spain", COUNTRIES["Spain"], 1, "Europe",
           aliases=["Primera División", "Campeonato Nacional de Liga de Primera División"],
           qid_hint="Q324867", explicitly_requested=True),

    League("ita_seriea", "Serie A", "Italy", COUNTRIES["Italy"], 1, "Europe",
           aliases=["Italian Serie A", "Serie A (Italy)"],
           qid_hint="Q15804", explicitly_requested=True),

    League("ger_bundesliga", "Bundesliga", "Germany", COUNTRIES["Germany"], 1, "Europe",
           aliases=["Fußball-Bundesliga", "German Bundesliga"],
           qid_hint="Q82595"),

    League("fra_ligue1", "Ligue 1", "France", COUNTRIES["France"], 1, "Europe",
           aliases=["French Ligue 1", "Division 1"],
           qid_hint="Q13394"),

    League("tur_superlig", "Süper Lig", "Turkey", COUNTRIES["Turkey"], 1, "Europe",
           aliases=["Turkish Süper Lig", "Süper Lig (Turkey)", "Turkish Super League"],
           qid_hint="Q485568", explicitly_requested=True),

    League("ned_eredivisie", "Eredivisie", "Netherlands", COUNTRIES["Netherlands"], 1, "Europe",
           aliases=["Dutch Eredivisie"],
           qid_hint="Q167541"),

    League("por_primeira", "Primeira Liga", "Portugal", COUNTRIES["Portugal"], 1, "Europe",
           aliases=["Liga Portugal", "Portuguese Primeira Liga", "Primeira Divisão"],
           qid_hint="Q182994"),

    League("bel_proleague", "Belgian Pro League", "Belgium", COUNTRIES["Belgium"], 1, "Europe",
           aliases=["Belgian First Division A", "Jupiler Pro League"],
           qid_hint="Q216022"),

    # Scotland's top flight has been THREE separate Wikidata items since 1990:
    # Premier Division (to 1998) -> SPL (1998-2013) -> Premiership (2013-).
    # Each one owns its own seasons, so all three are needed to get the full
    # club list. Same club appearing in all three is deduplicated by its QID.
    League("sco_premiership", "Scottish Premiership", "Scotland", COUNTRIES["Scotland"], 1, "Europe",
           aliases=["Scottish Premiership (football)"],
           qid_hint="Q14377162"),

    League("sco_spl", "Scottish Premier League", "Scotland", COUNTRIES["Scotland"], 1, "Europe",
           aliases=["SPL"],
           qid_hint="Q187304"),

    League("sco_premier_div", "Scottish Football League Premier Division", "Scotland",
           COUNTRIES["Scotland"], 1, "Europe",
           aliases=["Scottish Premier Division"],
           qid_hint="Q843012"),

    League("rus_premier", "Russian Premier League", "Russia", COUNTRIES["Russia"], 1, "Europe",
           aliases=["Russian Football Premier League", "Russian Top League"],
           qid_hint="Q182165"),

    League("gre_superleague", "Super League Greece", "Greece", COUNTRIES["Greece"], 1, "Europe",
           aliases=["Greek Super League", "Alpha Ethniki"],
           qid_hint="Q235114"),

    League("aut_bundesliga", "Austrian Football Bundesliga", "Austria", COUNTRIES["Austria"], 1, "Europe",
           aliases=["Austrian Bundesliga"],
           qid_hint="Q219592"),

    League("sui_superleague", "Swiss Super League", "Switzerland", COUNTRIES["Switzerland"], 1, "Europe",
           aliases=["Nationalliga A", "Swiss Football League"],
           qid_hint="Q202699"),

    # ---------------------------------------------------------------- tier 2
    League("eng_championship", "EFL Championship", "England", COUNTRIES["England"], 2, "Europe",
           aliases=["Football League Championship", "English Football League Championship"],
           qid_hint="Q19510", explicitly_requested=True),

    # The Championship only exists under that name from 2004. Between 1992 and
    # 2004 the second tier was the Football League First Division, and before
    # 1992 that name meant the TOP flight. Its clubs are in scope either way.
    League("eng_first_div", "Football League First Division", "England",
           COUNTRIES["England"], 2, "Europe",
           aliases=["English Football League First Division", "First Division"]),

    League("ita_serieb", "Serie B", "Italy", COUNTRIES["Italy"], 2, "Europe",
           aliases=["Italian Serie B"],
           qid_hint="Q194052", explicitly_requested=True),

    League("ger_2bundesliga", "2. Bundesliga", "Germany", COUNTRIES["Germany"], 2, "Europe",
           aliases=["2. Fußball-Bundesliga", "Zweite Bundesliga"],
           qid_hint="Q152665", explicitly_requested=True),

    # NOTE: Q751826 is Segunda División B — the THIRD tier. The actual second
    # tier is LaLiga 2 / Segunda División, Q35615.
    League("esp_segunda", "Segunda División", "Spain", COUNTRIES["Spain"], 2, "Europe",
           aliases=["LaLiga 2", "La Liga 2", "Segunda División de España"],
           qid_hint="Q35615"),

    League("fra_ligue2", "Ligue 2", "France", COUNTRIES["France"], 2, "Europe",
           aliases=["French Ligue 2", "Division 2"],
           qid_hint="Q217374"),

    League("tur_1lig", "TFF First League", "Turkey", COUNTRIES["Turkey"], 2, "Europe",
           aliases=["TFF 1. Lig", "1. Lig", "Turkish First League"],
           qid_hint="Q1141692"),

    # ------------------------------------------------------- rest of world
    League("usa_mls", "Major League Soccer", "United States", COUNTRIES["United States"], 1, "North America",
           aliases=["MLS"],
           qid_hint="Q18543", explicitly_requested=True),

    League("bra_seriea", "Campeonato Brasileiro Série A", "Brazil", COUNTRIES["Brazil"], 1, "South America",
           aliases=["Brasileirão", "Brazilian Série A", "Campeonato Brasileiro de Futebol Série A"],
           qid_hint="Q206813", explicitly_requested=True),

    League("ksa_proleague", "Saudi Pro League", "Saudi Arabia", COUNTRIES["Saudi Arabia"], 1, "Asia",
           aliases=["Saudi Professional League", "Roshn Saudi League"],
           qid_hint="Q255633", explicitly_requested=True),
]


def by_key(key: str) -> League:
    for league in LEAGUES:
        if league.key == key:
            return league
    raise KeyError(f"No league with key {key!r}")


def summary() -> str:
    tier1 = sum(1 for lg in LEAGUES if lg.tier == 1)
    tier2 = sum(1 for lg in LEAGUES if lg.tier == 2)
    return (f"{len(LEAGUES)} leagues configured "
            f"({tier1} top-flight, {tier2} second-division)")


if __name__ == "__main__":
    print(summary())
    for lg in LEAGUES:
        star = "*" if lg.explicitly_requested else " "
        print(f" {star} [{lg.key:20}] tier {lg.tier}  {lg.name} ({lg.country})")
    print("\n* = explicitly named in your original project spec")
