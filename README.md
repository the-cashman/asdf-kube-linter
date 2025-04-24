<div align="center">

# asdf-kube-linter [![Build](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/build.yml/badge.svg)](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/build.yml) [![Lint](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/lint.yml/badge.svg)](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/lint.yml) [![Test Downloads](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/test-download.yml/badge.svg)](https://github.com/devlincashman/asdf-kube-linter/actions/workflows/test-download.yml)


[kube-linter](https://docs.kubelinter.io/) plugin for the [asdf version manager](https://asdf-vm.com).

</div>

# Contents

- [Dependencies](#dependencies)
- [Install](#install)
- [Why?](#why)
- [Testing](#testing)
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

# Testing

This plugin is thoroughly tested to ensure compatibility with both newer and older versions of kube-linter. The testing process includes:

## Automated Tests

- **Download Testing**: The plugin automatically tests downloads for both newer versions (≥ 0.6.1 with 'v' prefix) and older versions (< 0.5.0 without 'v' prefix) to ensure backward compatibility.
- **Comprehensive Runner Testing**: Tests run on all GitHub-hosted runner types:
  - Linux x64: ubuntu-latest, ubuntu-24.04, ubuntu-22.04, ubuntu-20.04
  - Windows x64: windows-latest, windows-2022, windows-2019
  - Linux ARM64: ubuntu-24.04-arm, ubuntu-22.04-arm
  - Windows ARM64: windows-11-arm
  - macOS Intel: macos-13
  - macOS ARM64 (Apple Silicon): macos-latest, macos-14, macos-15
- **Multi-Architecture Support**: Tests verify compatibility with multiple architectures:
  - x86_64 (Intel/AMD 64-bit)
  - arm64 (Apple Silicon, ARM-based Linux)
- **CI Integration**: All tests are integrated into GitHub Actions workflows and run on every push, pull request, and on a scheduled basis.

## Manual Testing

You can manually test the download functionality by running:

```shell
# Test default versions (newer and older) on current architecture
./test_download.sh

# Test specific versions
./test_download.sh 0.7.2 0.2.0 0.6.0

# Test specific architecture
./test_download.sh --arch darwin_arm64 0.7.2

# Test all supported architectures (simulated)
./test_download.sh --all-archs

# Show help
./test_download.sh --help
```

This helps verify that the plugin can correctly download and install any version of kube-linter.

# Contributing

Contributions of any kind welcome! See the [contributing guide](contributing.md).

[Thanks goes to these contributors](https://github.com/devlincashman/asdf-kube-linter/graphs/contributors)!

# License

See [LICENSE](LICENSE) © [Devlin Cashman](https://github.com/devlincashman/)
