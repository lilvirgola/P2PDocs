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
  const neighborsBtn = document.getElementById("neighbors-btn");
  const neighborsDiv = document.getElementById("neighbors");
  const neighborsInput = document.getElementById("neighbors-input");
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
    let peerId = getQueryParam("peer_id");
    console.log("Peer ID from URL:", peerId);

    // Wait for WebSocket to be ready
    const tryConnect = () => {
      if (wsClient.socket?.readyState === WebSocket.OPEN) {
        if (peerId === "local") {
          newFileBtn.click();
        } else if (peerId) {
          peerAddressInput.value = peerId;
          connectBtn.click();
        }
        else{
          disconnectBtn.click();
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
    const peerId = getQueryParam("peer_id");
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

    // Remove peer_id from URL
    const url = new URL(window.location);
    url.searchParams.delete('peer_id');
    window.history.replaceState({}, '', url);
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

  neighborsBtn.addEventListener("click", () => {
    if (neighborsDiv.style.display === "block") {
      neighborsDiv.style.display = "none";
    } else {
      neighborsDiv.style.display = "block";
    }
  });

  // function to connect to the server for a new file or from the state of an other peer
  function connectToServer(peerAddress) {
    // Register message handler

    if (peerAddress) {
      wsClient.send({ type: "connect", peer_address: peerAddress });
      const url = new URL(window.location);
      url.searchParams.set('peer_id', peerAddress);
      window.history.replaceState({}, '', url);
    } else {
      const url = new URL(window.location);
      url.searchParams.set('peer_id', 'local');
      window.history.replaceState({}, '', url);
    }
    // get client ID
    wsClient.send({ type: "get_client_id" });
  }

  function handleServerMessage(data) {
    console.log(data);
    if (data.type === "init") {
      clientId = data.client_id;
      editor.value = data.content || "";
      editor.readOnly = false; // Enable editing after init
      neighborsInput.value = data.neighbors || "";
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
        char:     inserted[i],
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

    //console.log(inputType, start, end, oldVal);

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
        index: deletePos + 1,
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
    let cursor = editor.selectionStart;
    if (cursor >= index) cursor+=1;
    index = index - 1; // zero-based
    toEdit = editor.value;
    editor.value = toEdit.slice(0,index) + char + toEdit.slice(index);
    if (isRemoteUpdate) editor.setSelectionRange(cursor, cursor);
  }

  function deleteAt(index) {
    let cursor = editor.selectionStart;
    if (cursor >= index) cursor = max(0, cursor - 1);
    index = index - 1;
    toEdit = editor.value;
    editor.value = toEdit.slice(0,index) + toEdit.slice(index+1);
    if (isRemoteUpdate) {
      editor.setSelectionRange(cursor, cursor);
    }
  }

  function getQueryParam(name) {
    const urlParams = new URLSearchParams(window.location.search);
    return urlParams.get(name);
  }

  autoConnect();
});
