# lernhelfer-sync — Material-Ingest automatisieren

Bindet das adam-sync-Pull-System, die Material-Einordnung (`eingang.py`) und
den Lernhelfer-Build zusammen. Das eigentliche Bauen passiert im öffentlichen
Repo `Lernhelfer`; dieses Flake sorgt dafür, dass die neuen Dateien aus ADAM
regelmäßig im privaten Repo `Lernhelfer-Material` landen und die Skripte/Blätter
korrekt einsortiert werden.

## Nutzung (manuell)

```bash
nix develop                          # Shell mit adam-sync + ingest
LERNHELFER_MATERIAL=/pfad/zum/Lernhelfer-Material \
LERNHELFER_PUBLIC=/pfad/zum/Lernhelfer \
  nix run .# --                      # sync + einordnen in einem Aufruf
```

Voraussetzung: einmalig `adam-sync setup` (Browser-Login) ausführen, damit die
Session-Cookies für ADAM gespeichert sind (siehe `../adam-sync/`).

## NixOS-Modul (vollständig deklarativ, täglicher Timer)

```nix
# flake.nix inputs:
lernhelfer-sync.url = "github:salarehman/flake-environments?dir=lernhelfer-sync";

# modules:
lernhelfer-sync.nixosModules.default
({ load, ... }: {
  services.lernhelfer-sync = {
    enable = true;
    user = "me";
    materialDir = "/home/me/ws/Lernhelfer-Material";   # privates Repo
    publicDir   = "/home/me/ws/Lernhelfer";            # öffentliches Repo
    interval    = "02:00";   # täglich 02:00, Persistent = true
  };
});
```

Das Modul erzeugt `systemd.services.lernhelfer-sync` (oneshot) und
`systemd.timers.lernhelfer-sync` mit `OnCalendar = interval`.

## Grenzen / ehrliche Hinweise

- Nicht in dieser Sandbox end-to-end getestet (kein Nix/systemd, kein ADAM-Zugriff).
  Bitte `sudo nixos-rebuild build` auf deiner Maschine ausführen.
- Der echte ADAM-Login braucht deine Uni-Zugangsdaten und ist interaktiv
  (Browser) — siehe `../adam-sync/`.
- `eingang.py` erkennt Fächer (physik/mathe/chemie) und Dateitypen anhand von
  Dateinamen; unklare Dateien werden gemeldet und bleiben im `eingang/` liegen.
