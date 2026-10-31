---
name: rebase-ge
description: Rebase Proton-JE-GE onto the newest GE-Proton release, check, build and test the Proton-JE patches on it locally, tag it so GitHub Actions builds and publishes the release, then verify the release and install it as "Proton-JE-GE Latest". Use when GloriousEggroll publishes a new GE-Proton, or when asked to update, rebase, re-tag, rebuild or install a new Proton-JE-GE release.
---

# A new Proton-JE-GE release on a new GE-Proton

Layout: `~/repos/proton-je-ge` is proton-je/proton-je-ge, a GitHub fork of GloriousEggroll/proton-ge-custom under an
org, because GitHub allows one fork per owner in a fork network and jegglest/proton-je is already in this one. Remotes:
`origin` = proton-je/proton-je-ge over SSH, `ge` = GloriousEggroll/proton-ge-custom. The clone has two remotes, so every
`gh` command names `-R proton-je/proton-je-ge` or `-R GloriousEggroll/proton-ge-custom`. Of the submodules, only
`wine` (ValveSoftware/wine; remote `je` = jegglest/wine) and `wine-staging` are initialized. Both are full clones, never
shallow or partial.

The branch is `je-ge-<GE major>`: now `je-ge-11`, the repository's default branch. It is a GE release tag plus these
commits, in this order (subjects as on the branch):

1. `patches: add Proton-JE's RtlWaitOnAddress() stale alert fix`: Proton-JE's patches 2 and 3.
2. `patches: add Proton-JE's ntsync mutex abandonment fixes`: patches 4 to 6.
3. `patches: take Valve's RtlpUnWaitCriticalSection() fix early`: Paul Gofman's `d5c4b850198` from Valve's Wine (the
   Helldivers 2 crash), only until the Wine that GE points at has it.
