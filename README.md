# dev-setup

<p align="center">
    <a href="https://github.com/jmgilman/dev-setup/actions/workflows/ci.yml">
        <img src="https://github.com/jmgilman/dev-setup/actions/workflows/ci.yml/badge.svg"/>
    </a>
</p>

> A bash script for configuring an M1 MacBook Pro development environment

## Usage

Download the setup script and validate the checksum:

```bash
curl -s https://raw.githubusercontent.com/jmgilman/dev-setup/master/setup.sh -o setup.sh && \
curl -s https://raw.githubusercontent.com/jmgilman/dev-setup/master/setup.sh.sha256 -o setup.sh.sha256 && \
shasum -a 256 -c setup.sh.sha256
```

Run the setup script:

```bash
bash setup.sh
```

## Overview

The setup script takes care of the following:

1. Global system values (i.e. hiding dock)
1. Global CLI tools
1. User-specific development tools
1. User-specific GUI applications
1. User-specific dotfiles and shell configurations

The result is a complete development environment with all needed tools
available.

## Architecture

The setup script utilizes three primary tools for bootstrapping.

### Nix

Nix is installed onto the system in multi-user mode. Additionally, the
`nix-darwin` and `home-manager` packages are also installed and configured on
the system. The `nix-darwin` package is installed using the default installer
and the environment is later built by a provided flake file.

### Brew

The `brew` package manager is installed onto the system. All GUI applications
are installed using `brew` through a given `bundle` file.

### Chezmoi

Chezmoi is ran in an isolated environment (using `nix shell`) and is used to
pull down dotfiles. Chezmoi is what provides `nix-darwin` and `brew` the needed
configurations for performing the bootstrap process.

## Development

Development dependencies are handled by Nix:

```bash
nix develop
```

Alternatively, you can use `direnv` to automatically enable the environment:

```bash
direnv allow
```

## Contributing

Check out the [issues][01] for items needing attention or submit your own and
then:

1. [Fork the repo][02]
1. Create your feature branch (git checkout -b feature/fooBar)
1. Commit your changes (git commit -am 'Add some fooBar')
1. Push to the branch (git push origin feature/fooBar)
1. Create a new Pull Request

[01]: https://github.com/jmgilman/dev-setup/issues
[02]: https://github.com/jmgilman/dev-setup/fork
