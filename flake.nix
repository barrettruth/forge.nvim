{
  description = "forge.nvim — forge-agnostic git workflow for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    vimdoc-language-server.url = "github:barrettruth/vimdoc-language-server";
  };

  outputs =
    {
      nixpkgs,
      systems,
      vimdoc-language-server,
      ...
    }:
    let
      forEachSystem =
        f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
    in
    {
      formatter = forEachSystem (pkgs: pkgs.nixfmt-tree);

      devShells = forEachSystem (
        pkgs:
        let
          vimdoc-ls = vimdoc-language-server.packages.${pkgs.system}.default;
          commonPackages = [
            pkgs.prettier
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
            vimdoc-ls
          ];
        in
        {
          default = pkgs.mkShell {
            packages = commonPackages;
          };
          ci = pkgs.mkShell {
            packages = commonPackages;
          };
        }
      );
    };
}
