# ipile

**Machine bootstrap and git completion.** One command that takes a
machine from wherever it is to a working development setup: toolchains,
git identities, SSH keys, commit signing that actually verifies, hooks,
and a set of global editor configs.

`ipile` is Yoruba for *foundation*. Plain ASCII everywhere a machine
reads it, never the diacritic form. The workspace scaffolder and task
runner is a separate tool, [culm](../culm).

![Version](https://img.shields.io/badge/version-v4.0-blue)
![Shell](https://img.shields.io/badge/shell-bash%203.2%2B-green)
![License](https://img.shields.io/badge/license-MIT-green)

> **v4.0 is a rewrite.** The two monolithic scripts became ten
> independent modules. Everything is now skippable, re-runnable, and
> reachable on its own. See [Migrating from v3](#-migrating-from-v3).

---

## 📖 Table of contents

- [What it is](#-what-it-is)
- [Install](#-install)
- [Using it](#-using-it)
- [The modules](#-the-modules)
- [Git accounts](#-git-accounts)
- [Safety](#-safety)
- [Requirements](#-requirements)
- [Repository layout](#-repository-layout)
- [Build and release](#-build-and-release)
- [Troubleshooting](#-troubleshooting)
- [Migrating from v3](#-migrating-from-v3)
- [Contributing](#-contributing)
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

```sh
ipile run --dry-run              # see the whole plan first
ipile run --skip dotfiles        # everything but the config files
ipile run --only rust,node --yes # unattended toolchain install
```

`--dry-run` is honoured by every write in the codebase, because they all
go through one wrapper. It creates no files, not even a state file.

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

### Package managers

Linux is no longer apt only. `system` and `git-install` work through an
abstraction covering **apt, dnf, pacman, apk, zypper and brew**, so
Debian, Ubuntu, Fedora, Arch, Alpine and openSUSE all work.

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

## 🗂️ Repository layout

| Path | Role |
| --- | --- |
| `bin/ipile` | The dispatcher |
| `lib/core/` | ui, os, fs, state, identity, registry |
| `lib/modules/` | Ten modules |
| `lib/assets/` | Config files, hooks and shell helpers, as real files |
| `lib/doctor.sh`, `lib/update.sh` | Standalone commands |
| `installer.sh` | What the curl one liner runs |
| `build-and-install.sh` | Packs the tarball and checksums |
| `version.txt` | The published version. Polled by the update check |
| `docs/CONTEXT.md` | Conventions, safety rules, and why v4 is shaped the way it is |

Nothing shipped is generated from a heredoc. What you read in this
repository is what runs on the machine.

## 🔨 Build and release

```sh
bash build-and-install.sh
```

It syntax checks every script, runs shellcheck if available, packs
`lib/` and `bin/` into `ipile.tar.gz`, and writes `SHA256SUMS`. A syntax
error aborts the build, because a tarball that ships one installs
cleanly and then breaks on someone else's machine.

The version comes from `version.txt`, and the same string is packed as
`VERSION`, so the two cannot drift the way they could in v3.

Releasing:

1. Edit the scripts
2. Bump `version.txt`
3. `bash build-and-install.sh`
4. Publish `installer.sh`, `ipile.tar.gz`, `version.txt` and
   **`SHA256SUMS`** at the base URL
5. Push

`SHA256SUMS` is not optional. `update.sh` refuses to install an
unverified download.

Override the host with `IPILE_BASE_URL=... bash build-and-install.sh`.

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

- **Keep every module skippable.** The prompt in front of each one is the
  contract, and it is why the tool is safe to re-run.
- **Never write outside `run`, `fs_write` or `fs_install_asset`.** They
  are what make `--dry-run` and the backups work. A direct `cat >` or
  bare `git config` bypasses both.
- **Never overwrite user data without asking.** Existing keys are reused,
  appends are grep guarded, regeneration defaults to no.
- **Config content lives in `lib/assets/`, never in a heredoc.** Two
  modules installing the same file must install the same bytes.
- **bash 3.2 safe.** No `${VAR,,}`, no associative arrays, no `mapfile`,
  no namerefs.
- **`sed -i` is not portable.** Use `fs_sed_inplace`.
- Bash section dividers are `# === Section Name`.
- **No em dash** in any script, comment, commit message or document.
- Commit messages are one line, `<type>: <description>`.

## 🏛️ Organisation

ipile is a [Zunetra](../handbook) project. Org level decisions, including
naming and reserved names, live in that repository. The sibling projects
are [culm](../culm), the workspace scaffolder and task runner, and
[Klassivox](../Klassivox), the school management platform.

## 📄 Licence

MIT. See [LICENSE](LICENSE).
