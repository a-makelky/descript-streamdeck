# Descript Recorder for Stream Deck

An open-source Stream Deck plugin for controlling Descript recording on macOS.

The project is built around a simple rule: keep the Stream Deck side thin, and put the macOS-specific logic in a small native helper. That gives us cleaner code, better reliability, and a straighter path to supporting multiple Descript recorder surfaces over time.

## What Exists Today

This repo already ships a working first foundation:

- A Stream Deck plugin with two supported actions: `Pause / Resume` and `Stop`
- A bundled Swift helper binary that detects Descript, checks Accessibility permissions, inspects the Descript UI tree, and executes recorder commands
- A shared JSON protocol between the plugin and helper
- A property inspector with per-action settings for recorder preference, focus behavior, shortcut fallback, and permission handling
- One-command packaging into a distributable `.streamDeckPlugin` file

## Current Truth

This is the honest state of the project right now:

- `Pause / Resume` and `Stop` are the strongest controls today. They now have live Stream Deck hardware validation against both the standard in-project recorder controls and the dedicated Descript screen-recording control surface when macOS Accessibility is granted.
- `Record` is still experimental. The code path stays in the repo for further work, but it is not part of the current packaged public-beta action set because it is not yet reliable from a normal in-project editor window.
- `Pause / Resume` and `Stop` require macOS Accessibility permission because they rely on UI inspection and button presses inside Descript.
- `Editor Recorder` support is scaffolded and partially implemented through UI-button discovery, but it still needs a real UI capture pass to make it release-grade across app states.
- The helper includes a `debug` command so we can inspect Descript window/button snapshots and harden selectors instead of guessing.

Current practical release call:

- `Pause / Resume`: go for continued beta validation
- `Stop`: go for continued beta validation
- overall public release: not yet, until the `10-attempt` reliability drill passes

## Tested Baseline

The initial build and validation in this repo were done against:

- `macOS 26.5 beta (25F5053d)`
- `Descript 2.16.5`
- `Stream Deck 7.4.0`
- `Stream Deck +`

## Architecture

High level:

1. The Stream Deck plugin handles button events, settings, packaging, and status presentation.
2. The Swift helper handles app detection, keyboard-event synthesis, Accessibility inspection, and UI interaction.
3. The plugin and helper communicate over newline-delimited JSON on stdio.

More detail lives in [docs/architecture.md](/Users/aaronmakelky/Library/Mobile%20Documents/com~apple~CloudDocs/Windsurf%20Projects%20Coding/Descript-StreamDeck/docs/architecture.md).

## Repo Layout

- `packages/plugin`: Stream Deck plugin source and packaged `.sdPlugin` bundle
- `packages/helper`: Swift macOS helper
- `packages/shared`: shared protocol types
- `scripts`: build, sync, and packaging helpers
- `docs`: architecture and roadmap

## Quick Start

### Prerequisites

- Node.js 20+
- npm 11+
- Swift 6+
- Descript installed at `/Applications/Descript.app`
- Elgato Stream Deck installed on macOS

### Build

```bash
npm install
npm run build
```

### Package

```bash
npm run package:plugin
```

That creates a distributable file in `dist/`.

## Local Install

For local testing, you can either:

- double-click the packaged `.streamDeckPlugin` file from `dist/`, or
- copy/symlink `packages/plugin/com.descript.streamdeck.sdPlugin` into `~/Library/Application Support/com.elgato.StreamDeck/Plugins/`

Then restart Stream Deck or use the plugin reload flow in the app.

## Permissions

There are two permission realities on macOS:

- `Pause / Resume` and `Stop` need Accessibility so the helper can find and press Descript UI controls.
- `Record` may work in some Descript states through shortcut or UI paths, but it is not a release-grade promise yet and is not exposed as a packaged Stream Deck action today.

If the helper is blocked, the plugin can open the Accessibility settings pane for the user.

## Helper Diagnostics

The helper can be tested directly:

```bash
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge status
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge debug
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge record
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge pauseResume
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge stop
packages/plugin/com.descript.streamdeck.sdPlugin/bin/descript-bridge open-permissions
```

`debug` is especially important for hardening Editor Recorder support, because it tells us what Descript windows and buttons are actually exposed to Accessibility on a real machine.

## Design Priorities

- Minimal code paths
- Clear separation between plugin logic and macOS automation
- Honest status reporting instead of pretending controls succeeded
- Open-source friendliness over private one-off hacks
- A packaged action surface that only exposes controls that actually clear the release bar

## License

Apache-2.0. It is community-friendly and easy to adopt, while also being cleaner than MIT for a real public project because it includes an explicit patent grant.

## Roadmap

The roadmap is in [docs/roadmap.md](/Users/aaronmakelky/Library/Mobile%20Documents/com~apple~CloudDocs/Windsurf%20Projects%20Coding/Descript-StreamDeck/docs/roadmap.md).

## Release Gate

The go / no-go criteria live in [docs/test-plan.md](/Users/aaronmakelky/Library/Mobile%20Documents/com~apple~CloudDocs/Windsurf%20Projects%20Coding/Descript-StreamDeck/docs/test-plan.md).

## Automated Release Check

The repo now includes an evidence-generating release check:

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

- the live `10-attempt` recorder drill for `Pause / Resume` and `Stop`

That part still needs a real Descript session with Accessibility granted, because reliability is the actual product bar. `Record` stays experimental until it can start from a normal Descript project state consistently enough to deserve inclusion in that bar.
