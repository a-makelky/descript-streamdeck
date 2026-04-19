# Test Plan And Release Gate

This project needs an explicit `go / no-go` gate because the hard part is not compiling code. The hard part is whether the Stream Deck action can control a real Descript recorder session reliably on a real Mac.

## Release Stages

There are two practical release bars:

### Stage 1: Screen Recorder Public Beta

This is the first shippable target.

Scope:

- macOS desktop app only
- Descript Screen Recorder only
- `Pause / Resume`
- `Stop`
- active recording session already open in Descript

`Record` remains an experimental lane until the Descript start surface is reliable from a normal in-project editor state.

### Stage 2: Full Recorder Release

This is the broader target.

Scope:

- Screen Recorder
- Editor Recorder
- stable recorder detection
- clearer user messaging around permissions and unsupported states

## Go / No-Go Principle

The rule is simple:

- `Go` means a normal Descript user can install the plugin, grant permissions once, and reliably control the targeted recorder without reading source code.
- `No-go` means the feature only works with developer knowledge, timing luck, or fragile UI assumptions.

## Hard Gates

These are non-negotiable.

### Gate 1: Build And Package

Go:

- `npm run build` passes
- `npm run typecheck` passes
- `npm run package:plugin` produces a valid `.streamDeckPlugin` artifact
- the packaged plugin contains the helper binary, manifest, UI files, and plugin runtime

No-go:

- any build or typecheck failure
- packaged artifact missing helper/runtime files
- Stream Deck refuses to load the plugin bundle

### Gate 2: Install And Discoverability

Go:

- plugin installs cleanly in Stream Deck
- actions appear in the Stream Deck action list under the Descript category
- both supported actions can be placed on keys
- property inspector renders correctly for each action

No-go:

- plugin installs inconsistently
- actions do not appear
- property inspector is broken or empty

### Gate 3: Permission Handling

Go:

- when Accessibility is missing, the plugin state clearly tells the user what is blocked
- the helper can open Accessibility settings
- after permission is granted, the plugin reflects the new state without requiring source-code changes

No-go:

- plugin silently fails when permission is missing
- user is left guessing why `Pause / Resume` or `Stop` do nothing
- permission recovery requires developer-only steps

## Functional Gates

These determine whether a recorder surface is ready to ship.

### Screen Recorder Gate

This is the first real `go / no-go` ship decision.

Go:

- `Pause / Resume` correctly toggles state in 10 consecutive attempts during an active session
- `Stop` ends the active recording in 10 consecutive attempts
- button title/state reflects `recording` and `paused` accurately enough to guide the user
- failures are obvious and recoverable
- plugin clearly tells the user when no active recording session is available

No-go:

- `Pause / Resume` or `Stop` succeeds less than 9 out of 10 attempts
- `Pause / Resume` or `Stop` require the user to click Descript first in an undocumented way
- key state is misleading often enough that a user would press the wrong control
- helper buttons depend on labels that drift between windows without a fallback plan

### Editor Recorder Gate

This is stricter because it is currently more heuristic.

Go:

- a real Accessibility snapshot exists for all target Editor Recorder states
- `Record`, `Pause / Resume`, and `Stop` each succeed in 10 consecutive attempts
- recorder-surface detection chooses Editor Recorder correctly when it is visible and active
- no Screen Recorder selector is accidentally reused against the wrong surface

No-go:

- selectors are based on guesswork instead of captured UI snapshots
- the helper cannot reliably distinguish Editor Recorder from general editor UI
- the wrong Descript button is pressed even once in normal testing

## UX Gates

### User-Facing Clarity

Go:

- key titles make sense at a glance
- missing permissions produce a clear blocked state
- missing Descript app produces a clear blocked state
- the README install flow matches what the user actually sees

No-go:

- users need a verbal walkthrough from the maintainer to understand button behavior
- titles are technically correct but practically confusing

### Failure Behavior

Go:

- failures show alert feedback on-device
- helper errors do not crash the plugin
- the plugin recovers after Descript relaunch or system wake

No-go:

- plugin gets stuck after one helper failure
- stale state persists after Descript closes or reopens

## Regression Matrix

Every release candidate should be tested across this matrix.

### Baseline Environment

- macOS version
- Descript version
- Stream Deck version
- Stream Deck hardware model

### Functional Scenarios

- Descript not running
- Descript running but idle
- Screen Recorder visible, not recording
- Screen Recorder actively recording
- Screen Recorder paused
- recording stopped and returned to idle
- Descript relaunched while Stream Deck is open
- Mac sleeps and wakes while plugin is loaded

### Permission Scenarios

- Accessibility denied
- Accessibility granted after the plugin has already loaded

### Multi-Action Safety

- action used alone
- action used inside a multi-action

## Recommended Test Script

For the next real validation pass, use this order:

1. Run `npm run release:check` to generate the baseline evidence report.
2. Install the packaged plugin in Stream Deck.
3. Put `Pause / Resume` and `Stop` on visible keys.
4. Test with Accessibility denied and confirm blocked-state messaging.
5. Grant Accessibility to the helper.
6. Run `npm run release:check -- --skip-build` again to confirm the permission lane turned green and to capture a fresh helper snapshot.
7. Run the Screen Recorder 10-attempt cycle:
   - open a live Descript recording session
   - pause
   - resume
   - stop
8. Capture helper `debug` snapshots for each recorder state.
9. Harden selectors based on those snapshots.
10. Repeat the 10-attempt cycle.
11. Keep `Record` in the experimental lane until it can start a recording from a normal Descript project window in 10 consecutive attempts.
12. Only after Screen Recorder is stable, decide whether to re-expose `Record` in the packaged plugin.
13. Only after that, repeat the process for Editor Recorder.

## Automated Evidence

`npm run release:check` is the repo's preflight scoreboard.

It automatically checks:

- typecheck and packaging
- bundle completeness
- helper status and debug output
- local plugin install presence
- recent Stream Deck and plugin log evidence

It writes a timestamped JSON report into `artifacts/release-check/`.

Interpretation:

- `Go` means that lane is green.
- `Partial` means the lane is set up correctly but still needs a live validation step.
- `No-go` means there is a real blocker, not a paperwork issue.

Important:

- the automated release check does not replace the live 10-attempt drill
- the Screen Recorder release gate should still stay red until the real button cycle succeeds repeatedly on a real recorder session

## Current Readiness

Current call:

- `Build gate`: go
- `Packaging gate`: go
- `Install gate`: go
- `Permission gate`: go
- `Screen Recorder controls`: one live Stream Deck hardware validation passed for both `Pause / Resume` and `Stop`
- `Screen Recorder gate`: improved, but still not release-ready until the `10-attempt` drill passes
- `Editor Recorder gate`: definitely not release-ready yet

In plain English:

The core buttons are now working on the actual Stream Deck against a live Descript session, which is the first real on-field proof. But we still should not promise broad reliability to Descript users until those same controls survive the full `10-attempt` repetition test.
