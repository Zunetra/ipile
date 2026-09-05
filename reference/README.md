# Reference

**Both tools that used to live here have shipped as ipile modules**:
`dev-guard` as `ipile guard` (`lib/modules/guard.sh`), `dev-cleanup` as
`ipile cleanup` (`lib/modules/cleanup.sh`). Their source lives once, at
`lib/assets/bin/dev-guard` and `lib/assets/bin/dev-cleanup`, and each
module installs its script to `~/.local/bin/` -- there is nothing left
here to mirror by hand, and no copy to resync.

What remains below is the writeup that does not belong in either
module's own comments: the incident that made `dev-guard` necessary, the
performance numbers behind how it is built, and the hardening guidance
that goes beyond what either tool automates. It is still accurate for
both tools; only the installation path changed. The `## Turning this
into an ipile module` sketch that used to close this file is gone now
that both are.

---

## The incident

A backdoor was found appended to build config files across our repositories
in 2026. It gave an attacker command execution on developer machines. It has
been removed from `main` and `develop`.

**Nobody committed it knowingly, and that is the important part.** The
malware wrote the file itself, `git add .` staged it, and it was committed
unreviewed because of how it hides. Any mitigation that depends on a human
noticing it in a diff is already defeated.

It spreads mainly by git. You pull a teammate's infected config, you build,
it runs, it writes itself into your configs. It does not touch every project
on a machine: on the machine where it was found, four projects across three
organisations were hit while a project actively developed alongside them was
never touched.

Suspected entry vector is a compromised npm package around late April or
early May 2026, still unconfirmed. That is why the `--supply` checks exist
and why they matter on a machine that scans clean.

### What it looks like

Two forms, and a check that matches one and not the other is worse than
useless because it will be trusted.

**Minified**, pushed far right behind roughly 700 spaces so it sits off the
edge of the screen. Look at the last line and press `End`:

```js
module.exports = { mode: 'production' };
const x = 1;                        [~700 spaces]                        global.o='7-c1287';require("http")...
```

**Reformatted by Prettier**, which turns it into ordinary looking
multi-line JavaScript with mangled names like `_$_3035`, `zkC`, `dgk`:

```js
module.exports = { reactStrictMode: true };
global.o = "7-c1287";
const _$_3035 = require("http");
```

Note the spacing difference: `global.o='7-` in one, `global.o = '7-` in the
other. Every pattern in this repository matches both. If you write your own,
match both.

In `.mjs` files it also injects a CommonJS shim at the very top, so it can
`require()` inside an ES module:

```js
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
```

### Hits that do not mean you are infected

The signature appears in places where it is a record of the code, never
something that runs. `dev-guard` filters these out. They are all harmless:

| Location                                    | What it is                                       |
| ------------------------------------------- | ------------------------------------------------ |
| `~/.claude*/projects/*.jsonl`               | AI assistant transcripts discussing the incident |
| `~/.claude*/paste-cache/`                   | The incident memo, pasted into a session         |
| `Code/User/History/`                        | Editor local file history                        |
| `docs/security/*.md`, `reference/README.md` | Our own write-ups, which quote it on purpose     |
| Browser cache, chat app databases           | Pages and messages showing the diff              |

Only a `.js`, `.cjs`, `.mjs` or `.ts` file inside a project is something a
build will load and execute.

---

## dev-guard

```
dev-guard [checks] [scope] [options]
```

Run `dev-guard --help` for the full text. Scanning never modifies a file.
Cleaning is a separate flag and is dry run until you pass `--yes`.

### Checks

| Flag           | What it catches                                                                                                                             | What it does not                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `--scan`       | The known payload signature, both spacings.                                                                                                 | Any variant that renames `global.o`.                                        |
| `--heuristics` | Padded lines, a `global.<letter>` assignment at end of file, the injected `createRequire` preamble in `.mjs`, obfuscated `_$_` identifiers. | Anything that avoids all four shapes. Reports possibilities, not proof.     |
| `--procs`      | Running `node -e` / `node --eval` processes.                                                                                                | Anything already exited, or disguised as a normal node process.             |
| `--branches`   | Checked out branches that do not yet contain their `origin` base.                                                                           | Branches not checked out. Only the current branch of each repo is examined. |
| `--supply`     | Plaintext auth tokens in `.npmrc`, missing `minimum-release-age`, projects that let any dependency run install scripts.                     | Whether a specific installed package is malicious.                          |
| `--clean`      | Strips the payload, `.bak` first, then rescans to prove the result.                                                                         | Anything the two scans did not find.                                        |
| `--all`        | Every check above except `--clean`.                                                                                                         |                                                                             |

