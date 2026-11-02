# unibas-vpn — Universität Basel GlobalProtect VPN (NixOS)

The Uni Basel campus VPN runs **Palo Alto GlobalProtect** at `vpn.unibas.ch`,
with **SAML/SSO login via Microsoft 365 + 2-Step**. The vendor's
`PanGPLinux-*.tgz` is only officially supported on Ubuntu 22.04/24.04, so on
NixOS the working route is **GlobalProtect-openconnect** (OpenConnect-based,
SSO-capable), packaged in nixpkgs as `gpclient` and `gpauth`.

Both packages are built with `rustPlatform` + `makeBinaryWrapper`: all
libraries and tools (`openssl`, `gnutls`, `webkitgtk`, `systemd` binaries,
the vpnc-script, …) resolve through the Nix store — **no standard-Linux
dynamic linking and no FHS container required**.

## Quick start (`nix develop`)

```bash
nix develop
gpclient configure          # first time: portal = vpn.unibas.ch
gpclient connect            # opens browser for the Microsoft 365 SSO
```

The browser flow runs the university login + 2-Step confirmation; the cookie
is cached at `$HOME/.config/gpclient/cookie.json` for later connects.

## Root-elevation gotcha

`gpservice` (the privileged daemon that sets up the tunnel and routes) needs
root. The nixpkgs `gpclient` package does **not** ship the polkit rule that the
upstream flake module installs, so on its own it can't elevate via `pkexec`.
Two workable options:

1. **Simplest:** run the whole thing as root — `sudo gpclient connect`.
2. **As a service:** enable the bundled NixOS module with `runAsService`, which
   starts `gpservice --no-daemon` as a root `systemd` unit.

## NixOS module (declarative, recommended)

Add this flake as an input and import the module:

```nix
# flake.nix
inputs.unibas-vpn.url = "github:salarehman/flake-environments?dir=unibas-vpn";

# nixosConfigurations.<host>.modules:
unibas-vpn.nixosModules.globalprotect
({
  programs.globalprotect.enable = true;
  programs.globalprotect.runAsService = true;   # gpservice as a root unit
})
```

Then `sudo nixos-rebuild switch` and connect with `gpclient connect` (or the
GUI `gpgui` if you use the upstream module instead).

## Caveats

- In this repo nothing executes `nix build` (CI has no Nix); the flake is
  written against nixpkgs `gpclient` **3.0.5** and GlobalProtect-openconnect
  upstream as of 2026-11-02. Verify with `sudo nixos-rebuild build` on your
  machine.
- The real VPN session needs your Uni Basel credentials and can't be
  smoke-tested headlessly.
