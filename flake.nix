{
  description = "forge.nvim — GitHub issues and pull requests in Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    neovim = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      systems,
      neovim,
      ...
    }:
    let
      forEachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f system);
    in
    {
      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nvim = neovim.packages.${system}.default;
          devTools = [
            (pkgs.luajit.withPackages (
              ps: with ps; [
                busted
                nlua
              ]
            ))
            pkgs.gh
            pkgs.just
            pkgs.biome
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
            pkgs.vimdoc-language-server
            nvim
          ];
          shell = pkgs.mkShell {
            packages = devTools;
            VIMRUNTIME = "${nvim}/share/nvim/runtime";
            FORGE_YAML_PARSER = "${pkgs.vimPlugins.nvim-treesitter-parsers.yaml}";
          };
        in
        {
          default = shell;
          ci = shell;
        }
      );
    };
}
