// assets/js/crdt_client.js

import {EditorState, Text} from "@codemirror/state";
import {EditorView, basicSetup} from "codemirror";
import {json} from "@codemirror/lang-json";

// ———— WebSocket setup ————
const peerId = crypto.randomUUID();              // unique for this client
const socket  = new WebSocket(`ws://${location.host}/ws/crdt`);

socket.addEventListener("open", () => {
  socket.send(JSON.stringify({ type: "join", peer_id: peerId }));
});

// Broadcast local operations
function sendOp(op) {
  socket.send(JSON.stringify({
    type:    "op",
    peer_id,
    payload: op
  }));
}

// ———— CodeMirror editor ————
const state = EditorState.create({
  doc: "",
  extensions: [
    basicSetup,
    json(),
    EditorView.updateListener.of(update => {
      if (!update.docChanged) return;

      // collect each change as a CRDT insert/delete
      for (let tr of update.transactions) {
        for (let c of tr.changes.iterChanges()) {
          if (c.inserted.length > 0) {
            sendOp({
              action: "insert",
              pos:    c.from,
              text:   c.inserted.toString()
            });
          }
          if (c.deleted.length > 0) {
            sendOp({
              action: "delete",
              from:   c.from,
              to:     c.from + c.deleted.length
            });
          }
        }
      }
    })
  ]
});

const view = new EditorView({
  state,
  parent: document.getElementById("editor")
});

// Apply remote ops to CM
socket.addEventListener("message", ev => {
  const msg = JSON.parse(ev.data);
  if (msg.type !== "op" || msg.peer_id === peerId) return;

  const { action, pos, text, from, to } = msg.payload;
  view.dispatch({
    changes:
      action === "insert"
        ? { from: pos, to: pos, insert: text }
        : { from,    to,    insert: "" }
  });
});
