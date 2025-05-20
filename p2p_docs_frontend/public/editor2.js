// Class defining the WebSocket client for handling connections and messages
class WebSocketClient {
  constructor(url) {
    this.url = url;
    this.socket = null;
    this.clientId = null;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 1000;
    this.keepaliveInterval = null;
    this.messageQueue = [];
    this.messageHandlers = [];
  }

  connect() {
    this.socket = new WebSocket(this.url);

    this.socket.onopen = () => {
      console.log("WebSocket connected");
      this.reconnectAttempts = 0;

      // Send queued messages
      const pendingMessages = [...this.messageQueue];
      this.messageQueue = [];
      pendingMessages.forEach((msg) => this.send(msg));

      // Start keepalive to prevent disconnection of the socket on idle
      this.keepaliveInterval = setInterval(() => {
        this.send({ type: "ping" });
      }, 25000);
    };

    this.socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        this.messageHandlers.forEach((handler) => handler(data));

        if (data.type === "ping") {
          this.send({ type: "pong" });
        }
      } catch (e) {
        console.error("Error parsing message:", e);
      }
    };

    this.socket.onclose = (event) => {
      console.log(`WebSocket closed: ${event.code}`);
      clearInterval(this.keepaliveInterval);

      if (
        event.code !== 1000 &&
        this.reconnectAttempts < this.maxReconnectAttempts
      ) {
        setTimeout(() => {
          this.reconnectAttempts++;
          console.log(`Reconnecting attempt ${this.reconnectAttempts}...`);
          this.connect();
        }, this.reconnectDelay * this.reconnectAttempts);
      }
    };

    this.socket.onerror = (error) => {
      console.error("WebSocket error:", error);
    };
  }

  onMessage(handler) {
    this.messageHandlers.push(handler);
  }

  send(message) {
    const msg = typeof message === "string" ? message : JSON.stringify(message);

    if (this.socket?.readyState === WebSocket.OPEN) {
      this.socket.send(msg);
      return true;
    }

    // Queue message if not connected
    if (!this.messageQueue.some((m) => m === msg)) {
      this.messageQueue.push(msg);
    }
    return false;
  }

  disconnect() {
    if (this.socket) {
      clearInterval(this.keepaliveInterval);
      this.socket.close(1000, "Normal closure");
      this.messageQueue = [];
    }
  }
}

