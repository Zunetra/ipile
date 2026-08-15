# Context

**Conventions and hard-won context for ipile.** How code in this
repository is written, and the things a fresh session would otherwise
rediscover the hard way.

State is not tracked here. The code and the git history track state.
Org-level decisions, including how ipile is distributed, live in
[../../handbook/decisions/](../../handbook/decisions/).

**How to use this file:** when the owner corrects a decision, the
correction is appended under the section it belongs to. Corrections are
authoritative and outrank anything stated elsewhere.

**Last updated:** 2026-08-15

---

## The module contract

Every file in `lib/modules/` implements the same four functions, and
nothing else is a module.

| Function | Contract |
| --- | --- |
| `describe` | One line for the menu and for `ipile status`. No side effects. |
| `detect` | Reports `installed`, `partial`, or `absent` by looking at the machine. **Must not write anything**, including caches. |
| `apply` | Does the work. Honours `IPILE_DRY_RUN`. |
| `verify` | Proves `apply` worked. `ipile doctor` calls this same function, so a check written once serves both. |

**`detect` writing to disk is a real bug, not a theoretical one.**
`rustup component list` creates `~/.rustup` as a side effect, which broke
the dry-run guarantee below until it was guarded.

**`MODULE_NEEDS` declares dependencies, and the runner resolves them
transitively before anything runs.** A satisfied dependency is reported
and skipped, not re-run.

| Module | Needs |
| --- | --- |
| `git-identity`, `git-accounts`, `git-hooks`, `git-globals`, `dotfiles` | `git-install` |
| `pkgmanagers` | `node` |

`dotfiles` is in that list because it sets `core.excludesfile`, which is
a git call like any other. Without the declaration, `ipile git accounts`
on a machine with no git walked the user through generating a key and
registering it on GitHub, then died on the first `git config`. That is
the worst possible place to fail.

---

## Safety rules that are not negotiable

**A full dry run creates zero files.** Not "writes nothing important".
Zero. Verified by running against a sandboxed `HOME` and then `find`ing
it. Any module that breaks this breaks the only promise that makes a tool
touching `~/.ssh` safe to try.

**Back up before mutating, always.** Existing files go to
`~/.ipile/backups/<timestamp>/` before they are overwritten, and
`ipile restore` brings them back. Users have their own `.prettierrc`.

**Append only.** Never rewrite a block ipile did not create. Grep-guard
every append so a second run adds nothing, and prove it: a second run
still yields exactly eleven aliases and no duplicate rc functions.

**Destructive operations refuse to run non-interactively.** `restore`
declining under `IPILE_ASSUME_YES` is correct behaviour, not a bug.

**Config content lives once, in `lib/assets/`.** The v3 tool kept its own
copy of the same six config files in each of two scripts, and they
drifted. One of the drifts, `~/.ssh/allowed_signers` being written by one
script and not the other, meant a machine could sign commits correctly
and then report "No signature" on verify. It shipped as a README
troubleshooting entry, which is a known bug documented instead of fixed.
Never reintroduce a second copy of a shipped file.

---

## Bash rules

**bash 3.2 safe, everywhere.** macOS still ships 3.2, and a bootstrap
tool that asks you to bootstrap bash first is a chicken and egg problem.
None of these may appear anywhere in the tree:

- `${VAR,,}` and `${VAR^^}` case modification
- associative arrays, `declare -A`
- `mapfile` and `readarray`
- namerefs, `declare -n`
- `coproc`
- `&>>` and `|&`
- `globstar`
- `[[ -v ]]`
- `${var@Q}`

Checked by a static scan, since no 3.2 binary exists on the development
machine. That is a scan, not an execution, and the distinction is worth
keeping honest.

**A helper that assigns through `eval` must namespace its own locals.**
`ui_menu` used an internal variable named `choice`, and so did every
caller, so `eval` wrote the helper's own local and the caller's was never
set. Under `set -u` that crashed the retry loop outright, and it had been
silently defaulting the runner to "run" for some time before that. All
three eval-assigning helpers now prefix their internals.

