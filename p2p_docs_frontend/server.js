const express = require('express');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const port = 3000;

// Serve static files from 'public' directory
app.use(express.static(path.join(__dirname, 'public')));

// Create HTTP server
const server = app.listen(port, () => {
  console.log(`Frontend server running at http://localhost:${port}`);
});
// Simple route handling - serve editor.html for all routes
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'editor.html'));
});

app.get('/env.js', (req, res) => {
  res.setHeader('Content-Type', 'application/javascript');
  res.send(`
    window.env = {
      API_URL: "${process.env.MY_ENV_ENDPOINT || 'localhost:4000'}"
    };
  `);
});

// Handle 404
app.use((req, res) => {
  res.status(404).send('Not Found');
});