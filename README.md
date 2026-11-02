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
