# bioexperimentml

Fetches the **private** repo `github:salarehman/bioexperimentml` and exposes it as a
flake, so the whole project (format, validators, converters, docs, samples) is one
`nix build` / `nix develop` away.

> Because the source repo is **private**, the `bioexperimentml` flake input requires
> GitHub authentication for the Nix fetcher. On a machine with `gh` authenticated you can
> pass it through, e.g.:
>
> ```sh
> nix develop --extra-access-tokens "github.com=$(gh auth token)"
> ```
>
> or add an `access-tokens = github.com=<token>` entry to `~/.config/nix/nix.conf`.
> Without credentials, the input cannot be downloaded.

## Usage

```sh
nix build     # -> result/ = the whole project source
nix develop   # -> Python shell (with jsonschema) to run the validators/scripts
```

Once in the shell, the scripts run from the fetched source (see the project's `README.md`
for the full quickstart). The ChEMBL corpus is regenerated with
`python build_focus_corpus.py` (network + `rdkit` optional for the quality layer).
