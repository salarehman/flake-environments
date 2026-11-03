# adam-sync — Uni Basel ADAM (ILIAS) Auto-Sync

Lädt **neue** und **geänderte** Dateien aus deinen ADAM-Kursen
(Uni Basel, ILIAS) automatisch herunter — vollständig deklarativ als
NixOS-Systemmodul mit `systemd`-Timer. Kein API-Zugriff nötig: es nutzt die
normale ADAM-Websession (Session-Cookies).

## Warum keine einfache Passwort-POST?

ADAM authentifiziert primär über **SWITCH edu-ID SSO (Shibboleth)**
(es gibt zusätzlich die ILIAS-Form `doStandardAuthentication`). Ein
Passwort-POST ist daher nicht verlässlich automatisierbar. Die robuste,
funktionierende Methode:

1. **Einmalig** im Browser anmelden → Session-Cookies werden gespeichert.
2. Der `sync`-Lauf benutzt diese Cookies; werden sie ungültig, meldest du dich
   einfach erneut an.

## Setup (einmalig)

```bash
nix develop            # oder: installiere aus der Flake
adam-sync setup        # öffnet Browser-Login, speichert Cookies:
                       #   ~/.config/adam-sync/cookies.json
```

Bei `loginMode = "form"` können stattdessen `username` + `passwordFile`
gesetzt werden (Nur für ADAM-Konten, die die ILIAS-Form nutzen — die meisten
Uni-Basel-Konten gehen den edu-ID-SSO-Weg).

## Sync

```bash
adam-sync sync            # lädt neue/geänderte Dateien nach ~/ILIAS
adam-sync sync --dry-run  # nur zeigen, was geladen würde
adam-sync courses         # gefundene Objekte auflisten
```

## NixOS-Modul (vollständig deklarativ)

```nix
# flake.nix
inputs.adam-sync.url = "github:salarehman/flake-environments?dir=adam-sync";

# nixosConfigurations.<host>.modules:
adam-sync.nixosModules.default
({
  services.adam-sync = {
    enable = true;
    user   = "me";
    dest   = "/home/me/ILIAS";
    interval = "02:00";   # täglich 02:00, Persistent = true
  };
});
```

Danach:

```bash
sudo nixos-rebuild switch
sudo systemctl start adam-sync        # einmal sofort
systemctl --user daemon-reload        # falls als User gestartet
```

Das Modul erzeugt:
- `systemd.services.adam-sync` (oneshot), läuft als `user` nach
  `network-online.target`;
- `systemd.timers.adam-sync` mit `OnCalendar = interval`, `Persistent = true`,
  so dass ein versäumter Lauf beim nächsten Start nachgeholt wird;
- `StateDirectory=adam-sync` unter `/var/lib/adam-sync` (dort liegt optional
  auch die `cookies.json`, wenn du statt des User-`~/.config` einen zentralen
  Cookie-Ablageort willst).

## Grenzen / ehrliche Hinweise

- **Nicht build-/getestet in dieser Sandbox** (kein Nix/kein sudo). Bitte
  `sudo nixos-rebuild build` auf deiner Maschine ausführen.
- Der echte ADAM-Login braucht deine Uni-Zugangsdaten und kann nicht
  headless getestet werden; das Setup ist daher interaktiv (Browser).
- Dateinamen, Ordner-Tiefe und die konkrete Zerlegung der ILIAS-Seiten sind
  gegen ADAM anzupassen; eine erste lauffähige Basis liegt in `adam_sync.py`.
- Behalte die Nutzungsbedingungen der Uni Basel im Blick; nur eigene
  Kursmaterialien herunterladen.
