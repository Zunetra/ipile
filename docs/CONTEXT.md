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

**Last updated:** 2026-09-05

---

## The module contract

Every file in `lib/modules/` implements the same four functions, and
nothing else is a module.

| Function   | Contract                                                                                                              |
| ---------- | --------------------------------------------------------------------------------------------------------------------- |
| `describe` | One line for the menu and for `ipile status`. No side effects.                                                        |
| `detect`   | Reports `installed`, `partial`, or `absent` by looking at the machine. **Must not write anything**, including caches. |
| `apply`    | Does the work. Honours `IPILE_DRY_RUN`.                                                                               |
| `verify`   | Proves `apply` worked. `ipile doctor` calls this same function, so a check written once serves both.                  |

**`detect` writing to disk is a real bug, not a theoretical one.**
`rustup component list` creates `~/.rustup` as a side effect, which broke
the dry-run guarantee below until it was guarded.

**`MODULE_NEEDS` declares dependencies, and the runner resolves them
transitively before anything runs.** A satisfied dependency is reported
and skipped, not re-run.

| Module                                                                 | Needs         |
| ---------------------------------------------------------------------- | ------------- |
| `git-identity`, `git-accounts`, `git-hooks`, `git-globals`, `dotfiles` | `git-install` |
| `pkgmanagers`, `guard`                                                 | `node`        |

**A failed module does not abort the run, but it does reach the caller.**
The runner reports the failure and continues, so one broken step cannot
cost the user the other nine, and `bin/ipile` then exits `1` because
`run --yes` is documented as the CI path. Two exceptions: a dry run
always exits `0` since it changed nothing, and `doctor` always exits `0`
because it reports rather than gates and must be readable under `set -e`.
The status is captured immediately after the dispatch `case`, since the
update notice that follows would otherwise discard it.

`dotfiles` is in that list because it sets `core.excludesfile`, which is
a git call like any other. Without the declaration, `ipile git accounts`
on a machine with no git walked the user through generating a key and
registering it on GitHub, then died on the first `git config`. That is
the worst possible place to fail.

---

## Version pins live in the manifest

**Every version this tool installs is declared in `lib/manifest.sh` and
nowhere else.** A module that hardcodes a version is a bug, even when the
constant is named and sits at the top of the file. The question "what
will this put on my machine" has to be answerable by reading one file,
not by grepping ten.

`IPILE_NODE_VERSION` and `IPILE_NVM_VERSION` were constants at the top of
`node.sh` before this. That was tidy and still wrong: the answer lived in
the same place as the logic that consumed it, so it was findable only by
someone who already knew where to look.

**Node is pinned to the latest LTS major, never the newest release.**
Even-numbered majors only become LTS in the October after they ship, so
"latest" and "latest LTS" are different answers for half the year. A
machine bootstrap is the wrong place to run a Current release.

**Things with no hard pin are still declared.** `pnpm`, `yarn` and the
Rust toolchain resolve to `latest`, `stable` and `stable`, and Corepack's
shims are overridden per project by `packageManager` anyway. They are
named in the manifest regardless, because a manifest that answers half
the question sends people straight back to grepping the modules.

**Anything that sources modules must source the manifest first.**
`MODULE_DESC` is expanded at source time, so a caller that skips the
manifest gets `nvm plus Node  as the default` with a hole in it.
`doctor.sh` calls `registry_load` and shipped exactly that bug for the
length of one commit.

---

## Input validation

**Predicates are pure and live in `lib/core/validate.sh`. Prompting
lives in `ui.sh`.** Nothing in `validate.sh` reads stdin or writes to the
terminal, which is what keeps it callable from `doctor.sh` and from a
test with no tty attached. Every predicate returns 0 or 1 and prints
nothing; every message the user sees is printed by the caller.

**Validate the shape, not the vendor.** Email is checked for structure
and any domain passes. A `@gmail.com` allowlist would reject the work
address that is the entire reason a multi-account tool exists.

**Normalise before rejecting.** The username prompt asks for a handle,
but a profile URL is what sits on the clipboard, so
`gh_normalize_username` reduces every form of
`https://www.github.com/user/` to `user` instead of erroring. A hard
"must start with https://github.com/" rule would have turned the common
case, typing a bare handle, into a failure.

**Shape and plausibility are separate questions.** `valid_host` accepts
single-label hosts, so `gitbub` passes the shape check and is caught by
`forge_suggest` instead, which offers `github.com` at Levenshtein
distance 1. Rejecting it at the shape check produces "enter a hostname"
when what the user needs is "did you mean github.com?". The comparison
runs on the label before the first dot: `gitbub` to `github.com` is
distance 5, to `github` it is 1.

**An unknown host warns and confirms, it never rewrites.** The four
recognised forges are `github.com`, `gitlab.com`, `bitbucket.org` and
`codeberg.org`. Anything else gets the suggestion if one is close, then a
confirm that defaults to **no**, so a fat-fingered host is not waved
through by someone hitting Enter on autopilot. Under `IPILE_ASSUME_YES`
the suggestion is deliberately not applied: silently changing a value
nobody can see being changed is worse than an odd host.

