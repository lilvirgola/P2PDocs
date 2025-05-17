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
      console.log('WebSocket connected');
      this.reconnectAttempts = 0;
      
      // Send queued messages
      while (this.messageQueue.length > 0) {
        this.send(this.messageQueue.shift());
      }
      
      // Start keepalive
      this.keepaliveInterval = setInterval(() => {
        this.send({ type: 'ping' });
      }, 25000);
    };

    this.socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        // Call all registered message handlers
        this.messageHandlers.forEach(handler => handler(data));
        
        if (data.type === 'ping') {
          this.send({ type: 'pong' });
        }
      } catch (e) {
        console.error('Error parsing message:', e);
      }
    };

    this.socket.onclose = (event) => {
      console.log(`WebSocket closed: ${event.code}`);
      clearInterval(this.keepaliveInterval);
      
      if (event.code !== 1000 && this.reconnectAttempts < this.maxReconnectAttempts) {
        setTimeout(() => {
          this.reconnectAttempts++;
          console.log(`Reconnecting attempt ${this.reconnectAttempts}...`);
          this.connect();
        }, this.reconnectDelay * this.reconnectAttempts);
      }
    };

    this.socket.onerror = (error) => {
      console.error('WebSocket error:', error);
    };
  }

  onMessage(handler) {
    this.messageHandlers.push(handler);
  }

  send(message) {
    // Only send if we have a valid connection
    if (this.socket?.readyState === WebSocket.OPEN) {
      const msg = typeof message === 'string' ? message : JSON.stringify(message);
      this.socket.send(msg);
      return true;
    }
    return false;
  }

  disconnect() {
    if (this.socket) {
      clearInterval(this.keepaliveInterval);
      this.socket.close(1000, 'Normal closure');
    }
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const editor = document.getElementById('editor');
  const connectBtn = document.getElementById('connect-btn');
  const newFileBtn = document.getElementById('new-file-btn');
  const shareBtn = document.getElementById('share-btn');
  const tokenDiv = document.getElementById('token');
  const tokenInput = document.getElementById('token-input');
  const disconnectBtn = document.getElementById('disconnect-btn');
  const peerAddressInput = document.getElementById('peer-address');

  let myEnvEndpoint = window.env.MY_ENV_ENDPOINT || 'localhost:4000';
  let isRemoteUpdate = false;
  let wsClient = new WebSocketClient(`ws://${myEnvEndpoint}/ws`);;
  let clientId = null;
  let pendingOperations = [];
  let lastKnownVersion = 0;
    wsClient.onMessage(handleServerMessage);
    wsClient.connect();

  // Connect button handler
  connectBtn.addEventListener('click', () => {
    const peerAddress = peerAddressInput.value.trim();
    console.log('Connecting to peer:', peerAddress);
    connectToServer(peerAddress);
    document.getElementById('connect-form').style.display = 'none';
    document.getElementById('disconnect-form').style.display = 'block';
    editor.style.display = 'block';
  });

  // New file button handler
  newFileBtn.addEventListener('click', () => {
    connectToServer();
    document.getElementById('connect-form').style.display = 'none';
    document.getElementById('disconnect-form').style.display = 'block';
    editor.style.display = 'block';
  });

  // Disconnect button handler
  disconnectBtn.addEventListener('click', () => {
    clientId = null;
    pendingOperations = [];
    lastKnownVersion = 0;
    editor.innerHTML = '';
    document.getElementById('connect-form').style.display = 'block';
    document.getElementById('disconnect-form').style.display = 'none';
    tokenDiv.style.display = 'none';
    editor.style.display = 'none';
  });

    // Share button handler
    shareBtn.addEventListener('click', () => {
        if (tokenDiv.style.display === 'block'){
            tokenDiv.style.display = 'none';
        }
        else{
            tokenDiv.style.display = 'block';
        }
        tokenInput.value = clientId;
    });
        

  function connectToServer(peerAddress) {
    // Register message handler
    
    if (peerAddress) {
      wsClient.send({ type: 'connect', peer_address: peerAddress });
    }
    // get client ID
    wsClient.send({ type: 'get_client_id' });
  }

  function handleServerMessage(data) {
    if (data.type === 'init') {
      // Initial document content and client ID
      clientId = data.client_id;
      lastKnownVersion = data.version || 0;
      editor.innerHTML = data.content || '';
    } 
    else if (data.type === 'operations') {
      // Handle CRDT operations from server
      isRemoteUpdate = true;
      applyOperations(data.operations);
      
      // Update last known version
      if (data.version) {
        lastKnownVersion = data.version;
      }
      
      isRemoteUpdate = false;
    }
    else if (data.type === 'error') {
      if (data.message==="invalid_peer_address") {
        disconnectBtn.click();
        alert("Invalid peer address. Please try again.");
      }
      else{
        console.error('Unknown error from server', data);
      }
    }
  }

  // Handle local edits
  editor.addEventListener('input', (e) => {
  if (isRemoteUpdate || !wsClient) return;

  const selection = window.getSelection();
  const range = selection.getRangeAt(0);

  if (e.inputType === 'insertText') {
    const index = getCursorIndex(editor, range.startContainer, range.startOffset);
    const operation = {
      type: 'insert',
      index: index,
      char: e.data,
      client_id: clientId,
      version: lastKnownVersion
    };

    console.log('[Editor] Trying to send insert op:', operation);

    if (wsClient.send(operation)) {
      pendingOperations.push(operation);
      // Do not insert locally — wait for the echoed op
    }
  } else if (e.inputType === 'deleteContentBackward') {
    const index = getCursorIndex(editor, range.startContainer, range.startOffset)+1;
    if (index >= 0) {
      const operation = {
        type: 'delete',
        index: index,
        client_id: clientId,
        version: lastKnownVersion
      };
      console.log('[Editor] Trying to send delete op:', operation);

      if (wsClient.send(operation)) {
        pendingOperations.push(operation);
        // Do not delete locally — wait for the echoed op
      }
    }
  }
});
  
  // More accurate cursor position handling
  function getCursorIndex(editor, node, offset) {
    const range = document.createRange();
    range.setStart(editor, 0);
    range.setEnd(node, offset);
    
    // Handle cases where the editor might contain other elements
    let text = '';
    const treeWalker = document.createTreeWalker(
      range.commonAncestorContainer,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: function(node) {
          return NodeFilter.FILTER_ACCEPT;
        }
      },
      false
    );
    
    let currentNode = treeWalker.nextNode();
    while (currentNode) {
      if (currentNode === range.endContainer) {
        text += currentNode.textContent.substring(0, range.endOffset);
        break;
      } else {
        text += currentNode.textContent;
      }
      currentNode = treeWalker.nextNode();
    }
    
    return text.length;
  }
  
