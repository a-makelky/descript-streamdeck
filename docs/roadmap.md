# Roadmap

## Phase 1: Solid Screen Recorder MVP

Goal: make `Pause / Resume` and `Stop` dependable for an active Descript Screen Recorder session on macOS.

Work:

- grant Accessibility to the helper and capture real Descript button snapshots
- tighten pause, resume, and stop selectors based on those snapshots
- confirm button state refresh under idle, recording, and paused states
- ship a first installable plugin artifact

Definition of done:

- another user can install the plugin, grant permissions once, and reliably pause, resume, and stop Screen Recorder from Stream Deck

## Phase 1.5: Reliable Start Recording

Goal: decide whether `Record` can graduate from experimental to supported.

Work:

- find a stable way to launch recording from a normal Descript project window
- verify whether the editor `Record` control, menu bar actions, or documented shortcut can do this reliably
- require a 10-attempt pass before promoting `Record` into the release bar

Definition of done:

- `Record` starts the intended recorder from a normal Descript session without timing luck or developer-only setup

## Phase 2: Harden Editor Recorder

Goal: support the Editor Recorder with the same three-button control model.

Work:

- capture Editor Recorder Accessibility snapshots in multiple states
- identify stable window titles and button labels
- add recorder-surface inference with less guesswork
- add targeted tests for selector drift

Definition of done:

- Editor Recorder commands are based on verified UI structure, not hopeful labels

## Phase 3: UX And Distribution Polish

Goal: make the plugin easy for ordinary Descript users to install and trust.

Work:

- write a cleaner install guide with screenshots
- improve permission messaging in the plugin
- consider onboarding actions or a health-check action
- publish signed release artifacts and release notes

Definition of done:

- non-technical testers can install and verify the plugin without reading source

## Phase 4: Chrome Experiment

Goal: decide whether browser-based Descript control is worth supporting.

Work:

- inspect Descript web recorder surfaces in Chrome
- determine whether stable DOM or extension-level controls exist
- keep this separate from the macOS helper path

Definition of done:

- either a viable Chrome path is proven, or the project clearly documents why it is not worth shipping

## Immediate Next Work

- keep `Pause / Resume` and `Stop` on the public-beta lane now that they have first live Stream Deck validation
- keep `Record` out of the packaged action list until it clears the reliability gate
- run the 10-attempt drill for active-session controls inside the packaged `.sdPlugin`
- package and publish a cleaner beta artifact plus install notes for testers
- continue isolating a stable `Record` launch path from the normal editor state
- decide whether `Record` should stay experimental for the first community release
