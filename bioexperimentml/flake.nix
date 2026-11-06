{
  description = "BioExperimentML — strict wet-lab experiment records (fetches the private github:salarehman/bioexperimentml repo)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # private source repo, fetched (not built) so the whole project is available
    bioexperimentml = {
      url = "github:salarehman/bioexperimentml";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, bioexperimentml }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python3.withPackages (ps: [ ps.jsonschema ]);
      in
      {
        # `nix build` -> the entire project source (code, schema, docs, samples)
        packages.default = pkgs.runCommand "bioexperimentml" { } ''
          mkdir -p $out
          cp -r ${bioexperimentml}/. $out/
        '';

        # `nix develop` -> a shell with Python + jsonschema to run the scripts
        devShells.default = pkgs.mkShell {
          buildInputs = [ python ];
          shellHook = ''
            echo "BioExperimentML source (private repo): ${bioexperimentml}"
            echo "  validate example:"
            echo "    python ${bioexperimentml}/bioexperimentml-validate.py ${bioexperimentml}/bioexperimentml-example.json"
            echo "  (rdkit optional for quality I8: 'nix shell nixpkgs#python3Packages.rdkit')"
          '';
        };
      });
}
