# magicdrive/aqua-registry

This is a registry for [aqua](https://aquaproj.github.io/) to install CLI tools developed by [magicdrive](https://github.com/magicdrive).

## Packages

| Package | Description | Platforms | Installable versions |
| --- | --- | --- | --- |
| [magicdrive/ark](https://github.com/magicdrive/ark) | Code intelligence engine for AI coding agents | darwin, linux, windows (amd64, arm64) | v0.0.2 and later |
| [magicdrive/enma](https://github.com/magicdrive/enma) | Yet another event-driven command runner | darwin, linux, windows (amd64, arm64) | v0.0.3 and later |
| [magicdrive/goreg](https://github.com/magicdrive/goreg) | Yet another alternate goimports, gofmt tool | darwin, linux, windows (amd64, arm64) | v0.0.1 and later |
| [magicdrive/kjak](https://github.com/magicdrive/kjak) | Deliver one notification to many destinations (Slack, Discord and e-mail) | darwin, linux (amd64, arm64), windows (amd64; arm64 through emulation) | v0.0.1 and later |
| [magicdrive/git-parallel](https://github.com/magicdrive/git-parallel) | Run the command in parallel much to multiple repositories | darwin, linux | v1.0.3 and later |
| [magicdrive/hephaestus](https://github.com/magicdrive/hephaestus) | Forge release artifacts into reliable distributions | darwin, linux, windows (amd64, arm64) | v0.1.0-rc.2 and later |
| [magicdrive/kirke](https://github.com/magicdrive/kirke) | Yet another JSON to Go Struct Converter | darwin, linux (amd64, arm64); windows from v1.0.6 | v0.0.1 and later |
| [magicdrive/t](https://github.com/magicdrive/t) | Lazy tmux wrapper | darwin, linux (amd64, arm64) | v1.2.0-rc.1 and later |

Notes:

- Every download is verified with the SHA-256 checksum file published in the
  same GitHub Release (`checksum.type: github_release`).
- `git-parallel` and `t` are Bash scripts. aqua does not install dependencies,
  so install them yourself: `git-parallel` needs `bash` and `git`, and **`t`
  needs `tmux`** (for example `brew install tmux` or `apt-get install tmux`).
  They are not available on Windows.
- `t` has no `--version` option. Its version is in the bundled man page
  (`t.1`, next to the installed `t`).
- Releases older than the versions in the table have no downloadable assets;
  aqua reports "no asset is released for this version" for them.

## Usage

### 1. Add the registry to `aqua.yaml`

Pin `ref` to a tag of this repository (see the
[Releases](https://github.com/magicdrive/aqua-registry/releases)). A package is
available from the first tag whose `registry.yaml` contains it.

```yaml
registries:
  - name: custom
    type: github_content
    repo_owner: magicdrive
    repo_name: aqua-registry
    ref: v1.1.0 # replace with the latest tag
    path: registry.yaml
```

### 2. Allow the registry with a policy

aqua only installs packages from registries other than the Standard Registry
when a [policy](https://aquaproj.github.io/docs/reference/security/policy-as-code/)
allows them. Create `aqua-policy.yaml`:

```yaml
registries:
  - name: custom
    type: github_content
    repo_owner: magicdrive
    repo_name: aqua-registry
    ref: semver(">= 1.0.0")
    path: registry.yaml
packages:
  - registry: custom
```

And then allow the policy:

```bash
aqua policy allow ./aqua-policy.yaml
```

### 3. Add packages and pin their versions

Each package is pinned to a version with `@<tag>` (the tag of the tool's
GitHub Release, including the leading `v`):

```yaml
packages:
  - name: magicdrive/ark@v6.7.2
    registry: custom
  - name: magicdrive/enma@v2.1.2
    registry: custom
  - name: magicdrive/goreg@v1.3.11
    registry: custom
  - name: magicdrive/kjak@v0.0.4
    registry: custom
  - name: magicdrive/git-parallel@v1.0.3
    registry: custom
  - name: magicdrive/hephaestus@v1.2.0
    registry: custom
  - name: magicdrive/kirke@v1.2.8
    registry: custom
  - name: magicdrive/t@v1.2.1
    registry: custom
```

Then install them:

```bash
aqua install
```

To record and enforce the checksums in your repository, enable aqua's
[checksum verification](https://aquaproj.github.io/docs/reference/security/checksum/)
and run `aqua update-checksum`:

```yaml
checksum:
  enabled: true
  require_checksum: true
```

## Compatibility

- Package IDs did not change. Existing `magicdrive/enma`, `magicdrive/kirke`,
  `magicdrive/goreg` and `magicdrive/ark` entries in your `aqua.yaml` keep
  working.
- The tools moved from GoReleaser to Hephaestus, and their asset names changed
  over time (checksum file names, `zip` instead of `tar.gz` on Windows, no
  Windows build in early kirke releases). `registry.yaml` describes each
  change with `version_overrides`, so old versions resolve to the assets that
  were actually published for them.

## Development

CI (`.github/workflows/ci.yaml`) runs on every pull request:

- `registry.yaml` is validated against the aqua JSON schema.
- `ci/cross-install.sh` installs the cases in `ci/cross-cases.txt` (latest
  versions on every platform and the boundaries of every `version_overrides`
  entry) by overriding the target platform with `AQUA_GOOS` / `AQUA_GOARCH`.
  Each case downloads the real asset and verifies its checksum; unsupported
  platforms and versions without assets must be rejected, and a tampered
  checksum must fail.
- `ci/smoke.sh` installs the latest version of every package on Linux
  (amd64, arm64) and macOS (arm64), runs each command, checks the reported
  version and compares the recorded checksums with the Release checksum files.
- `ci/test-lib.sh` tests that checksum comparison with a stub `curl`: a
  mismatch, or an `aqua-checksums.json` that is missing, unparsable or empty,
  must fail.

When you add a package or a new release changes its asset names, update
`registry.yaml`, `ci/cross-cases.txt` and the version list in `ci/smoke.sh`.
