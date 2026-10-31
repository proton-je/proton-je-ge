---
name: mark-latest
description: Make a Proton-JE-GE release that the user has run a game on the one to use. Confirm it is GitHub's latest release, demote the earlier releases to pre-release, make sure Steam's "Proton-JE-GE Latest" tool holds it, and check which tools Steam's mappings name. Run with an older tag, it takes that release back when a newer one breaks a game. Use when asked to make a release the latest, promote it, mark older releases as pre-release, retire or roll back a release, update Proton-JE-GE Latest, or set Steam's default to Proton-JE-GE.
---

# Mark a Proton-JE-GE release as the latest

Argument: the release tag, default the newest one (`gh release list -R proton-je/proton-je-ge --limit 1`). The clone
has two remotes, so every `gh` command names `-R proton-je/proton-je-ge`.

`/rebase-ge` builds, verifies and installs a release: CI's Release job marks it Latest on GitHub, and `install-latest.sh`
puts it straight into Steam's `Proton-JE-GE Latest` tool. This skill comes after the user has run a game on it: the
earlier releases become pre-releases, so the releases page offers only the tried one. It is the user's "this one works"
signal: if they have not said that a game ran on the release, ask before going on.

## 1. Check the release

```bash
tag=proton-je-ge-11-11-2
gh release view "$tag" -R proton-je/proton-je-ge --json isDraft,isPrerelease,assets \
    --jq '{isDraft,isPrerelease,assets:[.assets[].name]}'
gh release list -R proton-je/proton-je-ge                  # "Latest" marks GitHub's current latest release
cat ~/.steam/root/compatibilitytools.d/"Proton-JE-GE Latest"/version   # "<epoch> <tag>"
```

Both assets (`<tag>.tar.gz`, `<tag>.sha512sum`) must be there, and the release must not be a draft. CI's Upload job
attaches them; nobody uploads or publishes a release by hand (`/rebase-ge`, step 5). Normally `Proton-JE-GE Latest`
already holds this release. When it holds another one, either the user tried this release side by side under its tag
name (`compatibilitytools.d/<tag>`), or they want an older release back. Step 3 moves the tool in both cases.

## 2. GitHub: latest, and only it

```bash
gh release edit "$tag" -R proton-je/proton-je-ge --latest --prerelease=false
for old in $(gh release list -R proton-je/proton-je-ge --json tagName,isPrerelease \
        --jq '.[] | select(.isPrerelease | not) | .tagName' | grep -vx "$tag"); do
    gh release edit "$old" -R proton-je/proton-je-ge --prerelease
done
gh release list -R proton-je/proton-je-ge                  # Latest on $tag, Pre-release on every other tag
gh run list -R proton-je/proton-je-ge -L 3                 # no new run
```

The list must show `Latest` on `$tag` and `Pre-release` on every other tag. Keep an older release offered only when the
user says so, and say which one stayed. To go back to an older release because the newest one breaks a game, run this
skill with the older tag: the loop then demotes the newer one.

These edits fire no `release: published` event, so no build starts. If a Release run shows up anyway, cancel it
(`gh run cancel <id> -R proton-je/proton-je-ge`), because its Upload job would overwrite the files that were verified.

## 3. Steam's `Proton-JE-GE Latest` tool

```bash
cd ~/repos/proton-je-ge && ./install-latest.sh --tag "$tag"
cat ~/.steam/root/compatibilitytools.d/"Proton-JE-GE Latest"/version    # "<epoch> $tag"
```

When the tool already holds `$tag`, the script says "already installed" and exits 0, which is the usual case. Otherwise
it downloads the release, checks its sha512 sum, renames the tool in its `compatibilitytool.vdf` and replaces the
previous `Proton-JE-GE Latest` directory. The name and the path stay, so every Steam mapping to the tool now runs this
release. The script says when Steam is running and needs a restart to notice. `--tag` makes it independent of what
GitHub's `releases/latest` redirect says.

## 4. Steam's mappings

```bash
f=~/.local/share/Steam/config/config.vdf
grep -n '"name"[[:space:]]*"\(proton-je\|Proton-JE\)' "$f"   # every mapping that names a Proton-JE(-GE) build
```

Since 2026-11-01, Steam's global default (app `"0"` under `"CompatToolMapping"`) and the mappings of Helldivers 2
(553850), Space Marine 2 (2183900) and app 1575940 name `Proton-JE-GE Latest`, so normally nothing changes here. List
for the user any mapping that names a per-tag `proton-je-ge-*` build, or the retired Proton-JE (`proton-je-11.0-*`,
`Proton-JE Latest`, both removed from Steam). Change one only when the user asks. They can also do it in Steam: the
game's Properties > Compatibility, or Settings > Compatibility for the default.

Steam rewrites config.vdf on exit, so edit it only while Steam is closed (`pgrep -x steam` finds nothing). For the
default:

```bash
cp "$f" "$f.before-$tag"
n=$(awk '/"CompatToolMapping"/{m=1} m && /^[[:space:]]*"0"$/{z=1} z && /"name"/{print NR; exit}' "$f")
sed -i -E "${n}s/(\"name\"[[:space:]]*)\"[^\"]*\"/\\1\"Proton-JE-GE Latest\"/" "$f"
diff "$f.before-$tag" "$f"                             # exactly one line
```

## 5. Afterwards

- `README.md`: the "Checked on" paragraph says what was checked on which release. If the user wants a game result
  recorded there, keep it qualitative: no play time, session counts or dates. Commit it as a fixup of the README commit,
  then run `git rebase --autosquash $(git describe --tags --abbrev=0 --match 'GE-Proton*')`, and push with
  `--force-with-lease`. A branch push builds nothing.
- Older tools in `compatibilitytools.d/`, such as a per-tag copy: offer to remove the ones that no mapping names. Do not
  remove them unasked.
- Report: which tag is Latest, which tags were demoted, what `Proton-JE-GE Latest` holds, what the mappings name (with
  the backup's path if config.vdf changed), and whether Steam needs a restart.
