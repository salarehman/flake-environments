{
  description = "Common Lisp (SBCL) development and build environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Name of your entry-point source file and the executable it produces.
        # Adjust these to match your project.
        mainFile = "main.lisp";
        binName = "my-lisp-app";
      in
      {
        # `nix develop` — a REPL-ready shell with SBCL, rlwrap for a nicer
        # readline experience, and Quicklisp available on disk.
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.sbcl
            pkgs.rlwrap
            pkgs.quicklisp
          ];

          shellHook = ''
            echo "Common Lisp dev shell (SBCL $(sbcl --version | cut -d' ' -f2))"
            echo "Run: rlwrap sbcl"
          '';
        };

        # `nix build` — compiles ${mainFile} into a standalone executable
        # core image via sb-ext:save-lisp-and-die. Assumes your entry point
        # defines a `main` function to call as :toplevel.
        packages.default = pkgs.stdenv.mkDerivation {
          pname = binName;
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.sbcl ];

          buildPhase = ''
            runHook preBuild
            sbcl --non-interactive \
                 --eval '(compile-file "${mainFile}")' \
                 --load "${mainFile}" \
                 --eval '(sb-ext:save-lisp-and-die "${binName}"
                           :toplevel #'"'"'main
                           :executable t
                           :compression t)'
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ${binName} $out/bin/${binName}
            runHook postInstall
          '';
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/${binName}";
        };
      });
}
