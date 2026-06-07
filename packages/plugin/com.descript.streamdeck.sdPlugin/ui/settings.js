(function () {
  const defaults = {
    preferredRecorder: "auto",
    bringDescriptToFront: true,
    allowHotkeyFallback: true,
    openPermissionsIfNeeded: true,
    screenRecorderShortcut: "cmd+shift+2",
    cutNoteText: "CUT"
  };

  const form = document.getElementById("settings-form");
  let websocket = null;
  let uuid = "";

  function mergeSettings(incoming) {
    return { ...defaults, ...(incoming || {}) };
  }

  function applySettings(settings) {
    const next = mergeSettings(settings);
    for (const [key, value] of Object.entries(next)) {
      const field = form.elements.namedItem(key);
      if (!field) continue;
      if (field instanceof HTMLInputElement && field.type === "checkbox") {
        field.checked = Boolean(value);
      } else if (field instanceof HTMLInputElement || field instanceof HTMLSelectElement) {
        field.value = String(value);
      }
    }
  }

  function currentSettings() {
    return {
      preferredRecorder: form.elements.namedItem("preferredRecorder").value,
      bringDescriptToFront: form.elements.namedItem("bringDescriptToFront").checked,
      allowHotkeyFallback: form.elements.namedItem("allowHotkeyFallback").checked,
      openPermissionsIfNeeded: form.elements.namedItem("openPermissionsIfNeeded").checked,
      screenRecorderShortcut: form.elements.namedItem("screenRecorderShortcut").value.trim() || defaults.screenRecorderShortcut,
      cutNoteText: form.elements.namedItem("cutNoteText").value.trim() || defaults.cutNoteText
    };
  }

  function sendSettings() {
    if (!websocket || websocket.readyState !== WebSocket.OPEN) {
      return;
    }

    websocket.send(
      JSON.stringify({
        event: "setSettings",
        context: uuid,
        payload: currentSettings()
      })
    );
  }

  form.addEventListener("input", sendSettings);
  form.addEventListener("change", sendSettings);

  window.connectElgatoStreamDeckSocket = function (
    inPort,
    inUUID,
    inRegisterEvent,
    inInfo,
    inActionInfo
  ) {
    uuid = inUUID;
    websocket = new WebSocket(`ws://127.0.0.1:${inPort}`);

    websocket.addEventListener("open", () => {
      websocket.send(
        JSON.stringify({
          event: inRegisterEvent,
          uuid: inUUID
        })
      );
      websocket.send(
        JSON.stringify({
          event: "getSettings",
          context: inUUID
        })
      );
    });

    websocket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.event === "didReceiveSettings") {
        applySettings(message.payload?.settings);
        return;
      }

      if (message.event === "sendToPropertyInspector") {
        applySettings(message.payload);
      }
    });

    applySettings(JSON.parse(inActionInfo).payload?.settings);
    void inInfo;
  };
})();
