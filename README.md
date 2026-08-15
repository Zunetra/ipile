# ipile

**Machine bootstrap and git completion.** One command that takes a
machine from wherever it is to a working development setup: toolchains,
git identities, SSH keys, commit signing that actually verifies, hooks,
and a set of global editor configs.

`ipile` is Yoruba for *foundation*. Plain ASCII everywhere a machine
reads it, never the diacritic form. The workspace scaffolder and task
runner is a separate tool, [culm](https://github.com/Zunetra/culm).

![Version](https://img.shields.io/badge/version-v4.0-blue)
![Shell](https://img.shields.io/badge/shell-bash%203.2%2B-green)
![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

```sh
curl -fsSL https://shogo-portfolio-ebon.vercel.app/scripts/installer.sh | sh
ipile
```

> **v4.0 is a rewrite.** The two monolithic scripts became ten
> independent modules. Everything is now skippable, re-runnable, and
> reachable on its own. See [Migrating from v3](#-migrating-from-v3).

---

## 📖 Table of contents

- [What it is](#-what-it-is)
- [Features](#-features)
- [Requirements](#-requirements)
- [Install](#-install)
- [Using it](#-using-it)
- [Command reference](#-command-reference)
- [Environment variables](#-environment-variables)
- [The modules](#-the-modules)
- [Git accounts](#-git-accounts)
- [Safety](#-safety)
- [Architecture](#-architecture)
- [Repository layout](#-repository-layout)
- [Local development](#-local-development)
- [Build and release](#-build-and-release)
- [Troubleshooting](#-troubleshooting)
- [Migrating from v3](#-migrating-from-v3)
- [Contributing](#-contributing)
- [Organisation](#-organisation)
- [Licence](#-licence)

## 🌍 What it is

A set of bash modules behind one command. Each module is a self contained
unit that knows four things about itself: what it changes, whether it is
already applied, how to apply it, and how to prove it worked.

That last part is what makes ipile flexible. It reads your machine
first. If git is already configured the way you like it, the git modules
report themselves as done and never ask. If you only want to add another
GitHub account, `ipile git accounts` goes straight there and touches
nothing else.

Two things follow from that:

- **Nothing happens without a prompt in front of it.** Every module is
  offered, and skipping moves to the next one.
- **Re-running is safe.** Existing keys are reused, existing config
  blocks are detected before being appended, and every file is backed up
  before it is overwritten.

## ✨ Features

### Toolchains

- Rust through rustup, with rustfmt and clippy, updating in place if
  rustup is already there
- Node through nvm, pinned to a major and set as the default alias
- Corepack, pnpm and yarn
- System build tools through **apt, dnf, pacman, apk, zypper or brew**,
  so Debian, Ubuntu, Fedora, Arch, Alpine, openSUSE and macOS all work

### Git identity

- One identity, or many, one per remote, with no manual switching
- ed25519 keys, **optionally passphrase protected**
- Key registration as **both** an authentication key and a signing key,
  automatically through the `gh` CLI when it is authenticated
- `~/.ssh/allowed_signers` written, so signed commits actually verify
- Non GitHub hosts as a per profile field: GitLab, Bitbucket, Gitea and
  self hosted instances
- Drift detection across all four sources a profile lives in, with repair

### Everyday helpers

- `gclone`, which clones through the right identity and bakes the alias
  into that repository
- `gitprofile`, to list profiles and override one for a single shell
- `git whoami`, plus ten more aliases
- Eight global hook types, each chaining to the repository's own hook so
  husky, lefthook and commitlint keep working

### Safety

- `--dry-run` on every write path, provably creating zero files
- A timestamped backup of every file before it is overwritten, and
  `ipile restore` to put them back
- A transcript of every run
- SHA256 verification on install and update
- Idempotent: a second run adds no duplicate config, aliases or shell
  functions

### Diagnostics

- `ipile status`, a read only table of what is set up
- `ipile doctor`, which verifies rather than assumes: that signing
  verifies, that each hook chains, that no profile has drifted

## ✅ Requirements

| Requirement | Note |
| --- | --- |
| **bash 3.2 or newer** | macOS's stock bash works. v3 needed bash 4 |
| **Linux or macOS** | apt, dnf, pacman, apk, zypper or brew |
| **`curl`** | Install, update, and the remote installers |
| **`ssh` and `ssh-keygen`** | Keys, agent, connection test |
| **`sudo`** on Linux | Only for the `system` and `git-install` modules |

Running as root is detected and needs an explicit confirmation. WSL is
detected and warned about, because its ssh-agent does not persist across
terminal restarts. Windows outside WSL is not supported.

Node is **not** a requirement. ipile is bash. `package.json` in this
repository is a script runner for people working on ipile, nothing more.

## 🚀 Install

```sh
curl -fsSL https://shogo-portfolio-ebon.vercel.app/scripts/installer.sh | sh
```

The installer downloads the tarball, **verifies it against a published
SHA256 checksum**, unpacks it into `$HOME/.ipile`, and symlinks one
executable onto your `PATH`. A checksum mismatch aborts the install.

Then restart your shell and run:

```sh
ipile
```

### What lands on disk

```
$HOME/.ipile/
├── bin/ipile              The dispatcher, the only thing on your PATH
├── lib/
│   ├── core/              Shared: ui, os, fs, state, identity, registry
│   ├── modules/           One file per unit of work
│   ├── assets/            The config files, as files
│   ├── doctor.sh
│   └── update.sh
├── var/                   State, run logs, backups. Survives updates
└── VERSION

$HOME/.local/bin/ipile     Symlink
```

Nothing is installed system wide. `sudo` is only used later, by the
`system` module, for your package manager.

### Uninstall

```sh
rm -rf "$HOME/.ipile" "$HOME/.local/bin/ipile"
```

That removes ipile. To undo what it configured, restore the backups
first with `ipile restore` (see [Safety](#-safety)).

## 🧭 Using it

Three ways in, all running the same modules.

```sh
ipile                             # menu, pick what you want
ipile git accounts                # jump straight to one module
ipile run --only rust,node --yes  # non interactive, for CI
```

### Worked examples

**See the whole plan before anything happens.**

```sh
ipile run --dry-run
```

Every write announces itself instead of happening:

```
→ Writing /home/you/.gitignore_global
[dry-run] backup /home/you/.gitignore_global -> ~/.ipile/var/backups/20260815-064138/
[dry-run] write /home/you/.gitignore_global (mode 644)
[dry-run] git config --global core.excludesfile /home/you/.gitignore_global
```

**Add a work GitHub account to a machine that already has a personal
one.**

```sh
ipile git accounts
```

It prints what already exists, asks how many **new** accounts you want,
and never touches the profiles already there.

**Set up a fresh CI runner, unattended.**

```sh
ipile run --only rust,node,pkgmanagers --yes
```

**Configure everything except the editor and formatter configs**, because
you keep your own.

```sh
ipile run --skip dotfiles
```

**Undo a run.**

```sh
ipile restore                 # list the runs
ipile restore 20260814-212711 # put that run's files back
```

## 📋 Command reference

| Command | What it does |
| --- | --- |
| `ipile` | Interactive menu, with a status table first |
| `ipile run [options]` | Run modules |
| `ipile <module>` | Run exactly one module |
| `ipile status` | What is set up, changes nothing |
| `ipile doctor` | Verify everything, changes nothing |
| `ipile restore [run-id]` | List or restore a backup |
| `ipile update` | Update ipile itself, checksum verified |
| `ipile version` | Print the version |

### Run options

| Option | Effect |
| --- | --- |
| `--only a,b,c` | Run only these modules |
| `--skip a,b,c` | Run everything except these |
| `--yes` | Take every default, never prompt. For CI |
| `--dry-run` | Print every change, make none |

`--dry-run` is honoured by every write in the codebase, because they all
go through one wrapper. It creates no files, not even a state file.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Everything asked for succeeded, or was skipped |
| `1` | A module failed, or the command could not start: unknown module, unsupported OS, a refused confirmation, a failed download |

**A failed module does not abort the run**, because one broken step must
not cost you the other nine. The run continues, reports
`Finished, with failures.`, points at `ipile doctor`, and then **exits
`1`**, so `ipile run --yes` fails a CI pipeline the way it should.

Two deliberate exceptions:

- **`--dry-run` always exits `0`.** It changed nothing, so there is
  nothing to have failed.
- **`ipile doctor` always exits `0`**, even when it finds problems. It
  reports rather than gates, and exiting non-zero would kill a shell
  running under `set -e` that only wanted to read the output.

## ⚙️ Environment variables

```sh
# Where the installer and the update check fetch from. Set it to run
# your own mirror, or to test a release before publishing it.
IPILE_BASE_URL="https://shogo-portfolio-ebon.vercel.app/scripts"

# Where state, run logs and backups live. Defaults to $IPILE_HOME/var.
# Point it elsewhere to keep the install directory read only.
IPILE_VAR="$HOME/.ipile/var"

# Any value disables colour, per no-color.org. Colour is also dropped
# automatically when stdout is not a terminal, so piping is already clean.
NO_COLOR=1
```

Everything else prefixed `IPILE_` is internal, set by the dispatcher and
exported to the modules. Setting it yourself is unsupported and mostly
ineffective: `IPILE_DRY_RUN` and `IPILE_ASSUME_YES` are reset from the
command line flags on every run.

## 🧩 The modules

Ten, run in this order. Dependencies come before dependents.

| Module | What it changes |
| --- | --- |
| `system` | System packages and build tools |
| `rust` | rustup, the stable toolchain, rustfmt, clippy |
| `node` | nvm, then Node 24 as the default |
| `pkgmanagers` | Corepack, pnpm, yarn |
| `git-install` | Git itself |
| `git-identity` | One identity: name, email, SSH key, signing |
| `git-accounts` | Several identities, one per remote |
| `git-hooks` | Global hooks, plus `gclone` and `gitprofile` |
| `git-globals` | Git config and 11 aliases |
| `dotfiles` | VS Code, Prettier, solhint, lint-staged, gitignore |

Every module implements the same four functions, which is what makes the
menu, `status`, `doctor` and `--dry-run` all work without special cases:

```bash
describe()   # what this changes on your machine
detect()     # 0 = already applied, 1 = not applied, 2 = partial
apply()      # do it
verify()     # 0 = provably working. doctor calls this too
```

A module may also declare `MODULE_NEEDS`, and the runner pulls those in
automatically. `ipile git accounts` on a machine with no git installs git
first rather than walking you through generating keys and then failing on
the first `git config`. A dependency that is already satisfied is noted
and skipped, not re-run.

Because `doctor` calls the same `verify()` the installer does, the
diagnostic and the installer can never disagree about what "installed"
means.

## 🔑 Git accounts

The problem: several git identities on one machine, and never having to
think about which one is active.

**The glue is the SSH host alias.** Each profile gets a named `Host`
block mapping an alias to the real host with its own key:

```
Host github-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_work
```

Clone through `gclone` and the alias is baked into that repository's
`.git/config`. Every future push uses the right key, with no switching.

### It reads before it writes

A profile lives in four independent places, and they drift:

| Source | Holds |
| --- | --- |
| `~/.gitidentities` | One line per profile. Read by the hooks and helpers |
| `~/.gitconfig-<alias>` | That profile's name, email, signing key |
| `~/.ssh/config` | The `Host` block |
| `~/.ssh/id_ed25519_<alias>` | The keypair |

`ipile git accounts` checks all four and prints a table before asking for
anything, marking each profile complete or naming exactly what it is
missing. Then it offers to repair the broken ones. The old version only
looked at `~/.gitconfig-*` and so could not see any of this.

### Adding accounts

It asks how many **new** accounts you want, where **0 is a valid answer**
(running it only to repair or rename is a supported path). Existing
profiles are never touched.

Per account it collects alias, name, host, username and email, confirms
them, then:

1. Generates an ed25519 key, **optionally passphrase protected**, or
   reuses an existing one after asking
2. Appends an SSH config block, guarded so it is never written twice
3. Registers the key with your host, **as both an authentication key and
   a signing key**. If the `gh` CLI is authenticated it offers to upload
   both for you instead of the copy and paste dance
4. Tests the connection, and **retries with you until it passes**:

```
  SSH test failed for github-work.

  [1] I have added the key now, test again
  [2] Show me the public key again
  [3] Show me the registration steps again
  [4] Regenerate the keypair and start this profile over
  [5] Continue without verifying, I will fix it later
```

5. Writes the profile config and the identity map line
6. Registers the key in `~/.ssh/allowed_signers`

That last step is why signing verifies. Signing and verifying are
separate settings: without an allowed signers file git signs correctly
and then reports "No signature", which reads as a signing failure. v3's
multi account script never wrote it, so every multi account machine had
this bug.

### Non GitHub hosts

Each profile has a host field, defaulting to `github.com`. GitLab,
Bitbucket, Gitea and self hosted instances work. The alias prefix follows
the host, so `github-work` and `gitlab-work` can coexist.

### Everyday use

```sh
gclone https://github.com/acme/api   # clone as a chosen identity
git whoami                           # who does this repo commit as
gitprofile                           # list profiles, active one marked
gitprofile work                      # override for this shell only
$EDITOR ~/.gitidentities             # edit by hand at any time
```

## 🛡️ Safety

| Guarantee | How |
| --- | --- |
| **Nothing is overwritten unbacked** | Every write backs the file up to `~/.ipile/var/backups/<run-id>/` first, with a `MANIFEST` |
| **Reversible** | `ipile restore <run-id>` puts them all back |
| **Previewable** | `--dry-run` prints every change and makes none |
| **Idempotent** | Running twice adds no duplicate config, aliases or shell functions |
| **Auditable** | Every run writes a transcript to `~/.ipile/var/logs/` |
| **Verified downloads** | Install and update both check SHA256 before unpacking |

### Hooks do not break your other hooks

`core.hooksPath` is global: once set, git stops looking in `.git/hooks`
entirely. v3 installed a `pre-commit` that chained to the repo's own hook
but a `pre-push` that did not, and installed no other hook types at all,
which silently disabled husky, lefthook and commitlint machine wide.

v4 installs **eight** hook types (`pre-commit`, `pre-push`, `commit-msg`,
`prepare-commit-msg`, `post-commit`, `post-merge`, `post-checkout`,
`pre-rebase`), and every one of them hands over to the repository's own
hook of the same name with `exec`, passing arguments and stdin through
and propagating the exit code. `ipile doctor` checks that the chaining is
intact.

## 🏗️ Architecture

One dispatcher, a core that every module shares, and modules that know
nothing about each other.

```
                       bin/ipile
                    the dispatcher
                          |
        +-----------------+-----------------+
        |                 |                 |
   cmd_menu           cmd_run          cmd_status
   cmd_<module>       cmd_doctor       cmd_restore
        |                 |                 |
        +--------+--------+-----------------+
                 |
          lib/core/registry.sh
   resolves MODULE_NEEDS, orders, prompts, runs
                 |
   +-------------+-------------+
   |             |             |
describe()   detect()      apply()   verify()
   |             |             |          |
   +-------------+------+------+----------+
                        |
                   lib/core/
    ui.sh    prompts and every line of output
    os.sh    which OS, which package manager
    fs.sh    every write, every backup, --dry-run
    state.sh what a run did, for status and update
    identity.sh  the four sources of a git profile
                        |
                   lib/assets/
      the config files, hooks and shell helpers,
      as real files rather than heredocs
```

Three properties fall out of that shape:

- **`--dry-run` cannot be forgotten.** No module writes directly. They
  all go through `fs.sh`, so a new module inherits dry run and backups
  without doing anything.
- **`doctor` cannot drift from the installer**, because it calls the same
  `verify()`.
- **A module is addable without touching anything else.** Drop a file in
  `lib/modules/`, add its id to the list, and the menu, `status`,
  `doctor`, `--only` and `--skip` all pick it up.

## 🗂️ Repository layout

```
ipile/
├── bin/
│   └── ipile                  The dispatcher, and the only entry point
├── lib/
│   ├── core/
│   │   ├── ui.sh              Colours, banner, prompts, every output helper
│   │   ├── os.sh              OS and package manager detection
│   │   ├── fs.sh              Writes, backups, and the --dry-run wrapper
│   │   ├── state.sh           What a run did, read by status and update
│   │   ├── identity.sh        The four sources a git profile lives in
│   │   └── registry.sh        Module ordering and MODULE_NEEDS resolution
│   ├── modules/               Ten modules, one contract
│   ├── assets/                Config files, hooks and shell helpers
│   ├── doctor.sh              Verify everything, change nothing
│   └── update.sh              Self update, checksum verified
├── scripts/
│   └── shellcheck.sh          Lint, fetching a static binary if needed
├── docs/
│   └── CONTEXT.md             Conventions, safety rules, why v4 is shaped so
├── installer.sh               What the curl one liner runs
├── build-and-install.sh       Packs the tarball and writes SHA256SUMS
├── version.txt                The published version, polled by update
├── package.json               Script runner for local work
└── LICENSE                    MIT
```

Nothing shipped is generated from a heredoc. What you read in this
repository is what runs on the machine.

## 💻 Local development

ipile needs no Node to run. `package.json` exists only so the commands
you use while working on it have names.

```sh
git clone git@github.com:Zunetra/ipile.git
cd ipile
pnpm lint:install     # fetches a shellcheck binary into .tools/
pnpm test
```

### Trying it without touching your machine

Two levels. The first shows you the plan, the second shows you the
result.

```sh
pnpm dry              # the plan against your real machine, writes nothing
pnpm dry:yes          # same, no prompts
```

```sh
pnpm demo             # the full interactive flow, into /tmp/ipile-demo
pnpm demo:accounts    # just the git accounts flow, which is the one to watch
pnpm demo:doctor      # doctor against the sandbox
pnpm demo:tree        # what the sandbox produced
pnpm demo:clean       # delete it
```

`demo` sets `HOME=/tmp/ipile-demo`, so everything runs for real, writes
real files, and none of them are yours. It is the honest way to see the
flow, because a dry run can only tell you it *would* generate a key,
while the sandbox gives you the key, the `~/.ssh/config` block, and the
retry menu when the connection test fails.

Two things to expect in the sandbox: the SSH test genuinely reaches
GitHub and will fail for a key you have not registered, which is the
point, and state still lands in `ipile/var/` next to the checkout rather
than in the fake home.

### Every script

| Script | What it runs |
| --- | --- |
| `pnpm start` | `ipile` from the checkout, interactive menu |
| `pnpm status` | `ipile status` |
| `pnpm doctor` | `ipile doctor` |
| `pnpm dry` | `ipile run --dry-run` |
| `pnpm dry:yes` | `ipile run --dry-run --yes` |
| `pnpm demo` | Full flow into `/tmp/ipile-demo` |
| `pnpm demo:accounts` | The `git-accounts` module into the sandbox |
| `pnpm demo:doctor` | `doctor` against the sandbox |
| `pnpm demo:tree` | List what the sandbox produced |
| `pnpm demo:clean` | Delete the sandbox |
| `pnpm check` | `bash -n` across `bin/` and `lib/` |
| `pnpm lint` | shellcheck, with the vetted exclusions |
| `pnpm lint:install` | Fetch the shellcheck binary only |
| `pnpm build` | Pack the tarball and write `SHA256SUMS` |
| `pnpm test` | `check`, then `lint` |

`pnpm lint` prefers a `shellcheck` already on your `PATH` and otherwise
downloads a static binary into `.tools/`, detecting linux or darwin and
x86_64 or aarch64. It **fails** when it cannot lint, unlike
`build-and-install.sh`, which prints a skip notice and carries on.

## 🔨 Build and release

```sh
pnpm build            # or: bash build-and-install.sh
```

It syntax checks every script, runs shellcheck if available, packs
`lib/` and `bin/` into `ipile.tar.gz`, and writes `SHA256SUMS`. A syntax
error aborts the build, because a tarball that ships one installs
cleanly and then breaks on someone else's machine.

The version comes from `version.txt`, and the same string is packed as
`VERSION`, so the two cannot drift the way they could in v3. Keep
`package.json`'s `version` in step with it by hand; nothing enforces
that yet.

Releasing:

1. Edit the scripts
2. Bump `version.txt`
3. `pnpm build`
4. Publish `installer.sh`, `ipile.tar.gz`, `version.txt` and
   **`SHA256SUMS`** at the base URL
5. Push

`SHA256SUMS` is not optional. `update.sh` refuses to install an
unverified download.

Override the host with `IPILE_BASE_URL=... pnpm build`.

### Planned, not built

Recorded here rather than implied. See
[handbook 0004](https://github.com/Zunetra/handbook/blob/main/decisions/0004-distribution-channels.md).

- **npm, Homebrew and crates.io.** Only the shell installer exists. The
  crates.io channel needs a thin Rust wrapper, because crates.io will not
  host a bash project and rewriting a machine bootstrap in Rust would
  need a toolchain the machine does not have yet.
- **GitHub Releases.** Install and update both verify SHA256, but nothing
  publishes a `SHA256SUMS` at the URL yet, so both warn and continue
  rather than protecting anyone. A personal deploy is also a single point
  of failure for everyone's setup.
- **`ipile uninstall --revert`.** `ipile restore` covers files. Nothing
  yet reverses git config keys.

## 🔧 Troubleshooting

### `ipile: command not found` right after installing

A running shell does not re-read its rc file. `source ~/.bashrc`, or
restart the terminal. `ipile doctor` checks whether `~/.local/bin` is
actually on your `PATH`.

### Commits are signed but show unverified

The key has to be on your host **twice**, once as an Authentication Key
and once as a Signing Key. `ipile git accounts` walks you through both
and retries until the connection test passes.

### `git log --show-signature` says "No signature"

Missing or incomplete `~/.ssh/allowed_signers`. `ipile doctor` checks for
this specifically, including whether your own email is listed. Fix with
`ipile git identity`.

### A repository's own hooks stopped running

They should not. Run `ipile doctor`, which verifies every installed hook
chains to the repository's own. If one reports "does NOT chain", re-run
`ipile git-hooks`.

### I want my old config files back

```sh
ipile restore              # list runs
ipile restore 20260814-212711
```

### The connection test keeps failing

It loops rather than giving up, offering to show the key again, show the
steps again, or regenerate the keypair. Outside the tool:

```sh
ssh -T git@github-work     # per alias
ipile doctor --network     # tests every profile
```

### Output is full of escape codes

You are piping to something that is not a terminal but forcing colour
somewhere upstream. Set `NO_COLOR=1`. Colour is dropped automatically
when stdout is not a terminal.

## 📦 Migrating from v3

Run the installer again. Nothing is migrated automatically because
nothing needs to be: your git config, SSH keys, hooks and home directory
config files are all where v3 left them, and v4 detects them.

```sh
curl -fsSL https://shogo-portfolio-ebon.vercel.app/scripts/installer.sh | sh
ipile status     # see what v4 thinks is already done
ipile doctor     # see what v3 left broken
```

`ipile doctor` will most likely flag two things v3 left behind:

- **No `allowed_signers`**, if you used `git-multiple-accounts`. Fix with
  `ipile git identity`.
- **Hooks that do not chain**, if you used v3's hook system. Fix with
  `ipile git-hooks`.

The old command names still work and forward to the new ones:

| v3 | v4 |
| --- | --- |
| `ipile dev-setup` | `ipile run` |
| `ipile git-multiple-accounts` | `ipile git accounts` |

The two v3 scripts, `dev-setup.sh` and `git-multiple-accounts.sh`, are
gone. They duplicated seven config files between them and had already
drifted apart. That duplication is what v4 exists to remove.

## 🤝 Contributing

Read [docs/CONTEXT.md](docs/CONTEXT.md) first. It holds the module
contract, the safety rules, and the bugs that are not to be
reintroduced. The short version:

- **Keep every module skippable.** The prompt in front of each one is the
  contract, and it is why the tool is safe to re-run.
- **Never write outside `run`, `fs_write` or `fs_install_asset`.** They
  are what make `--dry-run` and the backups work. A direct `cat >` or
  bare `git config` bypasses both.
- **`detect()` must not write anything**, caches included. `rustup
  component list` creating `~/.rustup` was a real dry run violation.
- **Never overwrite user data without asking.** Existing keys are reused,
  appends are grep guarded, regeneration defaults to no.
- **Config content lives in `lib/assets/`, never in a heredoc.** Two
  modules installing the same file must install the same bytes.
- **bash 3.2 safe.** No `${VAR,,}`, no associative arrays, no `mapfile`,
  no namerefs.
- **`sed -i` is not portable.** Use `fs_sed_inplace`.
- **A helper assigning through `eval` must namespace its own locals**, or
  it silently writes its own variable instead of the caller's.
- Bash section dividers are `# === Section Name`.
- **No em dash** in any script, comment, commit message or document.
- Commit messages are one line, `<type>: <description>`.

Before opening a pull request:

```sh
pnpm test        # bash -n, then shellcheck at zero findings
pnpm demo        # exercise the flow you changed, in the sandbox
```

## 🏛️ Organisation

ipile is a [Zunetra](https://github.com/Zunetra/handbook) project. Org level decisions, including
naming, distribution channels and the README standard, live in that
repository. The sibling projects are [culm](https://github.com/Zunetra/culm), the workspace
scaffolder and task runner, and [Klassivox](https://github.com/Zunetra/Klassivox), the school
management platform.

## 📄 Licence

MIT. See [LICENSE](LICENSE).