**`export` after a failed command still succeeds.** `gitprofile` exported
an empty git author when `git config` failed, so commits were silently
authored by nobody. Check the command, then export.

**shellcheck must report zero findings**, and it runs in
`build-and-install.sh`. Exclusions are named individually with a comment
explaining each. A blanket exclusion is how a linter starts crying wolf,
and the three genuine findings it caught were two dead locals and a
masked return value.

---

## Git profiles: four sources of truth

A profile is not one thing. It is four, and they drift independently:

- `~/.gitidentities`
- `~/.gitconfig-<alias>`
- the `Host` block in `~/.ssh/config`
- the keypair actually on disk

**Reconcile all four and print the table before asking for anything
new.** The v3 tool globbed `~/.gitconfig-*` only, so it could not see a
profile listed in `~/.gitidentities` with no key, a key with no `Host`
block, or a `Host` block pointing at a key that had been deleted. Drift
detection and repair both work against all four.

**Signing and verifying are separate settings.** `user.signingkey` makes
commits sign. `~/.ssh/allowed_signers` makes them verify. A tool that
does one and not the other produces commits that look broken to their own
author.

**A failed SSH test is a loop, not a warning.** Printing a warning and
moving on leaves a half-configured profile with no signal that anything
needs doing. The menu offers test again, show the key, open the keys
page, regenerate, skip this account, or continue anyway, and it repeats
until the test passes or the user explicitly gives up.

**Host is a per-profile field, never hardcoded.** Someone will be on
GitLab, Bitbucket, Gitea, or a self-hosted enterprise instance. This is
also why `gclone` rewrites URLs per the profile's own host: supporting
GitLab profiles while rewriting only `github.com` meant a profile could
be created and then never used.

---

## Testing

**Execution is the only evidence that counts.** Four bugs in the identity
modules survived writing, review, and a clean shellcheck, and every one
of them was found the first time the code actually ran. Dry run proves
the safety contract; it proves nothing about correctness.

The tests that are worth re-running after any change to the git modules:

- Generate a real key in a sandbox `HOME`, then make a commit and check
  `git verify-commit` returns `Good "git" signature` and exit 0.
- Break the machine three ways (delete a key, leave an identity entry
  with nothing behind it, leave an SSH `Host` block with nothing behind
  it) and confirm all three are detected with a precise reason, then
  repaired.
- Invoke an installed global hook against a repo-local hook and confirm
  the argument passes through and a non-zero exit propagates.
- Build a `PATH` mirroring every system binary except `git`, so
  `command -v git` genuinely fails, and confirm dependency resolution
  pulls `git-install` in.

**`ssh-add` in a test reaches the real agent** through an inherited
`SSH_AUTH_SOCK`. Unset it, or clean up afterwards and verify the agent is
back to the keys it started with.

---

## Git

**Committing is an explicit instruction, never an assumption.** Finish
the work and leave it uncommitted.

**Pushing is a separate explicit instruction.** Permission to commit is
not permission to push.

**Every commit is signed**, and every message is one line,
`<type>: <description>`, using `feat`, `fix`, `refactor`, `chore`,
`test`, `docs`, `perf`, or `style`. No body, no trailers, no
co-authorship attribution.

**`bin/` is in the global gitignore this tool itself installs**, so
`bin/ipile` needs the negation that is now in `.gitignore`. Check that
before assuming a file is committed.

---

## Not done

- **Distribution.** Only the shell installer exists. npm, the Homebrew
  tap, and the crates.io wrapper are unbuilt. See
  [handbook 0004](../../handbook/decisions/0004-distribution-channels.md).
- **Hosting.** Install and update both verify SHA256, but nothing
  publishes a `SHA256SUMS` at the URL yet, so both warn and continue
  rather than protecting anyone. Until `version.txt` v4.0 is published,
  every command also prints a spurious update notice.
- **Version pins in code.** `NODE_VERSION` and `NVM_VERSION` are named
  constants at the top of `node.sh` rather than buried, but they belong
  in a manifest.
- **`ipile uninstall --revert`.** `ipile restore` covers files. Nothing
  yet reverses git config keys.
