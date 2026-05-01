{
  description = "Pinned CLI tooling for developing dotagents (Bun/JS, Lefthook, shell format & lint)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs.lib) genAttrs;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = f: genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      repoPackages = pkgs: [
        pkgs.bun
        pkgs.lefthook
        pkgs.shellcheck
        pkgs.shfmt
      ];
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = repoPackages pkgs;
        };
      });

      packages = forAllSystems (pkgs: {
        inherit (pkgs) bun lefthook shellcheck shfmt;
        default = pkgs.symlinkJoin {
          name = "dotagents-toolchain";
          paths = repoPackages pkgs;
        };
      });
    };
}
