# Descript Stream Deck plugin

A macOS Stream Deck plugin that starts and stops Descript Screen Recorder from one key.

This project is intentionally small. Stream Deck handles the key, settings, packaging, and status. A bundled Swift helper handles the macOS work: finding Descript, checking Accessibility permission, reading the UI tree, and pressing the recorder control.

If Descript changes its recorder UI, the helper is the place to fix it.

## Current state

Working in the local beta:

- `Record / Stop` is the supported action.
- One key starts Screen Recorder when idle and stops it when recording.
- The key shows `Record` when idle and `Stop` when active.
- Manual testing on June 7, 2026 passed 10 straight Record / Stop clips, including starts and stops while Descript was not focused.
- The yellow `Unavailable` status seen during that test was traced to slow background status checks and fixed in this build.
- The plugin requires macOS Accessibility permission.

Still being held back:

- `Pause / Resume` stays hidden because Descript 2.19.1 does not expose a stable pause/resume control in the current Screen Recorder dock.
- `Editor Recorder` support is scaffolded, but it still needs a real UI capture pass across app states.

## For beta testers

The intended user flow is simple:

1. Download and install the `.streamDeckPlugin` package from the latest GitHub prerelease.
2. Open Stream Deck.
3. Drag `Record / Stop` from the Descript category onto a key.
4. Grant Accessibility permission to the helper if macOS asks.
5. Press once to start Screen Recorder. Press again to stop.

If Descript is not running or permission is missing, the key should show a blocked state instead of pretending it worked.

Latest public test project: [Short Audio Test: Aaron Makelky Streamdeck Plugin 2026.6.7](https://share.descript.com/view/mOF9esgJo3r).

## Tested baseline

Initial validation was done against:

- `macOS 26.5 beta (25F5053d)`
- `Descript 2.16.5`
- `Stream Deck 7.4.0`
- `Stream Deck +`

Latest preflight work on June 7, 2026 used:

- `macOS 26.5`
- `Descript 2.19.1`
- `Stream Deck 7.4.2`
- `Build and package`: passed
- `Install and discoverability`: passed
- `Permission handling`: passed
- `Record / Stop`: passed 10/10 clips in manual clean-project testing
- `Public package`: installed from GitHub prerelease and verified locally

## Architecture

High level:

1. The Stream Deck plugin handles button events, settings, packaging, and status presentation.
2. The Swift helper handles app detection, keyboard-event synthesis, Accessibility inspection, and UI interaction.
3. The plugin and helper communicate over newline-delimited JSON on stdio.

More detail lives in [docs/architecture.md](docs/architecture.md).

## Repo layout

- `packages/plugin`: Stream Deck plugin source and packaged `.sdPlugin` bundle
- `packages/helper`: Swift macOS helper
- `packages/shared`: shared protocol types
- `scripts`: build, sync, packaging, and release-check helpers
- `docs`: architecture, roadmap, and release gate notes

## Build from source

Prerequisites:

- Node.js 20+
- npm 11+
- Swift 6+
- Descript installed at `/Applications/Descript.app`
- Elgato Stream Deck installed on macOS

Build:

```bash
npm install
npm run build
```

Package:

```bash
npm run package:plugin
```

That creates a distributable `.streamDeckPlugin` file in `dist/`.

## Local install

For local testing, you can either:

- double-click the packaged `.streamDeckPlugin` file from `dist/`
- copy or symlink `packages/plugin/com.descript.streamdeck.sdPlugin` into `~/Library/Application Support/com.elgato.StreamDeck/Plugins/`

Then restart Stream Deck or use the plugin reload flow in the app.

## Permissions

There are two permission realities on macOS:

- `Record / Stop` needs Accessibility so the helper can find and press Descript UI controls.
- `Pause / Resume` is not exposed in the packaged beta until Descript exposes a stable pause/resume control again.

If the helper is blocked, the plugin can open the Accessibility settings pane for the user.

## Helper diagnostics

The helper can be tested directly:

```bash
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge status
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge debug
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge record
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge pauseResume
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge stop
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge open-permissions
```

`debug` is the useful one for future hardening because it shows the Descript windows and buttons macOS actually exposes.

## Design priorities

- Minimal code paths
- Clear separation between plugin logic and macOS automation
- Honest status reporting
- Open-source friendly defaults
- A packaged action list that only exposes controls that passed the release gate

## Roadmap

The roadmap is in [docs/roadmap.md](docs/roadmap.md).

## Release gate

The go / no-go criteria live in [docs/test-plan.md](docs/test-plan.md).

## Automated release check

The repo includes an evidence-generating release check:

```bash
npm run release:check
```

What it does:

- runs `typecheck` and packaging unless you pass `--skip-build`
- verifies the packaged bundle contains the required runtime, helper, UI, and assets
- reads the helper `status` and `debug` snapshots
- checks whether the plugin is installed locally and whether Stream Deck logged a plugin connection
- writes a timestamped JSON report into `artifacts/release-check/`

What it does not fake:

- the live `10-attempt` recorder drill for `Record / Stop`

That part still needs a real Descript session with Accessibility granted. Reliability is the product bar.

## License

Apache-2.0.
