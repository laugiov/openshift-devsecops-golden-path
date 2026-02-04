/**
 * __SERVICE_NAME__ - Main Entry Point
 * Generated from Golden Path template
 */

const http = require('http');

const PORT = process.env.PORT || __SERVICE_PORT__;
const SERVICE_NAME = '__SERVICE_NAME__';
const VERSION = process.env.VERSION || '1.0.0';

// Simple routing
const routes = {
  '/health': (req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'healthy',
      service: SERVICE_NAME,
      version: VERSION,
      timestamp: new Date().toISOString()
    }));
  },

  '/ready': (req, res) => {
    // Add readiness checks here (database, cache, etc.)
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ready: true }));
  },

  '/': (req, res) => {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      service: SERVICE_NAME,
      version: VERSION,
      endpoints: ['/health', '/ready']
    }));
  }
};

const server = http.createServer((req, res) => {
  const handler = routes[req.url] || ((req, res) => {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not Found' }));
  });

  handler(req, res);
});

server.listen(PORT, () => {
  console.log(`${SERVICE_NAME} listening on port ${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