### Scope

| Flag          | Reads                                  | Cost                     |
| ------------- | -------------------------------------- | ------------------------ |
| default       | `~/Projects`, or `--path DIR`          | ~5s over 2659 files      |
| `--staged`    | The git index, not the working tree    | ~0.36s for 21 files      |
| `--since REF` | Files changed between `REF` and `HEAD` | proportional to the diff |

`--staged` reads the **index**, which matters more than it sounds. A file
you clean after `git add` still commits the bad blob. Scanning the working
tree would call that clean. Verified: a payload staged and then removed from
the working tree is still caught.

`--since ORIG_HEAD` after a merge is what a pull brought in.

### Exit status

`0` nothing found, `1` findings or an unverified clean, `2` bad usage.
Suitable for gating a script.

### Cleaning

```bash
dev-guard --clean              # show what would be stripped
dev-guard --clean --yes        # strip it, keeping .bak next to each file
```

It removes everything from the `global.o` marker to end of file, removes the
injected `.mjs` preamble, restores the trailing newline that stripping takes
with it, and then rescans. **A clean that does not verify is worse than
none, because it is believed**, so the rescan is not optional.

`--clean` refuses to run against `--staged`, because staged blobs are read
into scratch space and cleaning them would edit a copy. Clean the working
tree, then `git add` the result.

Afterwards, in each affected project:

```bash
rm -rf node_modules
pnpm store prune
pnpm install --frozen-lockfile
```

**Do not delete the lockfile.** No malicious package has been found in our
dependencies. Deleting it unpins every package and pulls newer versions,
which adds risk rather than removing it, and it has already broken our
Docker builds once when pnpm 11 shipped.

---

## Performance, and why it is written this way

These numbers are on this machine, 2659 candidate files under `~/Projects`,
warm cache. They are here because the question "is this too slow to run
automatically" deserves a measurement rather than a guess.

| Approach                                       | Time              |
| ---------------------------------------------- | ----------------- |
| One `grep` process per file                    | 12.1s             |
| Batched through `xargs`                        | 1.0s for `--scan` |
| `--scan --heuristics`, naive `{200,}` regex    | 15.2s             |
| `--scan --heuristics`, with literal prefilters | 5.1s              |
| `--staged`, 21 files                           | 0.36s             |
| `scripts/supply-chain-check.sh`, 20 files      | 0.18s             |

Two findings worth keeping:

**Fork per file is the dominant cost.** The first version ran one `grep` per
file. Handing the whole list to `grep` through `xargs` is roughly 12x faster
for an identical result.

**A bounded repeat defeats grep's literal fast path.** `[[:space:]]{200,}`
alone costs 11.5s of a 15s run. Prefiltering with `grep -F` on 100 literal
spaces costs 274ms, and the precise regex then runs only on what came back.
100 is half the threshold, so the prefilter cannot miss a real hit. The same
prefilter-then-refine shape is used for the end-of-file check, where
position cannot be expressed to grep at all.

The remaining 5s is five separate passes over file content. That is
acceptable for a daily sweep and is not worth collapsing into one pass.

---

## Making it automatic

Nothing below is installed. Choose deliberately.

### The trap: do not use a machine-global git hook

`core.hooksPath` is all or nothing. A repo-local setting **replaces** the
global one, so a hook installed globally never runs in any repo that sets
its own. husky sets `core.hooksPath` to `.husky/_`. ipile is a husky repo,
and so are most of ours.

A global hook would therefore be silently dead in exactly the repositories
that matter most, while appearing installed. A security control that quietly
does nothing is worse than no control, because you stop looking.

This is also why the check is **not** in ipile's `lib/assets/hooks/pre-commit`,
even though that file exists and would have been the obvious place.

### Layer 1: a daily sweep (recommended, low risk)

