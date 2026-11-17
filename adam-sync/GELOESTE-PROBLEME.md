# adam-sync — Anpassungen & gelöste Probleme (HS26)

Dokumentiert alle Fehler und Fixes, die nötig waren, um adam-sync gegen den
**aktuellen ADAM (Uni Basel, ILIAS)** in Betrieb zu nehmen. Stand: HS26
(Nov. 2026). Die Datei `adam_sync.py` hierin ist die getestete Version.

---

## 1. Neues ADAM-Navigations-Schema `/go/<typ>/<ref>`

**Problem.** Der ursprüngliche Crawler erkannte nur alte ILIAS-Links
`goto.php?target=<typ>_<ref>`. Das aktuelle ADAM nutzt zusätzlich die Form
`https://adam.unibas.ch/go/crs/2207150` (Provider-Links). Dadurch wurden
Dateien/Folder aus `/go/…`-Links nicht gefunden.

**Fix.** `ref_from_href`/`type_from_href` parsen jetzt beide Formen:
`/(?:go|goto\.php)/[a-z]+/(\d+)` und der alte `target=…_NNN`-Pfad bleibt als
Fallback erhalten.

**Hinweis.** Die reale Kursliste holt man über
`ilias.php?baseClass=ilmembershipoverviewgui&cmd=show` — dort stehen die
`/go/crs/<ref>`-Links zu allen Kursen (z. B. `crs` 2207150 = "Einführung in
die Chemie"). Diese Refs trägt man in die Config-`roots` ein (siehe §6).

---

## 2. Download-URL: `ilrepositorygui` statt `ilObjFileGUI`

**Problem.** Der Download-Link war
`ilias.php?baseClass=ilObjFileGUI&cmd=sendfile&ref_id=…`. Auf dem aktuellen
ADAM liefert genau diese Variante **HTTP 404** (und den HTML-Login/Fehler),
plus generischen Text — kein Datei-Download.

**Fix.** Der funktionierende Link nutzt `ilrepositorygui` + explizite
`cmdClass`:
```
ilias.php?baseClass=ilrepositorygui&cmdClass=ilObjFileGUI&cmd=sendfile&ref_id=<ref>
```
So heruntergeladene Datei liefert korrektes
`Content-Disposition: attachment; filename="…"` und realen Content.

**Warum.** Die alte `baseClass=ilObjFileGUI`-Form ist im aktuellen ILIAS nicht
mehr der Sendepunkt für Datei-Objekte; `ilrepositorygui` mitsamt `cmdClass`
ist es. `cmdNode` ist dafür nicht nötig (getestet).

---

## 3. `type_from_href` erkannte `readfile` nie

**Problem.** Neben `cmd=sendfile` gibt es auch `cmd=readfile`; die Erkennung
prüfte nur `sendfile`.

**Fix.** Beide sendepflichtigen Commands als Dateityp werten
(`"cmd=sendfile" in href or "cmd=readfile" in href`).

---

## 4. Rekursion läuft ins Leere / globales Crawlen

**Problem.** Mit `roots=[1]` (Root) oder vagen Einstiegspunkten durchlief der
Walker die gesamte ADAM-Struktur (Hilfe&Support, ADAMtools, globale
Kategorien) — langsam, Datenmüll.

**Fixes im `walk`:**
- `SKIP_TYPES = {root, blog, impr, webr, ldap}` — globale Navigationsobjekte
  werden nicht rekursiv verfolgt.
- `SKIP_NAV_CATS` — explizite Ausschluss-Liste bekannter globaler Kategorien
  (z. B. Hilfe&Support, ADAMtools); hier als Set von `cat`-refs.
- `MAX_DEPTH` von 20 auf **8** gesenkt, `MAX_NODES = 400` als harte Grenze
  gegen Endlos-Walk bei sehr tiefen Kursen (jeder Kurs baut anders auf, siehe §5).

---

## 5. Jeder Kurs hat eine andere Struktur

**Problem/Beobachtung.** Chemie, Physik und Mathe hängen ihre Dateien in
völlig verschiedenen Ordner-Tiefen und -Namen ab (manche direkt, manche in
mehrere Unter-`cat`/`fold`). Ein starres, struktur-abhängiges Crawlen bricht
daher leicht.

**Design-Entscheidung.** adam-sync **flacht** deshalb ab: Es sammelt alle
`file`-Objekte, egal in welcher Tiefe/Nesting, und legt sie im `dest` ab —
die Zielstruktur (z. B. `eingang/<fach>/`) macht ein **separater
Sortierschritt** anhand des Dateinamens (siehe `eingang.py`, „sortieren"):
ein File ist ein File, egal wo es im Kurs hing. Der Kursbaum wird nie
nachgebildet. Das macht den Sync robust gegen unterschiedliche
Kursstrukturen.

---

## 6. `roots` als {Kurs-ref : Fach}-Mapping

**Neu v. o.** `config.json` akzeptiert `roots` entweder als Liste
(Mapping-Fach frei) oder als **Dict** `{kurs_ref: fach}`, wobei jeder Kurs
einer Fach-Nummer/Bezeichnung zugeordnet wird. Der Walker trägt das `fach` an
jede gefundene Datei, und `sync_file` legt sie unter `dest/<fach>/` ab:

```json
{ "roots": {
    "2207150": "chemie",
    "2207134": "physik",
    "2207348": "mathe",
    "2207352": "mathe"
} }
```

Damit kommen die Dateien direkt nach `dest/chemie/`, `dest/physik/`,
`dest/mathe/` — kein nachträgliches Raten am Dateinamen nötig.

---

## 7. Session-Cookies laufen ab („continous scraping“)

**Beobachtung.** ADAM-Session (`PHPSESSID`, `_shibsession_…`) verfallen nach
Stunden bis Tagen. Der Sync läuft als **täglicher Timer** weiter; es gibt
keine „per Upload“-Pflicht. Wenn die Session tot ist, muss man nur einmal
wieder die Cookies exportieren.

**Umgang im Wächter-Skript (z. B. `lernhelfer-probe.sh`):** fehlt
`cookies.json` oder meldet `adam-sync` eine Login-Pflicht-Antwort
(`doStandardAuthentication`, `cmd=showLogin`, `Anmelden`), wird **`SESSION_EXPIRED`**
ausgegeben — der Cron informiert dann den Nutzer, statt still nichts zu
finden. Der regelmäßige Re-Export (alle paar Tage) ist so kostengünstig wie
möglich gestaltet.

**Sicherheit.** Cookies gehören NICHT in ein (auch privates) Git-Repo;
`cookies.json` liegt nur unter `~/.config/adam-sync/`. In den Material-Repos
des Lernhelfer-Projekts wird `eingang/*.txt` per `.gitignore` ausgeschlossen,
damit ein versehentlich abgelegter Export nicht eingecheckt wird.

---

## 8. Abhängigkeiten: `requests` + `beautifulsoup4`

**Problem.** Auf der Zielmaschine fehlten `requests` und `beautifulsoup4`.

**Fix.** Die Nix-Flake packt sie als `python3.withPackages` in den
`adamSync`-`wrapProgram` (PYTHONPATH), sodass `adam-sync` out-of-the-box läuft
— kein manuelles `pip install`. Beim lokalen Test in einer nicht-Nix-Umgebung
entsprechend `pip install requests beautifulsoup4`.

---

## 9. Dateinamen: `.inhalt`-Artefakt im Dry-Run

**Problem.** Im `--dry-run`-Modus erschienen Dateien als `… .inhalt`, weil
`ext_from_props` aus den Seiten-„props“ fälschlich einen ersten Eintrag als
Extension übernahm.

**Beobachtung.** Beim echten Download wird der Dateiname aus dem
`Content-Disposition`-Header genommen (`filename_from_cd`), der korrekt ist —
das im Dry-Run gezeigte `.inhalt` ist also nur ein Anzeige-Artefakt und der
reale Download ergibt die richtigen Dateien (z. B. `Chemie_0_2026_1.pdf`).

---

## 10. Cross-device MOVE (eingang.py)

**Problem.** `datei.replace(dst)` schlägt fehl, wenn Quelle (z. B. `/tmp`)
und Ziel (`/opt/data/...`) auf verschiedenen Dateisystemen liegen
(`OSError ERRNO 18 Invalid cross-device link`).

**Fix.** `shutil.move()` verwenden, das über Dateisystemgrenzen hinweg
kopiert+entfernt. Außerdem vor dem Verschieben prüfen, ob das Ziel existiert
(`skips`/überspringen) statt still zu crashen.

---

## Noch offen / bewusst nicht gelöst

- Der komplette Nix-Build und der reale `systemd`-Timer sind in dieser
  Sandbox (kein Nix-Build/kein sudo) nicht end-to-end ausgeführt worden.
  Bitte `sudo nixos-rebuild build` auf der Zielmaschine machen (Flake evtl.
  einmal `nix flake lock --update-input nixpkgs`).
- Die SMIL-Liste von monoisotopischen Elementen usw. ist **fachlicher Inhalt**
  der Materialien und gehört nicht in diese technische Datei.

---

*Legende: Die Versionsnummern der gelösten Probleme sind intern;
`adam_sync.py` in diesem Ordner enthält den Stand mit allen Fixes aus §1–§6.*