**Validate the default too, under `IPILE_ASSUME_YES`.** Otherwise `--yes`
becomes the supported route to writing garbage into `~/.gitconfig-*`
while the interactive path refuses it.

**Never validate a default that is already on disk.** The alias rename
prompt in `git-accounts.sh` says "press Enter to keep it", so validating
its default would trap anyone holding a legacy alias in a loop with no
way out. The new value is validated after the fact instead, and a bad one
abandons the rename rather than blocking the prompt.

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

The same bug reappeared the moment a new eval-assigning helper was added.
`ui_ask_host` passed `__ui_value` to `ui_ask_valid`, which declares a
local of exactly that name, so the `eval` wrote the callee's local and
the caller read back an empty host. Prefixing is not enough on its own:
each helper in a chain needs a _distinct_ prefix, because the collision
is now between two helpers rather than between a helper and its caller.

**A failed `read` is EOF, not an empty answer.** `ui_ask` and
`ui_confirm` both looped on "this field is required" without checking the
return, so the moment stdin closed they spun forever. A piped or
backgrounded run produced 1.9MB of output in 120 seconds. Every prompt
loop now returns 1 on a failed read. This is the same class of bug as
`pre-commit` hanging on a closed stdin, and it will keep recurring
wherever a loop treats "no input" and "no more input" as the same thing.

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

**The author is set at commit time, the key at push time. They are not
the same decision.** A repository has one `user.email`, so it authors as
one identity no matter how many remotes it has. What a remote's SSH host
alias selects is which _key_ authenticates that push. `gremote` writes
the alias into the remote URL and records the profile in
`remote.<name>.ipileidentity`; `pre-push` compares the authors of the
outgoing commits against that profile and warns. It warns rather than
blocks, because the only fix is a rebase and whether that is worth it is
the user's call. Any future attempt to "set the identity per remote" runs
into this: git stamps the author into the commit object, and changing it
afterwards rewrites every SHA.

**A hook cannot prompt on stdin.** Git runs hooks with stdin closed, so
`read` returns EOF immediately. `pre-commit`'s identity fallback looped
forever on that, hanging any commit from an IDE, a script or a rebase in
a repo with no detected identity. Prompting now requires opening
`/dev/tty` in a test first, because the device can exist and still refuse
to open, and a failed `exec` redirect prints its own error before it can
be suppressed. `pre-push` is the other trap: it receives its ref list on
stdin, so a hook that reads it must replay it to the repo-local hook
rather than `exec`ing and expecting an unread stream to be inherited.

**Host is a per-profile field, never hardcoded.** Someone will be on
GitLab, Bitbucket, Gitea, or a self-hosted enterprise instance. This is
also why `gclone` rewrites URLs per the profile's own host: supporting
GitLab profiles while rewriting only `github.com` meant a profile could
be created and then never used.

---

## Hooks: `core.hooksPath` is a single slot, not a stack

`core.hooksPath` does not accumulate. A repository-local value **replaces**
the global one rather than running after it, so in a repo that sets its own,
ipile's hooks are never executed at all.

This is what husky does. `husky init` writes `core.hooksPath = .husky/_` into
the repo's local config, and from that moment the global identity hook is
skipped there. Nothing errors. Commits keep working, they just stop prompting
for an identity, which is the worst shape a failure can take.

Two halves, and only the first is ipile's to solve:

**Chaining down, which the shipped hooks do.** When ipile's hook does run, it
looks for the repository's own hook in `<git-dir>/hooks/<name>` **and** in
`.husky/<name>`. The second was added because husky keeps its scripts outside
`.git/hooks`, so a fresh clone with `.husky/` committed but its install not
yet run would silently skip the repo's checks. The passthrough hooks check
both too, with two path stats rather than a fork, keeping the cost the
generated hooks were designed around.

**Chaining up, which the repository has to do.** Once a local `hooksPath` is
set, no amount of cleverness in the global hook helps, because the global
hook is the thing being bypassed. The repo's own hook must call ipile's on
the way in:

```bash
# .husky/pre-commit
G="$(git config --global --get core.hooksPath || true)"
[ -n "$G" ] && [ -x "$G/pre-commit" ] && "$G/pre-commit" "$@"
```

`pre-push` needs one extra step. It receives its ref list on stdin and that
stream can only be read once, so read it up front and replay it, rather than
handing an already-consumed stream to the next hook:

```bash
# .husky/pre-push
REFS="$(cat)"
G="$(git config --global --get core.hooksPath || true)"
if [ -n "$G" ] && [ -x "$G/pre-push" ]; then
  printf '%s\n' "$REFS" | "$G/pre-push" "$@" || exit $?
fi
# ... and use "$REFS" for this repo's own checks too
```

