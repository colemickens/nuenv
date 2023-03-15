{
  description = "nuenv: a Nushell environment for Nix";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; overlays = [ self.overlays.nuenv ]; };
        inherit system;
      });
    in
    {
      overlays = {
        nuenv = (final: prev: {
          nuenv.mkDerivation = self.lib.mkNushellDerivation;
        });
      };

      lib = {
        # A derivation wrapper that calls a Nushell builder rather than the standard environment's
        # Bash builder.
        mkNushellDerivation =
          { nushell        # Nushell package
          , name           # The name of the derivation
          , src            # The derivation's sources
          , system         # The build system
          , packages ? [ ] # Packages provided to the realisation process
          , build ? ""     # The Nushell script used for realisation
          , debug ? false  # Run in debug mode
          }:

          derivation {
            inherit name src system;
            builder = "${nushell}/bin/nu";
            args = [ ./builder.nu ];

            # Attributes passed to the environment (prefaced with __nu_ to avoid naming collisions)
            __nu_nushell_version = nushell.version;
            __nu_envFile = ./env.nu;
            __nu_packages = packages ++ [ nushell ];
            __nu_debug = debug;

            # The Nushell build logic for the derivation (either a raw string or a path to a .nu file)
            build =
              if builtins.isString build then
                build
              else if builtins.isPath build then
                (builtins.readFile build)
              else throw "build attribute must be either a string or a path"
            ;
          };
      };

      apps = forAllSystems ({ pkgs, system }: {
        default = {
          type = "app";
          program = "${pkgs.nushell}/bin/nu";
        };
      });

      devShells = forAllSystems ({ pkgs, system }: {
        default = pkgs.mkShell {
          packages = with pkgs; [ nushell ];
        };

        # A dev environment with Nuenv's helper functions available
        nuenv = pkgs.mkShell {
          packages = with pkgs; [ nushell ];
          shellHook = ''
            nu --config ./env.nu
          '';
        };
      });

      packages = forAllSystems ({ pkgs, system }: rec {
        default = nushell;

        # An example Nushell-based derivation
        nushell = pkgs.nuenv.mkDerivation {
          name = "just-experimenting";
          inherit system;
          nushell = pkgs.nushell;
          packages = with pkgs; [ go ];
          src = ./.;
          build = ./example.nu;
          debug = true;
        };

        # The Nushell-based derivation above but with debug mode disabled
        nushellNoDebug = pkgs.nuenv.mkDerivation {
          name = "just-experimenting";
          inherit system;
          nushell = pkgs.nushell;
          packages = with pkgs; [ go ];
          src = ./.;
          build = ./example.nu;
        };

        # The same derivation above but using the stdenv
        std = pkgs.stdenv.mkDerivation {
          name = "just-experimenting";
          inherit system;
          buildInputs = with pkgs; [ go ];
          src = ./.;
          buildPhase = ''
            versionFile="go-version.txt"
            echo "Writing version info to ''${versionFile}"
            go version > $versionFile
            substituteInPlace $versionFile --replace "go" "golang"

            helpFile="go-help.txt"
            echo "Writing help info to ''${helpFile}"
            go help > $helpFile
            substituteInPlace $helpFile --replace "go" "golang"
          '';
          installPhase = ''
            mkdir -p $out/share
            cp go-*.txt $out/share
          '';
        };

        # Derivation that relies on the Nushell derivation
        other = pkgs.stdenv.mkDerivation {
          name = "other";
          src = ./.;
          installPhase = ''
            mkdir -p $out/share

            cp ${self.packages.${system}.default}/share/go-version.txt $out/share/version.txt
          '';
        };
      });
    };
}
