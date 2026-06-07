# Roadmap

## Phase 1: Solid Screen Recorder MVP

Goal: make one `Record / Stop` key dependable for Descript Screen Recorder on macOS.

Work:

- grant Accessibility to the helper and capture real Descript button snapshots
- tighten record and stop selectors based on those snapshots
- confirm button state refresh under idle and recording states
- ship a first installable plugin artifact

Definition of done:

- another user can install the plugin, grant permissions once, and reliably start and stop Screen Recorder from one Stream Deck key

## Phase 1.5: Pause / Resume Feasibility

Goal: decide whether `Pause / Resume` can graduate from experimental to supported.

Work:

- find a stable pause/resume control in the current Descript Screen Recorder surface
- capture UI snapshots for recording and paused states if Descript exposes them
- require a 10-attempt pass before promoting `Pause / Resume` into the release bar

Definition of done:

- `Pause / Resume` toggles the intended recorder without timing luck or developer-only setup

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

- watch for any remaining yellow `Unavailable` flashes after the timeout fix
- keep `Pause / Resume` out of the packaged action list until Descript exposes a stable control
- continue hardening the dedicated screen-recording control window path alongside the in-editor recorder path
- repeat the 10-attempt drill before each shared build
