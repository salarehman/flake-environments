#!/usr/bin/env python3
"""adam-sync – One-Way-Sync neuer Dateien aus deinen ADAM-Kursen (U. Basel, ILIAS).

Login-Logik:
  ADAM authentifiziert via SWITCH edu-ID SSO (Shibboleth) und optional der
  ILIAS-Form "doStandardAuthentication". Eine reine Passwort-POST ist daher
  nicht zuverlässig möglich. Die robuste Methode: einmalig interaktiv
  einloggen (Browser), die Session-Cookies speichern und diese für alle
  folgenden Synchronisationen verwenden; bei Ablauf nach dem Login-Vorgang
  erneut einloggen.

Befehle:
  adam-sync setup          interaktive Anmeldung (Browser) -> Cookie-Jar speichern
  adam-sync sync [--dry-run]  Dateien der Kurse herunterladen (nur neu/geändert)
  adam-sync courses        gefundene Kurse anzeigen
  adam-sync schedule       systemd-Timer anlegen (Hinweis; NixOS-Modul setup bevorzugt)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import unicodedata
import webbrowser
from pathlib import Path
from urllib.parse import unquote

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("Fehlende Pakete: pip3 install requests beautifulsoup4", file=sys.stderr)
    sys.exit(1)

__version__ = "0.1.0"

# --- Konstanten (für ADAM / Uni Basel) ---
BASE_URL = "https://adam.unibas.ch/"
LOGIN_URL = BASE_URL + "ilias.php?baseClass=ilStartUpGUI&cmd=showLogin"
POST_URL = BASE_URL + "ilias.php?baseClass=ilStartUpGUI&cmd=post&fallbackCmd=doStandardAuthentication"
# Container-Typen, in die rekursiv hineingeschaut wird (ILIAS Objekttypen)
CONTAINER_TYPES = {"fold", "grp", "sess", "cat"}
MAX_DEPTH = 20

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "adam-sync"
CONFIG_FILE = CONFIG_DIR / "config.json"
COOKIE_FILE = CONFIG_DIR / "cookies.json"

VERBOSE = False


def log(m):
    print(m, flush=True)


def vlog(m):
    if VERBOSE:
        print("  · " + m, flush=True)


# ---------------- config ----------------
def load_config() -> dict:
    if not CONFIG_FILE.exists():
        log("Noch nicht eingerichtet:  adam-sync setup")
        sys.exit(1)
    return json.loads(CONFIG_FILE.read_text(encoding="utf-8"))


def save_config(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8")


# ---------------- Hilfsfunktionen ----------------
def safe_name(name, max_len=150):
    name = unicodedata.normalize("NFC", name)
    name = re.sub(r'[\/\\:\*\?"<>|\x00-\x1f]', "_", name)
    name = re.sub(r"\s+", " ", name).strip().strip(".")
    name = name or "unbenannt"
    if len(name) > max_len:
        stem, dot, ext = name.rpartition(".")
        name = (stem[: max_len - len(ext) - 1].rstrip() + "." + ext) if dot and len(ext) <= 8 else name[:max_len].rstrip()
    return name


def ref_from_href(href):
    for pat in (r"[?&]ref_id=(\d+)", r"goto\.php/[a-z]+/(\d+)", r"[?&]target=[a-z]+_(\d+)"):
        m = re.search(pat, href)
        if m:
            return int(m.group(1))
    return None


def type_from_href(href):
    m = re.search(r"goto\.php/([a-z]+)/\d+", href) or re.search(r"[?&]target=([a-z]+)_\d+", href)
    if m:
        return m.group(1)
    if "cmd=sendfile" in href:
        return "file"
    return None


def type_from_icon(el):
    if el is None:
        return None
    for img in el.find_all("img"):
        m = re.search(r"icon_([a-z]+)\.svg", img.get("src", ""))
        if m and m.group(1) not in ("custom", "checked", "alert"):
            return m.group(1)
    return None


def filename_from_cd(cd):
    if not cd:
        return None
    m = re.search(r"filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)", cd)
    if m:
        return unquote(m.group(1).strip().strip('"'))
    m = re.search(r'filename\s*=\s*"([^"]+)"', cd) or re.search(r"filename\s*=\s*([^;]+)", cd)
    if m:
        raw = m.group(1).strip()
        try:
            return raw.encode("latin-1").decode("utf-8")
        except Exception:
            return raw
    return None


def file_signature(props):
    parts = []
    parts += re.findall(r"\d+(?:[.,]\d+)?\s*(?:Bytes|KB|MB|GB|kB)", props)
    parts += re.findall(r"Version:?\s*\d+", props, flags=re.I)
    parts += re.findall(r"\d{1,2}\.\s*\w+\.?\s*\d{4}(?:,?\s*\d{1,2}:\d{2})?", props)
    parts += re.findall(r"\d{1,2}\.\d{1,2}\.\d{2,4}(?:,?\s*\d{1,2}:\d{2})?", props)
    parts += re.findall(r"(?:Heute|Gestern|Today|Yesterday),?\s*\d{1,2}:\d{2}", props)
    return " | ".join(parts) if parts else props


def ext_from_props(props):
    first = props.split("|")[0].strip().lower()
    return "." + first if re.fullmatch(r"[a-z0-9]{1,6}", first) else ""


# ---------------- Session / Login ----------------
def load_session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": "Mozilla/5.0"})
    if COOKIE_FILE.exists():
        for c in json.loads(COOKIE_FILE.read_text(encoding="utf-8")):
            s.cookies.set(c["name"], c["value"], domain=c.get("domain"), path=c.get("path", "/"))
    return s


def save_session(s: requests.Session) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    COOKIE_FILE.write_text(
        json.dumps([{"name": c.name, "value": c.value, "domain": c.domain, "path": c.path} for c in s.cookies]),
        encoding="utf-8",
    )


def is_logged_in(s: requests.Session) -> bool:
    try:
        r = s.get(BASE_URL, timeout=30)
        return ("c-form" not in r.text.lower()) or ("usr_name" not in r.text) or ("cmd=showLogin" not in r.text)
    except Exception:
        return False


def interactive_login() -> requests.Session:
    """Öffnet den Browser für die SSO-Anmeldung und speichert die Cookies."""
    log("Öffne Browser für die Anmeldung an ADAM ...")
    webbrowser.open(LOGIN_URL)
    log("Nach der Anmeldung Enter drücken, um die Session zu übernehmen.")
    try:
        input()
    except EOFError:
        pass
    s = load_session()  # Browser-Cookie-Jar wird extern gelegt (siehe README)
    if not is_logged_in(s):
        log("Achtung: noch keine gültige Session erkennbar.")
    else:
        log("Session gültig.")
    return s


def authed(s: requests.Session, cfg: dict) -> None:
    """Sicherstellen, dass eine gültige Session vorliegt; ggf. Cookie neu setzen."""
    if is_logged_in(s):
        return
    if cfg.get("login_mode") == "form" and cfg.get("username"):
        pw = cfg.get("password")
        r = s.post(POST_URL, data={"login_form/input_3/input_4": cfg["username"], "login_form/input_3/input_5": pw, "cmd[doStandardAuthentication]": "Anmelden"})
        if is_logged_in(s):
            save_session(s)
            log("Formular-Login erfolgreich.")
            return
    raise SystemExit("Keine gültige ADAM-Session (mehr). Bitte 'adam-sync setup' erneut ausführen.")


# ---------------- Sync ----------------
def find_files(html):
    """Extrahiert (typ, ref, title, props) für Dateien/Folder im Treeslice."""
    soup = BeautifulSoup(html, "html.parser")
    out = []
    for a in soup.find_all("a", href=True):
        t = type_from_href(a["href"])
        r = ref_from_href(a["href"])
        if not (t and r):
            continue
        node = {"type": t, "ref": r, "title": a.get_text(strip=True)}
        # Props aus umliegendem Block (Grösse/Version/Datum) zusammenlesen
        parent = a.find_parent(class_=re.compile(r"row|item|tile")) or a.find_parent("li")
        props = parent.get_text(" | ", strip=True) if parent else a.get_text(" | ", strip=True)
        node["props"] = props
        node["file_name"] = safe_name((filename_from_cd(None) or a.get_text(strip=True)).strip())
        out.append(node)
    return out


def walk(cfg, s: requests.Session, ref_id: int, depth: int, out: list, visited: set) -> None:
    if depth > MAX_DEPTH or ref_id in visited:
        return
    visited.add(ref_id)
    target = f"goto.php?target=fold_{ref_id}"
    r = s.get(BASE_URL + target, timeout=30)
    html = r.text
    for node in find_files(html):
        if node["type"] == "file":
            out.append(node)
        elif node["type"] in CONTAINER_TYPES:
            walk(cfg, s, node["ref"], depth + 1, out, visited)


def list_courses(cfg, s: requests.Session):
    """Kurse des Nutzers ermitteln (Einstieg via goto.php auf eigene Objekte)."""
    # pragmatisch: Root-Folder des Nutzers + persönlicher Schreibtisch
    r = s.get(BASE_URL + "goto.php?target=root_1", timeout=30)
    return r.text


def sync_file(cfg, s, node, base_dir, dry_run):
    # sendfile URL
    dl = f"{BASE_URL}ilias.php?baseClass=ilObjFileGUI&cmd=sendfile&ref_id={node['ref']}"
    sig = file_signature(node.get("props", ""))
    folder = node.get("folder", "")
    target_dir = base_dir
    if folder:
        target_dir = base_dir / folder
    target_dir.mkdir(parents=True, exist_ok=True)
    ext = ext_from_props(node.get("props", ""))
    fname = safe_name(node.get("file_name", "datei") + ext)
    dst = target_dir / fname
    state = cfg.setdefault("state", {})
    known = state.get(str(node["ref"]))
    if known == sig:
        vlog(f"unverändert: {fname}")
        return False
    if dry_run:
        log(f"[dry-run] würde laden: {fname}")
        return False
    r = s.get(dl, stream=True, timeout=120)
    if r.status_code != 200:
        log(f"  Probe fehlgeschlagen {node['ref']} ({r.status_code})")
        return False
    # Dateinamen aus Content-Disposition bevorzugen
    cd_name = filename_from_cd(r.headers.get("Content-Disposition"))
    if cd_name:
        dst = target_dir / safe_name(cd_name)
    tmp = dst.with_suffix(dst.suffix + ".part")
    with open(tmp, "wb") as f:
        shutil.copyfileobj(r.raw, f)
    tmp.replace(dst)
    state[str(node["ref"])] = sig
    log(f"geladen: {dst}")
    return True


def cmd_setup(args):
    cfg = {
        "base_url": BASE_URL,
        "dest": args.dest or str(Path.home() / "ILIAS"),
        "login_mode": args.login_mode or "sso",
        "username": args.username or "",
        "password": args.password or "",
        "state": {},
    }
    save_config(cfg)
    s = interactive_login()
    save_session(s)
    log("Einrichtung abgeschlossen.")


def cmd_courses(args):
    cfg = load_config()
    s = load_session()
    authed(s, cfg)
    list_courses(cfg, s)
    log("Verfügbare Kurse: siehe ADAM-Web (die extrahierbaren Ordner folgen denselben ref_ids).")


def cmd_sync(args):
    global VERBOSE
    VERBOSE = args.verbose
    cfg = load_config()
    s = load_session()
    authed(s, cfg)
    base = Path(cfg["dest"])
    base.mkdir(parents=True, exist_ok=True)
    # Einstiegspunkte: Root (root_1) – durchläuft persönliche Objekte
    found = []
    visited = set()
    for root in cfg.get("roots", [1]):
        walk(cfg, s, root, 0, found, visited)
    changed = 0
    for node in found:
        if sync_file(cfg, s, node, base, args.dry_run):
            changed += 1
    save_config(cfg)
    log(f"Fertig. {len(found)} Dateien gefunden, {changed} geladen.")


def main():
    global VERBOSE, DEBUG
    p = argparse.ArgumentParser(prog="adam-sync", description="Sync neuer Dateien aus ADAM (Uni Basel, ILIAS).")
    p.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    p.add_argument("-v", "--verbose", action="store_true")
    sub = p.add_subparsers(dest="cmd")
    s = sub.add_parser("setup", help="Anmeldung (Browser) + Zielordner einrichten")
    s.add_argument("--dest", default="")
    s.add_argument("--login-mode", choices=["sso", "form"], default="")
    s.add_argument("--username", default="")
    s.add_argument("--password", default="")
    s.set_defaults(func=cmd_setup)
    sub.add_parser("courses").set_defaults(func=cmd_courses)
    s2 = sub.add_parser("sync", help="neue/geänderte Dateien herunterladen")
    s2.add_argument("--dry-run", action="store_true")
    s2.set_defaults(func=cmd_sync)
    args = p.parse_args()
    if not args.cmd:
        p.print_help()
        sys.exit(0)
    args.func(args)


if __name__ == "__main__":
    main()
