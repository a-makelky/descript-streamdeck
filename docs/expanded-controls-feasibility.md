# Expanded recorder controls feasibility

Branch: `codex/expanded-recorder-controls`

Tester request:

> Start, end, pause, it would be cool to be able to hit a button and add a "cut" note.

## Short answer

This is feasible as a dev build, but the controls should not all ship at the same confidence level.

- Start: high confidence. The current `Record / Stop` action already starts Screen Recorder reliably.
- End: high confidence. The current `Record / Stop` action already stops Screen Recorder reliably.
- Pause / Resume: medium confidence. The helper has an experimental command, but Descript 2.19.1 still needs a stable visible pause/resume control before this should be packaged for beta users.
- Cut Note: feasible, but we need to define what "note" means. A Descript marker is the best first target. A true Descript comment is less reliable because comments require selected transcript text.

## Product shape

Keep the current public beta action:

- `Record / Stop`

Add a dev-only expanded control set:

- `Start Recording`
- `End Recording`
- `Pause / Resume`
- `Cut Note`

The simple user story is: one deck can have the reliable toggle key, while advanced users can lay out a row of dedicated controls.

## Feasibility by control

### Start Recording

Confidence: high.

The helper already exposes `record`, and the current plugin can choose `record` when the recorder is idle. A dedicated Start action can reuse the existing helper command without new macOS automation.

Release bar:

- starts Screen Recorder in 10/10 attempts
- does nothing destructive if a recording is already active
- shows a clear blocked state if Descript is not running or Accessibility is missing

### End Recording

Confidence: high.

The helper already exposes `stop`, and the current public beta has passed local clean-project testing. A dedicated End action can reuse the same helper command.

Release bar:

- stops active Screen Recorder sessions in 10/10 attempts
- does not start a new recording when idle
- shows a clear blocked state when no session is active

### Pause / Resume

Confidence: medium.

The helper already has a `pauseResume` command and the plugin already has presentation logic for `Pause` and `Resume`. The reason it is hidden from the public package is product confidence, not lack of plumbing.

Current risk:

- Descript 2.19.1 has not exposed a stable pause/resume target in every Screen Recorder state we care about.
- The current beta should not promote Pause / Resume until active and paused snapshots prove the same control can be found repeatedly.

Release bar:

- capture Accessibility snapshots while actively recording and while paused
- prove the helper sees a stable pause/resume control
- pass a 10-attempt pause/resume drill without timing luck

### Cut Note

Confidence: medium.

There are three possible meanings:

1. Add a Descript marker named `CUT`.
2. Add a Descript comment that says `CUT`.
3. Save a local timestamped note outside Descript.

Best first version: marker named `CUT`.

Why:

- Descript's docs say markers can be inserted by typing `#` in the script.
- Descript's docs say comments are tied to selected transcript text, which makes them less reliable from a Stream Deck button during recording.
- A local note is reliable, but it does not solve the editor workflow unless we later sync it into Descript.

Main risk:

- If Screen Recorder is active and Descript is not focused, inserting a marker into the project may require stealing focus from the recording flow.

Recommended dev path:

1. First implement `Cut Note` as a local evidence log: timestamp, current recorder state, project/window title if available, and note text.
2. Then prototype optional marker insertion when Descript's script editor is focused and safe to edit.
3. Only promote marker insertion if it works without interrupting recording.

Release bar:

- button press never breaks an active recording
- local note is captured every time
- if marker insertion is enabled, `CUT` appears in the expected Descript project location in 10/10 attempts

## External Descript behavior checked

- Descript keyboard shortcuts list Screen Recorder start/stop as `Cmd + Shift + 2` by default.
- Descript keyboard shortcuts list marker insertion as `#`.
- Descript keyboard shortcuts list comments as `Shift + Cmd + M`.
- Descript marker docs say markers appear in the script and timeline.
- Descript comment docs say comments require selected transcript text.

Sources:

- https://help.descript.com/hc/en-us/articles/10255582172173-Keyboard-shortcuts
- https://help.descript.com/hc/en-us/articles/10164735239693-Markers-and-chapters
- https://help.descript.com/hc/en-us/articles/10255722202381-Commenting-in-projects

## Implementation plan

### Phase A: Dev branch scaffolding

- Keep `Record / Stop` unchanged. Done.
- Add separate manifest actions for `Start Recording`, `End Recording`, `Pause / Resume`, and `Cut Note`. Done.
- Add matching action classes in `packages/plugin/src/actions`. Done.
- Extend the shared protocol with a `cutNote` command after the local note behavior is defined. Done.

Current dev behavior:

- `Start Recording` calls the existing `record` helper command and never stops an active session.
- `End Recording` calls the existing `stop` helper command and never starts a new session.
- `Pause / Resume` calls the existing experimental `pauseResume` helper command.
- `Cut Note` writes a local JSONL entry to `logs/cut-notes.jsonl` inside the installed plugin bundle.
- `Cut Note` does not edit Descript yet.

### Phase B: Capture proof

- Add a focused drill script for each action.
- Require `Start Recording` and `End Recording` to pass before exposing them in a dev package.
- Capture live snapshots for Pause / Resume before exposing it.
- Capture `Cut Note` output in local JSON first.

### Phase C: Package rules

- Public beta package keeps only stable controls.
- Dev package can expose experimental controls with honest labels.
- Main stays untouched until the dev branch has a passing test matrix.

## Open decisions

- Should `Cut Note` be a marker, comment, or local note first?
- Should dedicated Start and End controls ship alongside `Record / Stop`, or only in an advanced/dev profile?
- Should Pause / Resume target Screen Recorder only, or also Editor Recorder later?
