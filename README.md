<div align="center">

# asdf-kube-linter [![Build](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/build.yml/badge.svg)](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/build.yml) [![Lint](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/lint.yml/badge.svg)](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/lint.yml)


[kube-linter](https://docs.kubelinter.io/) plugin for the [asdf version manager](https://asdf-vm.com).

</div>

# Contents

- [Dependencies](#dependencies)
- [Install](#install)
- [Why?](#why)
- [Contributing](#contributing)
- [License](#license)

# Dependencies

- `bash`, `curl`, `tar`: generic POSIX utilities.

# Install

Plugin:

```shell
asdf plugin add kube-linter
# or
asdf plugin add kube-linter https://github.com/devlincashman/asdf-kube-linter.git
```

kube-linter:

```shell
# Show all installable versions
asdf list-all kube-linter

# Install specific version
asdf install kube-linter latest

# Set a version globally (on your ~/.tool-versions file)
asdf global kube-linter latest

# Now kube-linter commands are available
kube-linter --help
```

Check [asdf](https://github.com/asdf-vm/asdf) readme for more instructions on how to
install & manage versions.

# Download Logic Details

This plugin determines the correct download URL for `kube-linter` based on the requested version, operating system, and architecture by following these rules derived from the `stackrox/kube-linter` release history:

1.  **GitHub Repository:** `https://github.com/stackrox/kube-linter`
2.  **Version Tag Prefix:**
    *   Tags are prefixed with `v` for versions `0.6.1` and later (e.g., `v0.6.1`, `v0.7.0`).
    *   Tags have no prefix for versions prior to `0.6.1` (e.g., `0.6.0`, `0.5.1`).
3.  **Architecture (`amd64`/`arm64`):**
    *   `amd64` builds are available for all relevant versions. The asset name does not include an architecture suffix for `amd64`.
    *   `arm64` builds are only available for versions `0.6.8` and later.
    *   For `arm64` builds (on supported versions), the architecture suffix `_arm64` is appended to the OS segment of the asset name (e.g., `linux_arm64`, `darwin_arm64`).
    *   Attempting to install an `arm64` version prior to `0.6.8` will result in an error.
4.  **Asset Format (OS-Dependent):**
    *   **Linux:** Uses the `.tar.gz` archive format for all versions providing Linux assets.
        *   Example (`amd64`): `kube-linter-linux.tar.gz`
        *   Example (`arm64`, >= `0.6.8`): `kube-linter-linux_arm64.tar.gz`
    *   **Darwin (macOS):** The format varies by version:
        *   Versions `< 0.5.0`: Uses `.tar.gz` format (e.g., `kube-linter-darwin.tar.gz`).
        *   Versions `>= 0.5.0` AND `< 0.6.8`: Uses a raw binary format (no extension) (e.g., `kube-linter-darwin`).
        *   Versions `>= 0.6.8`: Uses `.tar.gz` format.
            *   Example (`amd64`): `kube-linter-darwin.tar.gz`
            *   Example (`arm64`): `kube-linter-darwin_arm64.tar.gz`
5.  **URL Structure:**
    *   `https://github.com/stackrox/kube-linter/releases/download/{TAG}/{ASSET_FILENAME}`

This logic is implemented in `lib/utils.bash`.

# Contributing

Contributions of any kind welcome! See the [contributing guide](contributing.md).

[Thanks goes to these contributors](https://github.com/devlincashman/asdf-kube-linter/graphs/contributors)!

# License

See [LICENSE](LICENSE) © [Devlin Cashman](https://github.com/devlincashman/)
