{
  description = "Mojo experimentation environment: newest Python + Mojo, numpy, biopython (nixpkgs-unstable only)";

  # -----------------------------------------------------------------------
  # Why this looks the way it does
  #
  # Mojo is NOT packaged in nixpkgs (it's Modular's proprietary compiler;
  # nixpkgs closed the packaging request since it can only be distributed
  # via pip/pixi/uv: `pip install mojo`). So Nix's job here is just to give
  # you a clean, reproducible Python + the system libraries Mojo's compiler
  # (and numpy's / biopython's compiled C extensions) need at runtime.
  # Mojo, numpy and biopython themselves get pip-installed into a local
  # .venv the first time you enter the shell.
  #
  # On Linux, pip-downloaded binaries (Mojo's compiler/LLDB, numpy,
  # biopython) expect a normal FHS layout (/lib64, /usr/lib, a standard
  # dynamic linker, ...) that the Nix store doesn't provide. So on Linux
  # we wrap everything in `buildFHSEnv`, which gives those binaries that
  # layout without touching your system. On macOS this isn't needed (no
  # ELF/glibc mismatch), so we just use a plain devShell there.
  # -----------------------------------------------------------------------

  inputs = {
    # Unstable channel only, as requested.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # `python3` always tracks nixpkgs' current default interpreter, so
        # on the unstable channel this is the newest Python available.
        python = pkgs.python3;

        # Shared libraries pip-installed compiled wheels commonly need
        # (Mojo's compiler/LLDB, numpy, biopython's C extensions).
        nativeLibs = with pkgs; [
          stdenv.cc.cc.lib
          zlib
          ncurses
          libxml2
          libxcrypt
          openssl
        ];

        # Runs every time you enter the shell. Creates the venv once,
        # installs mojo/numpy/biopython once, then just activates it.
        venvSetup = ''
          export VENV_DIR="$PWD/.venv"
          if [ ! -d "$VENV_DIR" ]; then
            echo "→ creating virtualenv in .venv ..."
            python3 -m venv "$VENV_DIR"
          fi
          source "$VENV_DIR/bin/activate"

          if [ ! -f "$VENV_DIR/.deps-installed" ]; then
            echo "→ installing mojo, numpy, biopython into .venv (first run only) ..."
            pip install --upgrade pip
            pip install mojo numpy biopython
            touch "$VENV_DIR/.deps-installed"
          fi

          echo ""
          echo "Python:  $(python3 --version)"
          echo "Mojo:    $(mojo --version 2>/dev/null || echo 'installed — run: mojo --version')"
          echo "(delete .venv to force a clean reinstall)"
        '';
      in
      {
        devShells.default =
          if pkgs.stdenv.isLinux then
            (pkgs.buildFHSEnv {
              name = "mojo-env";
              targetPkgs = _: [
                python
                pkgs.python3Packages.pip
                pkgs.python3Packages.virtualenv
              ] ++ nativeLibs;
              profile = venvSetup;
              runScript = "bash";
            }).env
          else
            pkgs.mkShell {
              buildInputs = [ python ] ++ nativeLibs;
              shellHook = venvSetup;
            };
      }
    );
}
