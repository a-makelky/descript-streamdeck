import type { RecorderAction } from "./actions/recorder-action.js";
import streamDeck from "@elgato/streamdeck";
import { PauseResumeAction } from "./actions/pause-resume-action.js";
import { StopAction } from "./actions/stop-action.js";

const actions: RecorderAction[] = [
  new PauseResumeAction(),
  new StopAction()
];

for (const action of actions) {
  streamDeck.actions.registerAction(action);
}

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

void streamDeck.connect();