`ipile doctor` detects the shadowing and prints this, because a problem that
cannot be fixed from the global side should at least stop being invisible.

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

## Guard: the scanner never cleans on its own

`lib/modules/guard.sh` installs `lib/assets/bin/dev-guard`, the backdoor
scanner and cleaner. The full incident writeup, performance numbers, and
the reasoning behind every check live in `reference/README.md` and are
not repeated here.

**A finding is never cleaned automatically, not even under `--yes`.**
`apply` runs the scan as part of the module like anything else, but
cleaning is a separate confirm every time, because `--yes` means "don't
ask about running the scan," not "don't ask before rewriting files
across a dozen repos." A non-interactive run that finds something reports
it and points at `dev-guard --clean --yes`, and leaves it there.

**`detect` reads unit files and `~/.npmrc`, never the scanner.** Running
`dev-guard --all` from `detect` would make `ipile status` re-walk every
project on the machine on every render. Whether the daily timer is
enabled is read from the `timers.target.wants` symlink systemd itself
creates, same reasoning as the `rustup`/`systemctl` trap above: the first
call to a user bus can start a session manager, so unit state is read off
disk, never asked of `systemctl`.

**The daily timer is opt-in and systemd-only.** Enabling a background job
is a real side effect and gets its own confirm inside `apply`, separate
from the confirm to install the module at all. On darwin it is not
offered; `describe` says so rather than the module carrying a launchd
implementation nobody has tested. The timer's `ExecStart` scans the
default `~/Projects`, not whatever the user gave `projects_root` -- the
unit is a static asset compared byte for byte in `detect`, so a
per-machine path cannot be templated into it without breaking that check.
`cleanup`, below, needed a per-machine path in its unit and solved it
differently.

**`projects_root` is shared state, not a `guard`-only setting.** It lives
in `lib/core/projects.sh`, asked once by whichever of `guard` or
`cleanup` needs it first, and stored under a name neither module
namespaces to itself. Two modules asking the same question twice, or
worse landing on different answers, is its own bug.

---

## Cleanup: generated units, not shipped ones

`lib/modules/cleanup.sh` installs `lib/assets/bin/dev-cleanup` the same
way `guard` installs its scanner, but its systemd units are not shipped
assets. `guard`'s timer always scans the same fixed path, so its unit
can be a static file `detect` compares byte for byte. `cleanup`'s unit
has to bake in whatever age threshold, interval, and projects root the
user chose, so `lib/modules/cleanup.sh` generates the unit text itself
from state, in `cleanup_service_content`/`cleanup_timer_content`.
`detect` calls the same functions to regenerate the expected text and
diffs it against what's on disk -- still read-only, still no `systemctl`
call, just comparing two strings instead of two files.

**Manual and automatic are a real fork, not a flag.** `apply` asks the
mode before anything else. Manual mode installs the script and runs it
once; automatic additionally writes and enables the timer. Switching
modes on a later run is how you change your mind: auto to manual tears
the units down (`cleanup_disable_timer`) rather than leaving a timer
nothing points at, and manual to auto installs them.

**The age threshold is asked every run, but only ever answered once.**
`ui_ask_int`'s default comes from `state_get cleanup_age`, not a literal
30, so a saved answer becomes next run's default and `--yes` (which
takes a prompt's default without asking, by `ui_ask_int`'s own existing
contract) silently reuses it. No special-casing lives in `cleanup.sh`
for this -- it falls out of feeding a stateful default into a helper
that already had this behaviour.

**Deleting always needs a separate confirm, even under `--yes`, exactly
like `guard`'s clean step.** `--yes` skips being asked whether to run
the sweep, not whether to act on what it found. The one deliberate
exception is the _scheduled_ invocation: the unit's `ExecStart` already
carries `--yes` to `dev-cleanup`, because enabling the timer in the first
place was the confirmation, given once, for every run it will ever make
unattended.

**Automatic mode's scheduler install is gated on connectivity, not
assumed.** Enabling the timer itself needs no network, but a machine
missing `systemctl`/`loginctl` needs a package installed to get them,
and that install needs one. `cleanup_apply_auto` checks
`curl -s --head --connect-timeout 5 https://github.com` (same check
`preflight` already runs) before calling `os_pm_install`, and if either
the connection or the scheduler still isn't there afterward, falls back
to running once and says so, rather than failing the module outright.

---

## Not done

- **Distribution.** Only the shell installer exists. npm, the Homebrew
  tap, and the crates.io wrapper are unbuilt. See
  [handbook 0004](../../handbook/decisions/0004-distribution-channels.md).
- **Hosting.** Install and update both verify SHA256, but nothing
  publishes a `SHA256SUMS` at the URL yet, so both warn and continue
  rather than protecting anyone. Until `version.txt` v4.0 is published,
  every command also prints a spurious update notice.
- **`ipile uninstall --revert`.** `ipile restore` covers files. Nothing
  yet reverses git config keys.