4. `patches: add Proton-JE's fix for the stacks of killed threads`: patches 7 and 8 (Helldivers 2's memory growth),
   patch 7 in the version GE merged (below).
5. `ci: fix release.yml's Create Release step`: GE's own release workflow is broken since GE's 961d412f. This commit is
   written so GE could take it as is, and it goes away once GE fixes the same lines.
6. `ci: build proton-je-ge-* tags, check the Proton-JE patches`.
7. `README: describe Proton-JE-GE`: a section above GE's README, which stays unchanged.
8. `Add install-latest.sh: the newest release as "Proton-JE-GE Latest"`.
9. `Skills: rebase-ge and mark-latest`: this directory and `../mark-latest/`.

Pull requests to GE, opened 2026-11-01 from the fork's `ge-pr/*` branches with the same patch files under the same
names. GE took them by hand on 2026-11-02: GitHub shows them closed, not merged, and the commits are on GE's master
under our authorship.
- #911, commit 5's release.yml fix: taken as is (`dd5799ce`), plus GE's own `167f19de` for the upload job.
- #912, patches 2 and 3 (replacing GE's older copy of patch 2), and #913, patches 4 to 6: taken as is.
- #917, patches 7 and 8 (killed threads' stacks): taken with GE's change to patch 7 (`ecf1beff`):
  `free_killed_threads()` uses `pthread_tryjoin_np()` and leaves a killed thread that has not finished exiting for a
  later pass, instead of waiting for it. Commit 4 carries GE's file, byte for byte, since 2026-11-02.
- #914, the Helldivers 2 backport: closed as superseded. GE moved its Wine to `fda79a58`, which has `d5c4b850198`.

Their `ge-pr/*` branches were deleted on 2026-11-02. Every patch file of our section is now the file on GE's master,
same name and same content, but GE-Proton11-11 has none of them: they stay in our section until the GE release we
rebase onto has them (step 2, "A patch file of ours that GE also carries"). If no patch is left in our section then,
`check-proton-je-patches.sh` fails by design: ask the user what Proton-JE-GE should carry.

A new pull request to GE goes from a branch `ge-pr/<name>` on the fork: GE's master plus the one change, with the
patch file under the same name as ours. GE's master has a valid `release.yml` since #911, so pushing such a branch
starts no run. If GE asks for changes, update the branch, check it the way step 3 does on GE's master, and push it
with a lease. Once GE merges or closes the PR, delete the branch: `git push origin --delete ge-pr/<name>` and
`git branch -D ge-pr/<name>`. Never while the PR is open: GitHub closes a PR whose head branch is deleted.

The Wine patches are GE-style patch files in `patches/wine-hotfixes/pending/`. The `### PROTON-JE PATCHES ###` section
of `patches/protonprep-valve-staging.sh` applies them after all of GE's patches, just before
`echo "WINE: RUN AUTOCONF TOOLS/MAKE_REQUESTS"`. Each file is the `git format-patch --zero-commit --no-signature -N`
output of a commit on a scratch branch in the wine submodule, renamed to a fixed name with no number. The scratch branch
is GE's patched tree, committed, plus our commits. The exception is patch 7,
`ntdll-free-teb-and-stacks-of-killed-threads.patch`: it is GE's file as GE merged it, a plain diff without `git`
headers, which `patch`, `git apply` and `git am` all take.

CI: `.github/workflows/release.yml` runs for every pushed `proton-je-ge-*` tag (and for GE's `GE-Proton*-*` tags):
- **Build** (`_job_build.yml`): GE's patching (`|| true`), then `.github/check-proton-je-patches.sh`, then
  `configure.sh` and `make redist`. It takes about 2 h 35 min every time: the build runs in docker without ccache, so
  the cache step never helps.
- **Release**: creates the release from the tag's message (`--notes-from-tag`) and marks it Latest.
- **Upload**: attaches `<tag>.tar.gz` and `<tag>.sha512sum`.

Rules:
- Do the steps in order. Every push goes to the public fork. When a step fails, stop and report rather than improvise.
- Nothing with personal data (play time, schedules) goes into docs, commit messages or tag messages.
- Never move a tag that has a release.
- CI creates and publishes every release. Never create, publish or upload one by hand: when CI cannot do it, the
  workflow gets fixed and the tag goes through CI. Release `proton-je-ge-11-11-1` was the one exception, accepted on
  the condition that the next build is published by CI.

Use a scratch directory as `$work`, e.g. `<scratchpad>/je-ge-<new GE tag>`. Releases are about 550 MB each, and the
Wine build tree is about 700 MB.

## 1. Find the new base

```bash
cd ~/repos/proton-je-ge && git fetch ge --tags && git fetch origin
br=je-ge-11; K=.claude/skills/rebase-ge; work=<scratch dir>; mkdir -p $work
old_ge=$(git describe --tags --abbrev=0 --match 'GE-Proton*' $br)
new_ge=$(git tag -l 'GE-Proton*' --sort=-v:refname | head -1)
git log --oneline $old_ge..$new_ge
git ls-tree $old_ge wine; git ls-tree $new_ge wine          # the Wine that GE points at, before and after
gh release view $new_ge -R GloriousEggroll/proton-ge-custom --json assets --jq '.assets[].name'
```

- **No release assets yet:** GE builds and uploads by hand, sometimes after pushing the tag. Wait for
  `$new_ge-x86_64.tar.gz`, which step 3 needs.
- **Same tag as before:** there is nothing to rebase. A rebuild on the same base is only a new tag, `-<n+1>` (step 5).
- **A new major (`GE-Proton12-1`):** start `je-ge-12` from it with the same commits, the same way. Making it the
  default branch is a repository setting: ask the user.

Look before rebasing:

```bash
git diff --stat $old_ge $new_ge -- patches/protonprep-valve-staging.sh .github README.md
# Does GE now apply one of our patch files itself, or carry the same change under another name?
for f in $(sed -n '/^### PROTON-JE PATCHES ###$/,/^### END PROTON-JE PATCHES ###$/p' patches/protonprep-valve-staging.sh |
           grep -o 'pending/[^"]*'); do
  echo "== $f"; git grep -n -F "$f" $new_ge -- patches/protonprep-valve-staging.sh
  git grep -l -F "$(sed -n 's/^Subject: \[PATCH\] //p' patches/wine-hotfixes/$f)" $new_ge -- patches/
done
# Does GE's Wine have Valve's Helldivers 2 fix now? (commit 3)
new_wine=$(git ls-tree $new_ge wine | awk '{print $3}')
git -C wine cat-file -e $new_wine^{commit} 2>/dev/null || git -C wine fetch origin $new_wine
git -C wine log -1 --oneline -F --grep='Ignore semaphore errors in RtlpUnWaitCriticalSection' $new_wine   # empty: not yet
# Does GE's release.yml have the fix? (commit 5; GE's master since 2026-11-02, #911: "      - name: Create Release")
git show $new_ge:.github/workflows/release.yml | sed -n '/name: Create Release/,/fi$/p'
```

## 2. Rebase

```bash
old_head=$(git rev-parse $br)
git rebase --onto $new_ge $old_ge $br
```

Resolving conflicts:

- **`patches/protonprep-valve-staging.sh`:** keep GE's new lines and our section. Ours stays the last thing before
  `echo "WINE: RUN AUTOCONF TOOLS/MAKE_REQUESTS"`.
- **A patch file of ours that GE also carries under the same name:** expected for all of them at the first rebase
  onto a GE release with the merged PRs (above). GE's version wins. While the two files are the same, the rebase
  merges them without a conflict and leaves the file applied twice, by GE's `apply_patch` line and by ours (next
  item). If GE's release has a different copy, keep GE's (`git checkout --ours -- <file>`; in a rebase, "ours" is the
  new base) and drop ours the same way. Never put an older copy of ours back over GE's, such as patch 7 without GE's
  `pthread_tryjoin_np()` change.
- **A change that applies twice:** GE applies one of our patch files itself, or carries the same change under another
  name, or the new Wine has it (Valve's own commit, or the Helldivers 2 fix arriving). Step 3 shows it as "Reversed
  (or previously applied)". Check that it is the same change, then drop ours:
  - a whole commit (commit 3, when GE's Wine has `d5c4b850198`): `git rebase --onto <commit>^ <commit> $br`;
  - one file of a commit: delete its `apply_patch` line in that commit, and the file too unless GE carries it under
    the same name, which makes the file GE's (fixup, below).

  Then take the patch out of the README table and the release notes (steps 4 and 5).
- **`.github/workflows/*`:** keep GE's changes and ours. Commit 5 shrinks as GE fixes the same lines, and it disappears
  once GE's file works: valid YAML, and no `--repo` next to `--notes-from-tag` on `gh release create`, which gh refuses.
  GE's master has that exact fix since #911, so at the rebase onto the GE release with it, git skips commit 5 as
  already applied; that release also brings GE's upload job without `--clobber` (`167f19de`). If the rebase stops on
  commit 5 with nothing left, use `git rebase --skip`.
- **`README.md`:** our section stays on top. GE's README stays unchanged below the `---` line.

To change a commit after the rebase: make the change, `git commit --fixup=<commit>`, then
`git rebase --autosquash $new_ge`. Git 2.44 and later does this without `-i`, which this environment cannot run.

Verify: `git rev-list --count $new_ge..$br` is 9, less any commit dropped. In
`git range-diff $old_ge..$old_head $new_ge..$br`, every commit is `=`, except the ones resolved above.

## 3. Check, build and test locally

GE's Wine patching runs locally in seconds. The CI build takes 2.5 hours, so everything that can fail before it is
checked here first:

```bash
gh release download $new_ge -R GloriousEggroll/proton-ge-custom -p "$new_ge-x86_64.*" -D $work
(cd $work && sha512sum -c $new_ge-x86_64.sha512sum && tar -xzf $new_ge-x86_64.tar.gz)
$K/wine-prep.sh $work                       # GE's patching in podman, our section's output, the strict check
$K/build-wine.sh $work $work/$new_ge-x86_64 # ntdll, wineserver, tests, probes; $work/swapped = stock + ours
$K/run-tests.sh $work/$new_ge-x86_64 $work stock
$K/run-tests.sh $work/swapped $work swapped
git -C wine reset -q --hard && git -C wine clean -qxdf
```

`wine-prep.sh` fails when a patch of our section printed `FAILED`, fuzz or "previously applied", or when
`check-proton-je-patches.sh` fails (the same check as CI). Offsets ("Hunk #1 succeeded at 1234 (offset 5 lines)") are
fine. The podman image `je-wine-build` is built from `Containerfile` if it is missing.

Expected with the swapped build, in 64- and 32-bit:
- `ntdll:sync` and `kernel32:sync`: 0 failures. These include the tests from patches 3 and 6.
- `kernel32:thread`: 0 failures, with patch 8's test.
- `mutex_abandon close` and `waitall`: "0 failed step(s)".
- `inproc_cache`: "OK".
- `raced_wake`: "0 stale alerts, 0 early returns".
- `cs_leave`: "LeaveCriticalSection() returned" in all three cases.
- `killed_thread_stacks`: `kill` and `suspended` leave a few allocations at most for their 200 threads; `exit` none.

Stock GE-Proton11-11 failed in all of these except inproc_cache (4 and 3 test failures, 6 failed mutex steps, stale
alerts, and a raise in cs_leave), and stock is the comparison for the README. `kernel32:thread` and
`killed_thread_stacks` came with patches 7 and 8 (2026-11-01): release `proton-je-ge-11-11-1`, without them, failed
patch 8's 2 checks and kept 2 allocations per killed thread in 64-bit, 3 in 32-bit. Any failure on the swapped build stops the
release.

### Refreshing a patch that no longer applies

This happened with patch 5 on GE-Proton11-11: its `protocol.def` requests have to follow GE's wineland `hwnd_dmabuf_*`
requests. Port the patch the way the upstream submission would, on GE's patched tree:

```bash
$K/wine-prep.sh --ge-only $work             # GE's patching without our section, left in wine/
cd wine
git switch -c scratch/$new_ge-patched && git add -A && git commit -qm "$new_ge protonprep result (scratch)"
git switch -c scratch/$new_ge-je
git am -3 $(sed -n '/^### PROTON-JE PATCHES ###$/,/^### END PROTON-JE PATCHES ###$/p' \
    ../patches/protonprep-valve-staging.sh | grep -o '\.\./patches/[^"]*')
# on a conflict: resolve, git add, git am --continue (keep the message and any attribution line)
git format-patch --zero-commit --no-signature -N -o $work/fp scratch/$new_ge-patched..scratch/$new_ge-je
cd ..
```

The files in `$work/fp` come in section order: `0001` is the first `apply_patch`. Copy back only the refreshed ones,
under their existing names, and fix them up into the commit that added them. Then run step 3 from the top: `wine-prep.sh`
resets the submodule to the branch's gitlink and leaves the scratch branches alone.

## 4. Docs

Commit the doc changes as a fixup of the README commit (7), then autosquash (step 2):

- `README.md`, the `Base` row: the GE tag and its release link, and the Wine commit with its link (`$new_wine`).
- The "Checked on" paragraph: the date, the GE release, the stock failure counts from step 3, and what the swapped build
  passed.
- The "What is added" table, if a patch was dropped or changed, and the "Eight Wine patches" count.

## 5. Push, tag, build

```bash
git push --force-with-lease=$br:$old_head origin $br
tag=proton-je-ge-${new_ge#GE-Proton}-1     # GE-Proton11-12 -> proton-je-ge-11-12-1
prev=$(git tag -l 'proton-je-ge-*' --sort=-v:refname | head -1)
git tag -l --format='%(contents)' $prev > $work/tag.txt   # the template; edit it
```

`-<n>` counts builds on the same GE release. The tag message is the release page, in GE's style:
- The first line is the tag name, then a blank line, then Markdown: `# <tag>`, the one-line description, the
  Important note, and `Base:` with the GE release and its Wine commit.
- Then one line on what changed since `$prev`: "Rebased onto GE-ProtonX-Y; the patches are unchanged.", or what
  changed.
- `## Added`, with one bullet per fix still carried.
- `## FSR 4` and `## Installing`, with the new file names.

```bash
git tag -a --cleanup=whitespace -F $work/tag.txt $tag $br    # whitespace: keeps the Markdown "#" lines
git push origin $tag
gh run list -R proton-je/proton-je-ge -w Release -L 1        # the run for the tag
gh run watch <run id> -R proton-je/proton-je-ge --exit-status --interval 300   # in the background
```

The run has to go green on its own: Build, then Release (it creates the release and marks it Latest), then Upload
(both files attached). CI has done all three by itself since `proton-je-ge-11-11-2`. If it fails:

- **Build fails** (Patch, the check, or the compile): no release exists. Fix it on the branch, delete the tag locally
  and on `origin` (`git push origin :refs/tags/$tag`), and tag the same name on the fix.
- **Release fails:** no release exists either. Fix `release.yml` in commit 5, then delete and re-tag as above. The build
  runs again.
- **Upload fails:** the release exists without its files. If the failure was transient,
  `gh run rerun <run id> -R proton-je/proton-je-ge --failed` (the build artifacts are kept). Otherwise stop and report.
  Do not upload by hand, and do not delete the release without the user.

Never publish a release by hand. `gh release edit --draft=false` also fires release.yml's `release: published` trigger,
which starts a second full build, and that build's Upload overwrites (`--clobber`) the files that were verified.

## 6. Verify and install

```bash
d=$work/release && mkdir -p $d && gh release download $tag -R proton-je/proton-je-ge -D $d
(cd $d && sha512sum -c $tag.sha512sum && tar -xzf $tag.tar.gz && cat $tag/version)   # "<epoch> <tag>"
grep -c "\"$tag\"" $d/$tag/compatibilitytool.vdf                                     # 2
$K/run-tests.sh $d/$tag $work release                                              # as the swapped build in step 3
curl -sI https://github.com/proton-je/proton-je-ge/releases/latest | grep -i '^location'   # .../tag/$tag
./install-latest.sh
```

`install-latest.sh` installs the latest release into Steam's `compatibilitytools.d` as one tool named "Proton-JE-GE
Latest", replacing the previous one in place. A second run says it is already installed. If Steam is running
(`pgrep -x steam`), it lists the new build after a restart. Afterwards, remove `$work`.

GitHub marks the new release Latest by itself, and Steam's default and per-game mappings already name `Proton-JE-GE
Latest`, so nothing else moves now. Once the user has run a game on the new release, `/mark-latest` makes it the only
release offered: the older ones become pre-releases.

## Report

- The base before and after: GE tags and Wine commits.
- What changed in our commits: the range-diff, any patch refreshed or dropped, and how each conflict was resolved.
- Step 3's results next to stock.
- The tag, the run id, and how long it took.
- The release's sha512 check, its `version` line, and its test results.
- Where the tool is installed, and whether Steam needs a restart.
