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

**TODO: adapt this section**

- `bash`, `curl`, `tar`: generic POSIX utilities.
- `SOME_ENV_VAR`: set this environment variable in your shell config to load the correct version of tool x.

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

# Contributing

Contributions of any kind welcome! See the [contributing guide](contributing.md).

[Thanks goes to these contributors](https://github.com/devlincashman/asdf-kube-linter/graphs/contributors)!

# License

See [LICENSE](LICENSE) © [Devlin Cashman](https://github.com/devlincashman/)