document.addEventListener("DOMContentLoaded", () => {
  const editor = document.getElementById("editor");
  const connectBtn = document.getElementById("connect-btn");
  const newFileBtn = document.getElementById("new-file-btn");
  const shareBtn = document.getElementById("share-btn");
  const tokenDiv = document.getElementById("token");
  const tokenInput = document.getElementById("token-input");
  const disconnectBtn = document.getElementById("disconnect-btn");
  const peerAddressInput = document.getElementById("peer-address");
  let prevValue = editor.value;
  // CSS fixes for overflow
  Object.assign(editor.style, {
    whiteSpace: "pre-wrap",
    overflowWrap: "break-word",
    wordBreak: "break-word",
    overflow: "auto",
  });
  let isRemoteUpdate = false;
  let wsClient = new WebSocketClient(`http://${window.location.host}/ws`);
  let clientId = null;
  let pendingOperations = [];
  let localPendingOperations = [];
  // Initialize editor as non-editable
  editor.readOnly = true;
  wsClient.onMessage(handleServerMessage);
  wsClient.connect();

  const autoConnect = () => {
    let peerId = getCookie("peer_id");
    console.log("Peer ID from cookie:", peerId);

    // Wait for WebSocket to be ready
    const tryConnect = () => {
      if (wsClient.socket?.readyState === WebSocket.OPEN) {
        if (peerId === "local") {
          newFileBtn.click();
        } else if (peerId) {
          peerAddressInput.value = peerId;
          connectBtn.click();
        }
      } else {
        setTimeout(tryConnect, 50);
      }
    };
    tryConnect();
  };
  // Show loading screen until WebSocket is connected
  const loadingScreen = document.getElementById("loading-screen");
  loadingScreen.style.display = "block";
  editor.style.display = "none";
  document.getElementById("connect-form").style.display = "none";
  document.getElementById("disconnect-form").style.display = "none";

  wsClient.onMessage(() => {
    if (loadingScreen.style.display !== "none") {
      loadingScreen.style.display = "none";
      document.getElementById("connect-form").style.display = "block";
    }
  });

  wsClient.socket &&
    wsClient.socket.addEventListener("open", () => {
      loadingScreen.style.display = "none";
      document.getElementById("connect-form").style.display = "block";
    });

  // Connect button handler
  connectBtn.addEventListener("click", () => {
    const peerAddress = peerAddressInput.value.trim();
    console.log("Connecting to peer:", peerAddress);
    connectToServer(peerAddress);
    document.getElementById("connect-form").style.display = "none";
    document.getElementById("disconnect-form").style.display = "block";
    editor.style.display = "block";
  });

  // New file button handler
  newFileBtn.addEventListener("click", () => {
    connectToServer();
    document.getElementById("connect-form").style.display = "none";
    document.getElementById("disconnect-form").style.display = "block";
    editor.style.display = "block";
  });

  // Disconnect button handler
  disconnectBtn.addEventListener("click", () => {
    const peerId = getCookie("peer_id");
    if (peerId && peerId !== clientId) {
      wsClient.send({ type: "disconnect", peer_id: peerId });
    } else {
      wsClient.send({ type: "disconnect" });
    }
    clientId = null;
    pendingOperations = [];

    editor.value = "";
    document.getElementById("connect-form").style.display = "block";
    document.getElementById("disconnect-form").style.display = "none";
    tokenDiv.style.display = "none";
    editor.style.display = "none";

    // Clear the cookie
    deleteCookie("peer_id");
  });

  // Share button handler
  shareBtn.addEventListener("click", () => {
    if (tokenDiv.style.display === "block") {
      tokenDiv.style.display = "none";
    } else {
      tokenDiv.style.display = "block";
    }
    tokenInput.value = clientId;
  });

  // function to connect to the server for a new file or from the state of an other peer
  function connectToServer(peerAddress) {
    // Register message handler

    if (peerAddress) {
      wsClient.send({ type: "connect", peer_address: peerAddress });
      setCookie("peer_id", peerAddress, 7);
    } else {
      setCookie("peer_id", "local", 7);
    }
    // get client ID
    wsClient.send({ type: "get_client_id" });
  }

  function handleServerMessage(data) {
    if (data.type === "init") {
      clientId = data.client_id;
      editor.value = data.content || "";
      editor.readOnly = false; // Enable editing after init
      //editor.normalize(); // Normalize text nodes

      // Process any locally queued operations
      localPendingOperations.forEach((op) => {
        op.client_id = clientId;
        wsClient.send(op);
      });
      localPendingOperations = [];
    } else if (data.type === "operations") {
      // Handle CRDT operations from server
      isRemoteUpdate = true;
      console.log("[Editor] Received operations:", data.operations);
      applyOperations(data.operations);

      isRemoteUpdate = false;
    } else if (data.type === "error") {
      if (data.message === "invalid_peer_address") {
        disconnectBtn.click();
        alert("Invalid peer address. Please try again.");
      } else {
        console.error("Unknown error from server", data);
      }
    }
  }

  editor.addEventListener("beforeinput", (e) => {
    const { inputType, data, target } = e;
  const oldVal = e.target.value;
  const start = target.selectionStart;
  const end   = target.selectionEnd;

  // figure out what (if anything) is being inserted
  let inserted = data;
  if (!inserted && inputType === 'insertLineBreak') {
    // Enter key in a textarea
    inserted = '\n';
  }

  // INSERTIONS (typing, paste, enter, etc.)
  if (inputType.startsWith('insert') && inserted) {
    const insertPos = start;
    for (let i = 0; i < inserted.length; i++) {
     let operation = ({
        type:     'insert',
        char:     inserted[i] === '\n' ? '\n' : inserted[i],
        index: insertPos + i + 1,
        client_id: clientId
      });
      if (wsClient.send(operation)) {
        pendingOperations.push(operation);
      }
    }
  }
  // DELETIONS (backspace, delete key, cut, selection delete)
  else if (inputType.startsWith('delete')) {
    let deletedText = '';
    let deletePos   = start;

    console.log(inputType, start, end, oldVal);

    if(start < end){
      deletedText = oldVal.slice(start, end);
      deletePos   = start;
    }else{

    switch (inputType) {
      case 'deleteContentBackward':
        deletePos   = start - 1;
        deletedText = oldVal.charAt(deletePos);
        break;
      case 'deleteContentForward':
        deletePos   = start;
        deletedText = oldVal.charAt(deletePos);
        break;
      default:
        // deleteByCut, deleteContent, deleteByDrag, etc.
        deletedText = oldVal.slice(start, end);
        deletePos   = start;
    }
  }

    for (let i = 0; i < deletedText.length; i++) {
      let operation = ({
        type:     'delete',
        char:     deletedText[i] === '\n' ? '\n' : deletedText[i],
        index: deletePos + i + 1,
        client_id: clientId
      });
      if (wsClient.send(operation)) {
        pendingOperations.push(operation);
      }
    }
  }
  // (you can add other inputTypes if you care about undo/formatting/etc.)
  }
  
  );


  /*
  // Handle local edits
  editor.addEventListener("input", (e) => {
    if (isRemoteUpdate || !clientId) {
      if (!clientId) {
        // Store operation locally until we get client ID
        const operation = createOperationFromEvent(e);
        if (operation) localPendingOperations.push(operation);
      }
      return;
    }

    const selection = window.getSelection();
    const range = selection.getRangeAt(0);

    let inserted = e.data;
    if(!inserted && e.inputType === "insertLineBreak" ){
      inserted = "\\n";
    }

    if (e.inputType.startsWith("insert") && inserted) {
      const index = e.target.selectionStart;
      const operation = {
        type: "insert",
        index: index,
        char: inserted,
        client_id: clientId,
      };

      if (wsClient.send(operation)) {
        pendingOperations.push(operation);
      }
    } else if (e.inputType === "deleteContentBackward") {
      const index = e.target.selectionStart + 1; // 1-based
      if (index >= 1) {
        // Minimum index is 1
        const operation = {
          type: "delete",
          index: index,
          client_id: clientId,
        };

        if (wsClient.send(operation)) {
          pendingOperations.push(operation);
        }
      }
    }
  });
  */

  function applyOperations(op) {
    isRemoteUpdate = true;
    console.log("[Editor] Applying operation:", op);
    op = JSON.parse(op);

    if (op["type"] === "insert") {
      console.log("[Editor] Applying insert op:", op);
      insertAt(op["index"], op["char"]);
    } else if (op["type"] === "delete") {
      console.log("[Editor] Applying delete op:", op);
      deleteAt(op["index"]);
    }
    //editor.normalize(); // Normalize text nodes
    isRemoteUpdate = false;
  }

  function insertAt(index, char) {
    index = index - 1; // zero-based
    toEdit = editor.value;
    editor.value = toEdit.slice(0,index) + char + toEdit.slice(index);
    //if (isRemoteUpdate) restoreCursorPosition();
  }

  function deleteAt(index) {
    
    toEdit = editor.value;
    editor.value = toEdit.slice(0,index) + toEdit.slice(index+1);
    if (isRemoteUpdate) {
      //restoreCursorPosition();
    }
  }

  function createOperationFromEvent(e) {
    const selection = window.getSelection();
    const range = selection.getRangeAt(0);

    if (e.inputType === "insertText") {
      index = e.target.selectionStart;
      return {
        type: "insert",
        index: index,
        char: e.data,
      };
    } else if (e.inputType === "deleteContentBackward") {
      const index = e.target.selectionStart + 1;
      if (index >= 1) {
        return {
          type: "delete",
          index: index,
        };
      }
    }
    return null;
  }

  function restoreCursorPosition() {
    // This is a simplified version - you might want to implement
    // a more sophisticated cursor position tracking system
    const range = document.createRange();
    range.selectNodeContents(editor);
    range.collapse(false); // Move to end

    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  // Cookie utility functions
  function getCookie(name) {
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop().split(";").shift();
  }

  function setCookie(name, value, days) {
    const date = new Date();
    date.setTime(date.getTime() + days * 24 * 60 * 60 * 1000);
    const expires = `expires=${date.toUTCString()}`;
    document.cookie = `${name}=${value}; ${expires}; path=/`;
  }

  function deleteCookie(name) {
    document.cookie = `${name}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;`;
  }
  autoConnect();
});
