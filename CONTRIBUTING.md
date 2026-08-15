# Contributing

Development, issues, and pull requests happen on
[GitHub](https://github.com/barrettruth/forge.nvim).

## Scope

forge.nvim is a Neovim plugin for GitHub issues and pull requests from the
editor. It is not a git client, a diff viewer, or a client for any forge other
than GitHub. Diffs belong to
[diffs.nvim](https://forge.barrettruth.com/barrettruth/diffs.nvim) and checks
to [ci.nvim](https://forge.barrettruth.com/barrettruth/ci.nvim).

## Pull Requests

Bug fixes and documentation fixes are welcome. AI-generated contributions are
not accepted.

For new behavior, open an issue first unless the change is small and already
fits the project's scope.

Behavior or configuration changes should update `README.md` and
`doc/forge.txt` when appropriate.

## Development

It is preferred to use the Nix development shell, which bundles all necessary
tools:

```sh
nix develop
```

## Checks

Run the local checks before opening a pull request:

```sh
nix develop --command just ci
```
