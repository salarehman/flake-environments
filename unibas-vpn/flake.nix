{
  description = "Universität Basel GlobalProtect VPN (gpclient / gpauth)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        # `nix develop` — a shell with the GlobalProtect client (SSO-capable)
        # and its privileged daemon. Connects to vpn.unibas.ch with the
        # Microsoft 365 SSO + 2-Step login.
        #
        #   nix develop
        #   gpclient configure          # portal: vpn.unibas.ch  (first time)
        #   sudo gpclient connect       # root for gpservice, or:
        #   gpclient connect
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.gpclient
            pkgs.gpauth
            # optional friendly extras
            pkgs.gnupg
          ];

          shellHook = ''
            echo "Universität Basel GlobalProtect VPN shell"
            echo "  gpclient version: $(gpclient --version)"
            echo "  Connect:  gpclient connect        (portal vpn.unibas.ch)"
            echo "  Elevation quirk: use 'sudo gpclient connect' if gpservice can't elevate"
            echo "  (nixpkgs gpclient ships no polkit rule; see README in this dir)"
          '';
        };

        packages.default = pkgs.gpclient;

        # Build-only gate for CI: just confirm both derivations evaluate/build.
        packages.full = pkgs.buildEnv {
          name = "unibas-globalprotect-full";
          paths = [ pkgs.gpclient pkgs.gpauth ];
        };
      }) // {
        # ------------------------------------------------------------------
        # NixOS module — import this from your NixOS configuration to get
        # gpclient/gpauth installed and gpservice run as a root systemd unit.
        #
        #   # in your flake's nixosConfigurations.modules:
        #   unibas-vpn.nixosModules.globalprotect
        #   ({ config, pkgs, ... }: {
        #     programs.globalprotect.enable = true;
        #   })
        # ------------------------------------------------------------------
        nixosModules.globalprotect = { lib, config, pkgs, ... }:
          let
            cfg = config.programs.globalprotect;
          in
          {
            options.programs.globalprotect = {
              enable = lib.mkEnableOption "Universität Basel GlobalProtect VPN";
              gpclient = lib.mkOption {
                type = lib.types.package;
                default = pkgs.gpclient;
              };
              gpauth = lib.mkOption {
                type = lib.types.package;
                default = pkgs.gpauth;
              };
              # Run gpservice as a root unit (see https://github.com/yuezk/GlobalProtect-openconnect)
              runAsService = lib.mkOption {
                type = lib.types.bool;
                default = false;
                example = true;
                description = "Run gpservice as a root systemd unit instead of relying on polkit elevation.";
              };
            };

            config = lib.mkIf cfg.enable {
              environment.systemPackages = [ cfg.gpclient cfg.gpauth ];
              security.polkit.enable = true;

              systemd.services.gpservice = lib.mkIf cfg.runAsService {
                description = "GlobalProtect service (Uni Basel)";
                wantedBy = [ "multi-user.target" ];
                after = [ "network-online.target" ];
                wants = [ "network-online.target" ];
                serviceConfig = {
                  ExecStart = "${cfg.gpclient}/bin/gpservice --no-daemon";
                  Type = "simple";
                  Restart = "on-failure";
                  RestartSec = 5;
                };
              };
            };
          };
      };
}
