# Architecture

## Why A Plugin Plus A Helper

Using only Stream Deck macros would be fast, but it would also be flimsy.

The project uses two layers:

- The Stream Deck plugin is responsible for actions, settings, packaging, and rendering button state.
- The macOS helper is responsible for everything platform-specific: detecting Descript, sending key events, checking Accessibility permission, reading the UI tree, and pressing buttons.

That split matters because Descript does not currently expose a public desktop automation surface for recorder controls. The plugin layer alone is not a good place to own UI automation heuristics.

## Runtime Flow

1. A Stream Deck action appears.
2. The plugin asks the helper for current status.
3. The helper inspects Descript and returns a status payload.
4. The plugin renders the key title/state based on that status.
5. When the user presses a key, the plugin sends a command to the helper.
6. The helper executes the command and returns an updated status snapshot.
7. The plugin shows success or alert feedback and refreshes visible actions.

## Packages

### `packages/shared`

Holds the contract between the TypeScript plugin and the Swift helper:

- command names
- settings shape
- status payloads
- command results
- debug snapshot payloads

### `packages/plugin`

Owns:

- Stream Deck actions
- helper process management
- periodic status refresh
- settings UI
- final `.sdPlugin` bundle

The plugin is intentionally thin. It should not know how to automate macOS.

### `packages/helper`

Owns:

- Descript process discovery
- bundle/version inspection
- shortcut synthesis for Screen Recorder
- Accessibility trust detection
- window/button inspection
- UI button presses for record and stop, with pause/resume kept as an experimental helper command

## Command Surface

The helper currently exposes:

- `ping`
- `getStatus`
- `record`
- `pauseResume`
- `stop`
- `openPermissions`
- `debugSnapshot`

This is small on purpose. It is easier to keep a narrow control surface stable than to expose a wide helper API we do not need yet.

## Status Model

The helper returns:

- whether Descript is running
- the detected Descript version
- whether Accessibility is trusted
- preferred recorder
- active recorder when inferable
- recorder state: `idle`, `recording`, `paused`, `unavailable`, or `unknown`
- which controls are currently supported
- a human-readable detail string when something important is missing

That lets the plugin present honest button states instead of blindly firing actions.

## Recorder Strategy

### Screen Recorder

Current strongest path:

- use Accessibility to inspect the Screen Recorder dock
- use the dock's stable primary control for `Record` and `Stop`

This is the most durable near-term strategy because it only exposes the controls that have a verified, repeatable target in the current Descript UI.

### Editor Recorder

Current path:

- UI-button discovery and button press heuristics

This is intentionally marked as less mature. It needs real Accessibility snapshots from several Editor Recorder states before it should be called stable.

## Failure Modes

The helper is expected to fail openly when:

- Descript is not running
- Accessibility permission is missing
- no matching recorder control is visible
- the helper process cannot be launched

The plugin reflects those failures on-device instead of hiding them.

## Durability Plan

The durability strategy is simple:

- keep the protocol small
- keep selectors centralized in the helper
- capture real UI snapshots when Descript changes
- never spread recorder heuristics across multiple places in the codebase
