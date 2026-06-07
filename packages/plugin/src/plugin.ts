import type { RecorderAction } from "./actions/recorder-action.js";
import streamDeck from "@elgato/streamdeck";
import { CutNoteAction } from "./actions/cut-note-action.js";
import { EndAction } from "./actions/end-action.js";
import { PauseResumeAction } from "./actions/pause-resume-action.js";
import { RecordAction } from "./actions/record-action.js";
import { StopAction } from "./actions/stop-action.js";

const actions: RecorderAction[] = [
  new StopAction(),
  new RecordAction(),
  new EndAction(),
  new PauseResumeAction(),
  new CutNoteAction()
];

for (const action of actions) {
  streamDeck.actions.registerAction(action);
}

streamDeck.logger.info(
  "[descript-streamdeck] registered expanded recorder actions"
);

streamDeck.system.onApplicationDidLaunch((event) => {
  if (event.application === "com.descript.beachcube") {
    for (const action of actions) {
      void action.refreshVisibleActions();
    }
  }
});

streamDeck.system.onApplicationDidTerminate((event) => {
  if (event.application === "com.descript.beachcube") {
    for (const action of actions) {
      void action.refreshVisibleActions();
    }
  }
});

streamDeck.system.onSystemDidWakeUp(() => {
  for (const action of actions) {
    void action.refreshVisibleActions();
  }
});

streamDeck
  .connect()
  .then(() => {
    streamDeck.logger.info("[descript-streamdeck] connected to Stream Deck");
  })
  .catch((error: unknown) => {
    streamDeck.logger.error(
      `[descript-streamdeck] failed to connect to Stream Deck: ${String(error)}`
    );
    process.exitCode = 1;
  });
