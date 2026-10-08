# Contributing

## Building

```sh
brew install xcodegen create-dmg   # once — project.yml generates the .xcodeproj
make build               # Debug build, ad-hoc signed
make test                # unit tests
make run                 # build and launch
```

None of these need an Apple Developer account. `xcodebuild` ad-hoc signs a
Debug build automatically, which is enough to run and debug locally.

A note on the keychain, because it is not only a development annoyance. A
keychain item has an access list, which is what "Always Allow" writes to, and a
*partition list*, which nothing in the GUI ever writes to. An app outside the
partition list is refused before the access list is consulted, so approving the
dialogue is good for one read. Claude Code recreates its keychain items on every
token rotation, and a new item's partition list admits only Apple's own tools —
which refuses a properly signed release build as surely as an ad-hoc one.

So `ClaudeCredentials.read` never shows the dialogue from a background refresh:
interaction is switched off for the read, and a refusal is retried through
`/usr/bin/security`, which is Apple-signed and on the item's access list. The
one read that may prompt is the one somebody clicks **Allow access…** for in
Settings. To stop the refusal happening at all, `Scripts/fix-keychain-partitions.sh`
adds Codenotch's Team ID to those items' partition lists — once, with your login
password.

`make release` is different: it archives, signs with a Developer ID
certificate, notarizes with Apple, and regenerates the Sparkle auto-update
feed. That's the maintainer's job for cutting an official build, and it needs
credentials only the maintainer has. You won't need it to contribute.

## Before opening a PR

- `make test` passes.
- New behavior has a test. `Tests/` mirrors `Sources/` by concern, not by
  file — look for the existing test class closest to what you're changing
  before adding a new one.
- If you're changing layout math in `Sources/Notch/NotchLayout.swift`, check it
  against `docs/design/frame-124-hover-tooltip.png` — every constant there is
  quoted from that frame in design-frame pixels via `Design.px(_:)`.

## Code style

- Comments explain **why**, not what — a hidden constraint, a bug a piece of
  code works around, a design decision that would otherwise look arbitrary.
  If removing a comment wouldn't confuse the next reader, it shouldn't be
  there.
- No premature abstraction. Three similar lines beat an early helper.
- A provider adapter (`Sources/Providers/`) should degrade every failure to a
  visible, honest status — `stale`, `needsAuth`, `accessDenied`, `error` — and
  never invent a number. See `UsageProviderError` and `ProviderStatus`.

## Visible copy

- User-visible strings (settings, menus, tooltips, notifications, What's New,
  provider labels and status) go through `L10n.t("English source")`. The
  English source **is** the key.
- English is the source language. Put optional translations in
  `Sources/Localizable.xcstrings`. A missing translation falls back to
  English and must not fail tests — do not gate CI on any locale being
  complete.
- Don't freeze `L10n.t` in a `static let` — lookup has to see the current
  language.
- Follow System plus the in-app Language setting; don't set `AppleLanguages`.
- Windows `windows/codenotch/src/i18n.rs` is a separate system — don't merge
  the two.

## Adding a provider

Implement `UsageProvider` (`Sources/Providers/UsageProvider.swift`). At
minimum:

- Declare a `Fidelity` — `.official` if the number comes from the vendor's own
  endpoint or local state, `.derived` if you computed it yourself (the
  tooltip prefixes a `~`), `.manual` if it's a placeholder.
- Every failure path should map to a `ProviderStatus`, not throw something the
  UI can't render — see how `ClaudeOAuthProvider` and `CodexLocalProvider`
  handle theirs.
- If the credential lives in the keychain, hold it with `CredentialCache`
  rather than reading on every poll — see its doc comment for why.

## Reporting a bug

Include the unified log around the time it happened:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "com.vinz.codenotch"' --info --debug
```

## Syncing this fork with upstream

This fork (`gaelito17/codenotch`) carries three features on top of
`vinzdg/codenotch`: the clipboard history cell, the screenshot cell (with its
tuck against the clipboard cell) and wake-only-at-screen-edge. To pull in
upstream without losing them:

```sh
git remote add upstream https://github.com/vinzdg/codenotch.git   # once
git fetch upstream
git log --oneline main..upstream/main      # what is new
git stash                                  # upstream also touches .gitignore
git checkout -b sync-upstream
git merge upstream/main                    # never merge straight on main
```

Resolve the conflicts on that branch, keeping upstream's structure and
re-applying the three features on top of it, then:

```sh
make test-ci                               # xcodegen + xcodebuild; all green
git commit
git checkout main && git merge --ff-only sync-upstream
git push origin main
git stash pop                              # keep both sides of .gitignore
git branch -d sync-upstream
```

Where the features meet upstream's notch layout (the files that conflicted last
time are `NotchViewModel`, `NotchRootView`, `NotchWindowController`,
`NotchFleet`, `SettingsView` and `Tests/HardwareNotchTests`):

- Geometry counts `cellCount` (providers + clipboard + screenshot), not
  `snapshots.count`. Anything provider-specific keeps `snapshots`.
- Rings are placed with `ringAlong(index:in: cellWing)` and
  `leadAllowance`/`endAllowance`. The screenshot tuck is subtracted in
  `ringCenter`, `bodyLength`, `shapeLength(cellCount:)` and `travelSize`.
- `cellIndex(along:)` picks the nearest ring across `0..<cellCount`, because
  the tucked cells' hover bands overlap.
- Upstream's update card takes priority over the clipboard panel.
- Wake-at-edge means no wake band around the pill: `wakeLength`/`wakeDepth` are
  the resting shape. Adapt upstream tests that assume a band (they use
  `NotchLayout.pillHotZone`) instead of restoring it.

Tests only cover the geometry, so run the app afterwards and check the cells
and hover cards on a notched Mac and on a side edge.