function applyOperations(operations) {
  isRemoteUpdate = true;
  
  operations.forEach(op => {
    // Skip operations that originated from this client
    if (op.client_id === clientId) return;
    
    if (op.type === 'insert') {
      insertAt(op.index, op.char);
    } else if (op.type === 'delete') {
      deleteAt(op.index);
    }
  });
  
  // Update last known version from the most recent operation
  if (operations.length > 0) {
    lastKnownVersion = operations[operations.length - 1].version;
  }
  
  isRemoteUpdate = false;
}
  
  function insertAt(index, char) {
    const textNode = document.createTextNode(char);
    const range = document.createRange();
    
    if (editor.childNodes.length === 0) {
      editor.appendChild(document.createTextNode(''));
    }
    
    let pos = 0;
    let found = false;
    
    // Walk through child nodes to find the correct position
    for (let i = 0; i < editor.childNodes.length; i++) {
      const node = editor.childNodes[i];
      
      // Skip non-text nodes
      if (node.nodeType !== Node.TEXT_NODE) {
        continue;
      }
      
      const nodeLength = node.length || 0;
      
      if (pos + nodeLength >= index) {
        const nodeOffset = index - pos;
        range.setStart(node, nodeOffset);
        range.setEnd(node, nodeOffset);
        range.insertNode(textNode);
        found = true;
        break;
      }
      pos += nodeLength;
    }
    
    if (!found && index >= pos) {
      editor.appendChild(textNode);
    }
    
    // Restore cursor position after remote updates
    if (isRemoteUpdate) {
      restoreCursorPosition();
    }
  }

  function deleteAt(index) {
    let pos = 0;
    
    for (let i = 0; i < editor.childNodes.length; i++) {
      const node = editor.childNodes[i];
      
      if (node.nodeType !== Node.TEXT_NODE) {
        continue;
      }
      
      const nodeLength = node.length || 0;
      
      if (pos + nodeLength > index) {
        const nodeOffset = index - pos;
        node.deleteData(nodeOffset, 1);
        break;
      }
      pos += nodeLength;
    }
    
    // Restore cursor position after remote updates
    if (isRemoteUpdate) {
      restoreCursorPosition();
    }
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
});