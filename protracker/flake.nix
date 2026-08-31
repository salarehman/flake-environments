{
  description = "ProTracker (pt2-clone) — accurate native rebuild, no Amiga or ROM required";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # 8bitbubsy/pt2-clone: a highly accurate, native reimplementation of
        # ProTracker 2.3D. No Amiga hardware, Kickstart ROM, or emulator
        # involved — it's a real program that compiles and runs directly.
        pt2-clone = pkgs.stdenv.mkDerivation rec {
          pname = "pt2-clone";
          version = "1.91";

          src = pkgs.fetchFromGitHub {
            owner = "8bitbubsy";
            repo = "pt2-clone";
            rev = "v${version}";
            # Placeholder: `nix build .#pt2-clone` will fail once and print
            # the real hash to paste in here (standard Nix pinning workflow).
            sha256 = "sha256-Kti3oWkgpdZu3w0FjW3pjYSSkda56Ht/a/oaC3JDHIM=";
          };

          nativeBuildInputs = [ pkgs.cmake ];
          buildInputs = [ pkgs.SDL2 ];

          # The repo ships a ready-to-use config at release/other/protracker.ini;
          # stash it in $out so the run wrapper below can seed a user config.
          postInstall = ''
            mkdir -p "$out/share/protracker"
            cp "${src}/release/other/protracker.ini" "$out/share/protracker/protracker.ini"
          '';

          meta = with pkgs.lib; {
            description = "Highly accurate native clone of ProTracker 2.3D — no Amiga/Kickstart needed";
            homepage = "https://github.com/8bitbubsy/pt2-clone";
            license = licenses.bsd3;
            platforms = platforms.unix;
            mainProgram = "pt2-clone";
          };
        };

        runProtracker = pkgs.writeShellApplication {
          name = "protracker";
          runtimeInputs = [ pt2-clone ];
          text = ''
            configDir="$HOME/.config/protracker"
            mkdir -p "$configDir"
            if [ ! -f "$configDir/protracker.ini" ]; then
              cp "${pt2-clone}/share/protracker/protracker.ini" "$configDir/protracker.ini"
            fi
            exec pt2-clone "$@"
          '';
        };
      in
      {
        packages = {
          inherit pt2-clone;
          default = runProtracker;
        };

        apps.default = {
          type = "app";
          program = "${runProtracker}/bin/protracker";
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.cmake pkgs.SDL2 ];
        };
      });
}
