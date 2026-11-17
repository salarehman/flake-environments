{
  description = "lernhelfer-sync: adam-sync + Material-Eingang + Lernhelfer-Build automatisieren";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python3.withPackages (ps: [ ps.requests ps.beautifulsoup4 ]);
        tectonic = pkgs.tectonic;

        adamSync = pkgs.stdenv.mkDerivation rec {
          pname = "adam-sync";
          version = "0.1.0";
          src = ./.;
          buildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp adam_sync.py $out/bin/adam-sync
            chmod +x $out/bin/adam-sync
            wrapProgram $out/bin/adam-sync \
              --prefix PYTHONPATH : ${python}/${pkgs.python3.sitePackages}
            runHook postInstall
          '';
        };

        ingest = pkgs.writeShellScriptBin "lernhelfer-ingest" ''
          set -euo pipefail
          : "''${LERNHELFER_MATERIAL:=}";   # Pfad zum privaten Material-Repo
          : "''${LERNHELFER_PUBLIC:=}";     # Pfad zum öffentlichen Lernhelfer-Repo
          if [ -z "$LERNHELFER_MATERIAL" ] || [ -z "$LERNHELFER_PUBLIC" ]; then
            echo "Bitte LERNHELFER_MATERIAL und LERNHELFER_PUBLIC setzen." >&2
            exit 1
          fi
          (cd "$LERNHELFER_MATERIAL" && "${adamSync}/bin/adam-sync" sync)
          (cd "$LERNHELFER_MATERIAL" \
             && "${pkgs.python3}/bin/python3" werkzeuge/eingang.py einordnen --public "$LERNHELFER_PUBLIC")
        '';
      in
      {
        packages = {
          adamSync = adamSync;
          default = ingest;
        };

        apps.default = {
          type = "app";
          program = "${ingest}/bin/lernhelfer-ingest";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ ingest adamSync tectonic pkgs.git ];
          shellHook = ''
            echo "lernhelfer-sync dev shell"
            echo "  ingest:  nix run .# --            (adam-sync sync -> eingang.py einordnen)"
            echo "  bauen:   python3 werkzeuge/build.py --fach <fach>"
            echo "  env:     LERNHELFER_MATERIAL + LERNHELFER_PUBLIC setzen"
          '';
        };
      }) // {
      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.lernhelfer-sync;
          ingest = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        in
        {
          options.services.lernhelfer-sync = {
            enable = lib.mkEnableOption "Lernhelfer Auto-Ingest (adam-sync + einordnen)";
            user = lib.mkOption { type = lib.types.str; default = "root"; };
            materialDir = lib.mkOption { type = lib.types.str; default = ""; description = "Privates Material-Repo (skript/ + eingang/)."; };
            publicDir = lib.mkOption { type = lib.types.str; default = ""; description = "Öffentliches Lernhelfer-Repo."; };
            interval = lib.mkOption { type = lib.types.str; default = "02:00"; description = "systemd-Kalender (täglich 02:00)."; };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ ingest ];

            systemd.services.lernhelfer-sync = {
              description = "Lernhelfer Material-Ingest (adam-sync + einordnen)";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                Type = "oneshot";
                User = cfg.user;
                WorkingDirectory = cfg.materialDir;
                Environment = [
                  "LERNHELFER_MATERIAL=${cfg.materialDir}"
                  "LERNHELFER_PUBLIC=${cfg.publicDir}"
                ];
                ExecStart = "${ingest}/bin/lernhelfer-ingest";
              };
            };

            systemd.timers.lernhelfer-sync = {
              description = "Lernhelfer Material-Ingest regelmäßig";
              wantedBy = [ "timers.target" ];
              timerConfig = { OnCalendar = cfg.interval; Persistent = true; };
            };
          };
        };
    };
}
