const express = require('express');
const helmet = require('helmet');
const pino = require('pino');
const pinoHttp = require('pino-http');

// Configuration
const config = {
  port: process.env.PORT || 3000,
  environment: process.env.NODE_ENV || 'development',
  version: process.env.APP_VERSION || '1.0.0',
  serviceName: 'demo-service'
};

// Logger setup
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  formatters: {
    level: (label) => ({ level: label })
  }
});

// Express app
const app = express();

// Security middleware
app.use(helmet());

// Request logging
app.use(pinoHttp({ logger }));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: config.serviceName,
    version: config.version,
    timestamp: new Date().toISOString()
  });
});

// Readiness check endpoint
app.get('/ready', (req, res) => {
  res.json({
    status: 'ready',
    service: config.serviceName
  });
});

// Main API endpoint
app.get('/api/info', (req, res) => {
  res.json({
    service: config.serviceName,
    version: config.version,
    environment: config.environment,
    message: 'Golden Path Demo Service'
  });
});

// Echo endpoint for testing
app.post('/api/echo', express.json(), (req, res) => {
  const { message } = req.body;

  if (!message) {
    return res.status(400).json({
      error: 'Bad Request',
      message: 'Missing required field: message'
    });
  }

  res.json({
    received: message,
    timestamp: new Date().toISOString(),
    service: config.serviceName
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.path
  });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error({ err }, 'Unhandled error');
  res.status(500).json({
    error: 'Internal Server Error',
    message: config.environment === 'development' ? err.message : 'An error occurred'
  });
});

// Start server (only if not in test mode)
if (process.env.NODE_ENV !== 'test') {
  app.listen(config.port, () => {
    logger.info({
      port: config.port,
      environment: config.environment,
      version: config.version
    }, `${config.serviceName} started`);
  });
}

module.exports = app;
