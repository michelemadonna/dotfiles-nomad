# dotfiles-nomad

Portable Zsh configuration for macOS and apt-based Linux systems. The installer
clones or reuses the repository, installs the selected tools, generates
`zsh/home/.zshenv` from `zsh/.zshenv.init`, and links it to `~/.zshenv`.

## Installer

Run the interactive wizard from a checkout:

```sh
sh ./install.sh
```

The wizard keeps the editor choice (`micro`, `fresh`, `vim`, or `nano`) and
offers either Oh My Posh or the built-in minimal Zsh prompt. Zsh reads the
selected renderer from `DOTSH_PROMPT` in the generated `.zshenv`.

For a non-interactive installation with the documented defaults:

```sh
sh ./install.sh non-interactive
# Equivalent:
sh ./install.sh --non-interactive
```

To provide explicit choices, use a configuration file:

```sh
sh ./install.sh --conf ./install.conf
```

`--conf` implies non-interactive mode. The file accepts only the keys and
values shown below. It is parsed as data, validated, and never sourced or
executed as a shell script.

```text
PROMPT=ohmyposh
EDITOR=micro
SHOW_FASTFETCH=first-pty
USE_MISE=true
USE_FZF=true
LOAD_SSH_KEY=false
SHOW_SSH_KEY=false
ASKPASS_REQUIRE=false
INTEL_PACKAGE_MANAGER=macports
```

Allowed values:

| Key | Values |
| --- | --- |
| `PROMPT` | `ohmyposh`, `minimal` |
| `EDITOR` | `micro`, `fresh`, `vim`, `nano` |
| `SHOW_FASTFETCH` | `always`, `first-pty`, `never` |
| `USE_MISE`, `USE_FZF` | `true`, `false` |
| `LOAD_SSH_KEY`, `SHOW_SSH_KEY`, `ASKPASS_REQUIRE` | `true`, `false` |
| `INTEL_PACKAGE_MANAGER` | `macports`, `homebrew` |

Blank lines and lines beginning with `#` are ignored. Unknown keys, shell
syntax, unsupported values, and malformed lines stop the installation.

### Shell preferences

The three SSH settings are independent and default to `false`.

| Config key | Zsh variable | Effect when enabled |
| --- | --- | --- |
| `LOAD_SSH_KEY` | `DOTSH_SSH_LOAD_KEY` | Tries to add supported local identities to the SSH agent at Zsh startup. With this setting off, use `ssh-load` to add keys on demand. |
| `SHOW_SSH_KEY` | `DOTSH_SSH_SHOW_KEY` | Shows the fingerprints reported by the active agent at startup, including keys that were already loaded. |
| `ASKPASS_REQUIRE` | `DOTSH_SSH_ASKPASS_REQUIRE` | Sets `SSH_ASKPASS_REQUIRE=force` for SSH commands in the shell, including commands run after startup. The configured askpass helper must be available. |

`SHOW_FASTFETCH` is saved as `DOTSH_SHOW_FASTFETCH`. Use `always` to show the
overview in eligible interactive shells, `first-pty` to also require the first
active terminal, or `never` to skip the overview and its optional installation.
Both display modes retain the filters for detected editor and tmux shells and
skip shells that inherit a marker from a previous display. The first-PTY check
counts active terminals across the system, including SSH and other terminal
applications, and accounts for Lig's extra PTY. The wizard defaults to `never`
and a fresh non-interactive install defaults to `first-pty`. Existing
`true`, `first`, and `false` values map to the corresponding new modes.

### Package manager on macOS Intel

The wizard lets you choose MacPorts or Homebrew on Intel. The installer checks
`INTEL_PACKAGE_MANAGER` in `--conf`, then `DOTSH_INTEL_PACKAGE_MANAGER` in the
environment, then the saved preference, and defaults to MacPorts. The previous
name `DOTFILES_INTEL_PACKAGE_MANAGER` remains a fallback within each of the
environment and saved preference checks.

