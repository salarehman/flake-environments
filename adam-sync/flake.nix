{
  description = "adam-sync: neue Dateien aus ADAM (Uni Basel ILIAS) automatisch herunterladen";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        adamSync = pkgs.stdenv.mkDerivation rec {
          pname = "adam-sync";
          version = "0.1.0";
          src = ./.;
          python = pkgs.python3.withPackages (ps: [ ps.requests ps.beautifulsoup4 ]);
          buildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp adam_sync.py $out/bin/adam-sync
            chmod +x $out/bin/adam-sync
            wrapProgram $out/bin/adam-sync \
              --prefix PATH : ${pkgs.python3}/bin \
              --prefix PYTHONPATH : ${python}/${pkgs.python3.sitePackages}
            runHook postInstall
          '';
        };
      in
      {
        # `nix develop` — shell mit dem Tool + Abhängigkeiten
        devShells.default = pkgs.mkShell {
          buildInputs = [ adamSync pkgs.python3 pkgs.beautifulsoup4 pkgs.python3.pkgs.requests ];
          shellHook = ''
            echo "adam-sync dev shell"
            echo "  ersteinrichtung: adam-sync setup"
            echo "  sync:            adam-sync sync [--dry-run]"
          '';
        };

        packages.default = adamSync;
      }) // {
      # ----------------------------------------------------------------------
      # NixOS module — importiere diesen, um den Sync vollständig deklarativ
      # als systemd-Service + Timer zu betreiben (kein manuelles Einstellen).
      #
      #   # flake.nix inputs:
      #   adam-sync.url = "github:salarehman/flake-environments?dir=adam-sync";
      #
      #   # nixosConfigurations.<host>.modules:
      #   adam-sync.nixosModules.default
      #   { services.adam-sync = {
      #       enable = true;
      #       dest = "/home/me/ILIAS";
      #       interval = "02:00";            # systemd-Kalender (täglich 02:00)
      #       user  = "me";                  # läuft als dieser Benutzer
      #       # login_mode/username/password NUR setzen, wenn ILIAS-Form,
      #       # sonst SSO: Cookies nach einmaligem Browser-Login ablegen unter
      #       #   /var/lib/adam-sync/cookies.json  (owner = user)
      #     };
      #   };
      # ----------------------------------------------------------------------
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.adam-sync;
          adamSync = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        {
          options.services.adam-sync = {
            enable = lib.mkEnableOption "ADAM-Sync (Uni Basel ILIAS)-Timer";

            package = lib.mkOption {
              type = lib.types.package;
              default = adamSync;
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "root";
            };

            dest = lib.mkOption {
              type = lib.types.path;
              default = builtins.getEnv "HOME";
            };

            interval = lib.mkOption {
              type = lib.types.str;
              default = "02:00";
              description = "systemd-Kalenderausdruck für den Timer (z. B. '02:00' täglich).";
            };

            loginMode = lib.mkOption {
              type = lib.types.enum [ "sso" "form" ];
              default = "sso";
            };

            username = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };

            passwordFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Nur für loginMode=form. Datei (root-schlüßend) mit dem ADAM-Passwort.";
            };

            stateDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/adam-sync";
            };

            runtimeDeps = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = with pkgs; [ openssl cacert ];
            };
          };

          config = lib.mkIf cfg.enable {
            # lazy: netzwerk-Tools + Zertifikate für requests
            environment.systemPackages = [ cfg.package ] ++ cfg.runtimeDeps;

            systemd.services.adam-sync = {
              description = "ADAM (Uni Basel) Datei-Sync";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                Type = "oneshot";
                User = cfg.user;
                StateDirectory = "adam-sync";
                WorkingDirectory = cfg.dest;
                ExecStart = "${cfg.package}/bin/adam-sync sync";
              } // lib.optionalAttrs (cfg.loginMode == "form" && cfg.passwordFile != null) {
                EnvironmentFile = cfg.passwordFile;
                Environment = "ADAM_PASSWORD_FILE=${toString cfg.passwordFile}";
              };
            };

            systemd.timers.adam-sync = {
              description = "ADAM-Sync regelmäßig";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = cfg.interval;
                Persistent = true;
              };
            };
          };
        };
    };
}
