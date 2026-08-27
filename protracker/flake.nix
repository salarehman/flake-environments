{
  description = "Fully declarative Amiga ProTracker (FS-UAE) environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ProTracker 2.3F is freeware, so it CAN be pinned and fetched
        # declaratively. The hash below is a placeholder (lib.fakeHash):
        # the first `nix build .#protrackerAdf` will fail and print the
        # real hash to paste in here. That's the standard Nix workflow
        # for pinning a new fetchurl source.
        protrackerAdf = pkgs.fetchurl {
          url = "https://16-bits.org/PT23F.ADF";
          sha256 = pkgs.lib.fakeHash;
        };

        # Kickstart ROMs are copyrighted and can't be fetched here, so
        # everything except the ROM path is baked into this config.
        baseConfig = pkgs.writeText "protracker-base.fs-uae" ''
          [config]
          amiga_model = A500
          floppy_drive_0 = ${protrackerAdf}
          floppy_drive_0_type = 0
        '';

        runProtracker = pkgs.writeShellApplication {
          name = "protracker";
          runtimeInputs = [ pkgs.fs-uae ];
          text = ''
            if [ -z "''${AMIGA_KICKSTART_ROM:-}" ]; then
              echo "Set AMIGA_KICKSTART_ROM to the path of your own legally" >&2
              echo "obtained Kickstart ROM, e.g.:" >&2
              echo "  export AMIGA_KICKSTART_ROM=\$HOME/Amiga/Kickstarts/kick13.rom" >&2
              exit 1
            fi
            if [ ! -f "$AMIGA_KICKSTART_ROM" ]; then
              echo "No file found at AMIGA_KICKSTART_ROM=$AMIGA_KICKSTART_ROM" >&2
              exit 1
            fi

            tmpconfig=$(mktemp --suffix=.fs-uae)
            trap 'rm -f "$tmpconfig"' EXIT
            cat ${baseConfig} > "$tmpconfig"
            echo "kickstart_file = $AMIGA_KICKSTART_ROM" >> "$tmpconfig"

            exec fs-uae "$tmpconfig"
          '';
        };
      in
      {
        packages = {
          inherit protrackerAdf;
          default = runProtracker;
        };

        apps.default = {
          type = "app";
          program = "${runProtracker}/bin/protracker";
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.fs-uae pkgs.fs-uae-launcher ];
        };
      });
}