Homebrew on Intel is Tier 3 as of September 2026. With no CI coverage or new
Intel binary packages, some formulae may build from source or fail. Homebrew
plans to stop running on Intel in or after September 2027. MacPorts is the
recommended choice for setups that need to remain in use in 2028.
[Homebrew Support Tiers](https://docs.brew.sh/Support-Tiers)

### Installer usage

All options are:

```text
install.sh [non-interactive|--non-interactive] [--conf FILE]
install.sh --help
```

### One-line bootstrap

The installer can be started from standard input. It opens `/dev/tty` for the
interactive menu, so the pipe remains available for the script itself:

```sh
curl -fsSL https://raw.githubusercontent.com/michelemadonna/dotfiles-nomad/main/install.sh | sh
```

The raw URL becomes available after `install.sh` is committed and published on
the referenced branch.

Pass options to `sh` after `-s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/michelemadonna/dotfiles-nomad/main/install.sh \
  | sh -s -- --conf "$HOME/install.conf"
```

The default clone source is
`https://github.com/michelemadonna/dotfiles-nomad.git`. Override it without
editing the installer:

```sh
DOTFILES_REPO_URL=https://github.com/example/dotfiles.git sh ./install.sh
```

For the piped form, put the override on the `sh` side of the pipe:

```sh
curl -fsSL https://example.test/install.sh \
  | DOTFILES_REPO_URL=https://github.com/example/dotfiles.git sh
```

### Packages and installation methods

The base package groups remain package-manager-specific:

| System and method | Base packages |
| --- | --- |
| macOS Intel, MacPorts | `bat`, `eza`, `fd`, `git`, `git-delta`, `htop`, `ripgrep`, `tmux`, `tree`, `wget`, `chafa`, `mediainfo`, `poppler`, `file`, `bind9`, `7zip`; bundled fonts |
| macOS, Homebrew | `bat`, `eza`, `fd`, `git`, `git-delta`, `htop`, `ripgrep`, `tmux`, `tree`, `wget`, `chafa`, `mediainfo`, `poppler`, `file`, `bind`, `sevenzip`; `font-fira-code-nerd-font` cask |
| apt-based Linux | `bat`, `eza`, `chafa`, `mediainfo`, `poppler-utils`, `tree`, `file`, `dnsutils`, `fd-find`, `wget`, `grc`, `ripgrep`, `python3-pip`, `command-not-found`, `git-delta`, `tmux`, `htop`, `unzip`, `curl`, `fontconfig`, `7zip`; bundled fonts |

The selected editor is installed through MacPorts, Homebrew, or APT when it is
not already available. Fresh uses its compatible release package on Linux.
Fastfetch also uses the active package manager. Oh My Posh uses MacPorts or
Homebrew on macOS and installs into `~/.local/bin` on Linux. Mise, fzf, and Lig
use their official release installers/assets and are stored in
`~/.local/bin`.

Before installing a required or selectable tool, the installer checks the
corresponding command and `~/.local/bin` where applicable. Existing tools are
retained, while configuration generation and links still run. Lig's release
installer selects a compatible macOS or Linux asset for the current
architecture and verifies its checksum.

## Docker demo

The image contains the complete selectable tool set before the wizard starts:
all four editors, Mise, Fastfetch, Oh My Posh, Lig, fzf, and the base packages.
The runtime menu therefore changes only the demo user's configuration.

After the wizard, the container creates three SSH keys in the demo user's
`~/.ssh`. The RSA key (`id_rsa`) uses the passphrase `123`. The Ed25519 and
ECDSA keys have no passphrase. Each new container generates its own test keys.

Build the default remote `main` branch and then start the menu:

```sh
./docker-demo.sh remote
```

Build another remote branch:

```sh
./docker-demo.sh remote feature/example
```

Build the current checkout:

```sh
./docker-demo.sh local
```

`DOTFILES_REPO_URL`, `DOTFILES_REF`, and `DOCKER_IMAGE` can override the remote
repository, default branch, and image name respectively. Both remote and local
images defer the installer wizard until `docker run`, after the complete image
has been built. Remote builds invalidate only the repository-clone stage so a
moving branch is refreshed while the expensive tool layer remains cached.
