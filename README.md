# flake-environments

A collection of self-contained Nix flake environments. Each subdirectory is a
flashcard flake that brings up a reproducible toolchain with `nix develop`,
`nix build`, or a NixOS module.

## Contents

- `Java/` — JDK + Maven Java build environment (project scaffold included).
- `common-lisp/` — SBCL + rlwrap + Quicklisp development shell.
- `mojo/` — Mojo language environment.
- `protracker/` — ProTracker / module-music environment.
- `unibas-vpn/` — Universität Basel GlobalProtect VPN (gpclient/gpauth; NixOS
  module included). See its `README.md`.
- `adam-sync/` — Uni Basel ADAM (ILIAS) auto-sync: lädt neue Kursdateien
  als NixOS-Systemmodul + systemd-Timer (kein API nötig, Session-Cookies).
- `bioexperimentml/` — strict wet-lab experiment records (format + validators +
  converters + LLM extraction agent). Fetches the **private**
  `github:salarehman/bioexperimentml` repo; needs GitHub auth for the fetcher.
