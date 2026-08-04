{
  description = "Simple Java development environment";

  inputs = {
    nixpkgsstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgsrolling.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgsstable, nixpkgsrolling }:
    let
      system = "x86_64-linux";
      stable = import nixpkgsstable {
        inherit system;
      };
    in
    {
      devShells.${system}.default = stable.mkShell {

        buildInputs = [
          # Java
          stable.temurin-bin
          stable.jdt-language-server
	
	  # maven
	  stable.maven
	
	  # Editor 
	  stable.eclipses.eclipse-java
        ];

        shellHook = ''
          echo "Java development environment loaded"
          echo "Java version:"
          java --version
	  echo "eclipse um den Editor zu starten"
        '';
      };
    };
}