Catches everything on disk regardless of git: files a pull brought in,
branches never rebased, config drift, stray processes. It detects rather
than blocks, and daily is the right cadence for that. Costs about 5s.

`ipile guard` asks about this directly -- "Also run a sweep automatically,
once a day?" -- and only installs the timer on a yes. Without ipile, the
same units are still here to install by hand:

```bash
mkdir -p ~/.config/systemd/user
cp lib/assets/systemd/dev-guard.service lib/assets/systemd/dev-guard.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now dev-guard.timer
```

Check on it:

```bash
systemctl --user list-timers dev-guard.timer
systemctl --user status dev-guard.service      # shows "failed" when it found something
journalctl --user -u dev-guard.service -n 50
```

The unit exits `1` on findings on purpose, so an unattended sweep still
registers as failed rather than passing quietly.

To remove it:

```bash
systemctl --user disable --now dev-guard.timer
rm ~/.config/systemd/user/dev-guard.{service,timer}
systemctl --user daemon-reload
```

### Layer 2: block the commit (recommended, but roll out deliberately)

This is the layer with real value, because it stops the bad commit rather
than reporting it afterwards. It goes in `.lintstagedrc`, which means:

- it is **committed**, so it protects every teammate, not only machines that
  ran an installer
- husky invokes it, so it **survives a husky reinstall** instead of being
  overwritten
- it is self-contained and does not require `dev-guard` on the machine
- it runs on staged files only, about 0.18s

Already wired into this repo:

```json
"*.{js,cjs,mjs,ts}": ["scripts/supply-chain-check.sh"]
```

To add it to another repo, copy `scripts/supply-chain-check.sh` and add that
one line to its `.lintstagedrc`. For a repo with no lint-staged, the same
script works as a plain `.husky/pre-commit` line:

```sh
git diff --cached --name-only --diff-filter=ACM | xargs -r scripts/supply-chain-check.sh
```

The only expected false positive is genuine minified vendor code committed
on purpose. `git commit --no-verify` overrides once.

### Layer 3: after a pull (optional)

`--since` exists for this, but a `post-merge` hook has the same
`core.hooksPath` problem as any other hook. Running it by hand after pulling
something you did not write is enough:

```bash
dev-guard --scan --heuristics --since ORIG_HEAD
```

---

## Hardening the entry vector

Detection is downstream of the actual problem. These reduce the chance of a
compromised package executing at all. **None of these are applied.**

### 1. Do not let a fresh publish reach you immediately

A compromised version is typically pulled within hours of publish and yanked
within a day or two. Waiting the release out costs almost nothing.

```ini
# ~/.npmrc
minimum-release-age=1440
```

1440 minutes is 24 hours. The tradeoff is real and worth stating: it will
occasionally delay a legitimate urgent patch, and you will have to override
it knowingly when that happens.

### 2. Do not let arbitrary packages run install scripts

An install script is the most likely way a bad package first executes. pnpm
10 and later block them by default and take an explicit allowlist. Name only
what genuinely needs to build:

```json
{
  "pnpm": {
    "onlyBuiltDependencies": ["esbuild", "sharp"]
  }
}
```

`dev-guard --supply` reports which projects have no allowlist.

### 3. Do not keep a plaintext token on disk

```ini
# ~/.npmrc  <- this is the problem
//registry.npmjs.org/:_authToken=npm_xxxxxxxxxxxx
```

Anything running as your user can read that, including a build script. That
is precisely the access this backdoor had.

**Revoke it at npmjs.com first, then remove the line.** Deleting it locally
before revoking breaks your installs without closing the exposure. Use
`npm login` per session, or a granular read-only token.

### 4. Rotate credentials even when the scan is clean

A clean scan means your files are clean now. It does not mean nothing ever
ran. Rotate GitHub PATs, SSH keys (generate new, remove old from GitHub),
npm tokens, cloud CLI logins (`doctl`, `aws`, `gcloud`), and anything in
local `.env` files. Run a full endpoint scan.

### 5. Rebase before building on an old branch

`main` and `develop` are clean; feature branches are not.

```bash
git fetch origin
git rebase origin/develop
```

`dev-guard --branches` lists the ones that need it.
