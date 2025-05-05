# magicdrive/aqua-registry

This is a registry for [aqua](https://aquaproj.github.io/) to install CLI tools developed by [magicdrive](https://github.com/magicdrive).

## Packages

- [magicdrive/enma](https://github.com/magicdrive/enma) - Yet another integration software with file monitoring
- [magicdrive/kirke](https://github.com/magicdrive/kirke) - JSON to Golang Struct Generator
- [magicdrive/goreg](https://github.com/magicdrive/goreg) - Golang import order stabilizer

## Usage

Add this registry to your `aqua-policy.yaml`:

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

And then allowing policy.

```bash
aqua policy allow ./aqua-policy.yaml
```

Add this registry to your `aqua.yaml`:

```yaml
registries:
  - type: github_content
    repo_owner: magicdrive
    repo_name: aqua-registry
    path: registry.yaml
    ref: {{Version}}
```

Then you can install packages like:

```yaml
packages:
  - name: magicdrive/enma@{{Version}}
    registry: custom
  - name: magicdrive/kirke@{{Version}}
    registry: custom
  - name: magicdrive/goreg@v{{Version}}
    registry: custom
```

And then execute install command.

```bash
aqua install
```
