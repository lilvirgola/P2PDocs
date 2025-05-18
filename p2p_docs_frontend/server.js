const express = require('express');
const path = require('path');
const { createProxyMiddleware } = require("http-proxy-middleware");

const app = express();
const port = 3000;

// Solo host e porta
const backendHost = process.env.MY_ENV_ENDPOINT || 'localhost:4000';
const wsTarget = 'http://' + backendHost;

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// Proxy middleware
const proxy = createProxyMiddleware( {
  target: wsTarget,
  ws: true,
  changeOrigin: true,
});

app.use('/ws',proxy);

// Server HTTP
const server = app.listen(port, () => {
  console.log(`Frontend server at http://localhost:${port}, proxying to ${wsTarget}`);
});

// Supporto WebSocket
server.on('upgrade', proxy.upgrade);

// Route principale
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'editor.html'));
});

// 404 handler
app.use((req, res) => {
  res.status(404).send('Not Found');
});
