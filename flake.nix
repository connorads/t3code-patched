{
  description = "T3 Code nightly with local patches";

  # Pinned to a nixpkgs whose t3code derivation builds the pinned nightly.
  # Consumers must not override this with `follows`: a different nixpkgs
  # changes the store path and misses the binary cache.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/6a8196756aab924f46fe3be35e931882e0304dd1";

  outputs =
    { nixpkgs, ... }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      pins = builtins.fromJSON (builtins.readFile ./pins.json);

      unwrapped = pkgs.t3code.unwrapped.overrideAttrs (
        finalAttrs: old: {
          version = pkgs.lib.removePrefix "v" pins.tag;
          src = pkgs.fetchFromGitHub {
            owner = "pingdotgg";
            repo = "t3code";
            inherit (pins) tag;
            hash = pins.srcHash;
          };
          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (finalAttrs)
              pname
              version
              src
              pnpmWorkspaces
              ;
            pnpm = pkgs.pnpm_11;
            fetcherVersion = 4;
            hash = pins.pnpmDepsHash;
          };
          patches = (old.patches or [ ]) ++ [ ./patches/cache-badge.patch ];
          # nixpkgs names the bundle after the stable channel.
          postInstall = (old.postInstall or "") + ''
            mv "$out/Applications/T3 Code (Alpha).app" "$out/Applications/T3 Code (Nightly).app"
            substituteInPlace "$out/Applications/T3 Code (Nightly).app/Contents/Info.plist" \
              --replace-fail "<string>T3 Code (Alpha)</string>" "<string>T3 Code (Nightly)</string>"
          '';
        }
      );
    in
    {
      packages.${system} = {
        inherit unwrapped;
        default = pkgs.t3code.override { t3code-unwrapped = unwrapped; };
      };
    };
}
