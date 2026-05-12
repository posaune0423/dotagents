{
  description = "Pinned CLI tooling for developing dotagents (just, Bun/JS, Lefthook, shell format & lint)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs.lib) genAttrs makeBinPath;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = f: genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      repoPackages = pkgs: [
        pkgs.just
        pkgs.bun
        pkgs.gitMinimal
        pkgs.lefthook
        pkgs.shellcheck
        pkgs.shfmt
      ];

      setupScript =
        pkgs:
        pkgs.writeShellScriptBin "dotagents-setup" ''
          set -euo pipefail
          if [[ ! -f flake.nix ]] || [[ ! -f package.json ]]; then
            echo "dotagents-setup: リポジトリのルート（flake.nix があるディレクトリ）で実行してください。" >&2
            exit 1
          fi
          echo "dotagents-setup: bun install（依存取得 + prepare で lefthook install）…"
          ${pkgs.bun}/bin/bun install
          echo "dotagents-setup: 完了。開発は nix develop 後に just / bun を使えます。"
        '';
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = repoPackages pkgs;
          shellHook = ''
            # 継承 PATH の /usr/bin 等より、この flake の CLI を先に使う（再現性のため）
            export PATH="${makeBinPath (repoPackages pkgs)}:$PATH"
            if [[ ! -d node_modules ]]; then
              echo "[dotagents] node_modules がありません。初回は次のいずれかでセットアップしてください:"
              echo "  nix run .#setup   または   bun install"
            fi
          '';
        };
      });

      apps = forAllSystems (pkgs: {
        setup = {
          type = "app";
          program = "${setupScript pkgs}/bin/dotagents-setup";
        };
      });

      packages = forAllSystems (pkgs: {
        inherit (pkgs) just bun lefthook shellcheck shfmt;
        default = pkgs.symlinkJoin {
          name = "dotagents-toolchain";
          paths = repoPackages pkgs;
        };
      });
    };
}
