const request = require('supertest');
const app = require('../src/index');

describe('Demo Service API', () => {
  describe('GET /health', () => {
    it('should return healthy status', async () => {
      const response = await request(app)
        .get('/health')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'healthy');
      expect(response.body).toHaveProperty('service', 'demo-service');
      expect(response.body).toHaveProperty('version');
      expect(response.body).toHaveProperty('timestamp');
    });
  });

  describe('GET /ready', () => {
    it('should return ready status', async () => {
      const response = await request(app)
        .get('/ready')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'ready');
      expect(response.body).toHaveProperty('service', 'demo-service');
    });
  });

  describe('GET /api/info', () => {
    it('should return service information', async () => {
      const response = await request(app)
        .get('/api/info')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('service', 'demo-service');
      expect(response.body).toHaveProperty('version');
      expect(response.body).toHaveProperty('environment');
      expect(response.body).toHaveProperty('message', 'Golden Path Demo Service');
    });
  });

  describe('POST /api/echo', () => {
    it('should echo the message back', async () => {
      const testMessage = 'Hello, Golden Path!';

      const response = await request(app)
        .post('/api/echo')
        .send({ message: testMessage })
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('received', testMessage);
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body).toHaveProperty('service', 'demo-service');
    });

    it('should return 400 if message is missing', async () => {
      const response = await request(app)
        .post('/api/echo')
        .send({})
        .expect('Content-Type', /json/)
        .expect(400);

      expect(response.body).toHaveProperty('error', 'Bad Request');
      expect(response.body).toHaveProperty('message');
    });

    it('should return 400 if body is empty', async () => {
      const response = await request(app)
        .post('/api/echo')
        .send()
        .expect(400);

      expect(response.body).toHaveProperty('error', 'Bad Request');
    });
  });

  describe('404 handling', () => {
    it('should return 404 for unknown routes', async () => {
      const response = await request(app)
        .get('/unknown/path')
        .expect('Content-Type', /json/)
        .expect(404);

      expect(response.body).toHaveProperty('error', 'Not Found');
      expect(response.body).toHaveProperty('path', '/unknown/path');
    });
  });

  describe('Security headers', () => {
    it('should include security headers from helmet', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      // Helmet adds these headers
      expect(response.headers).toHaveProperty('x-content-type-options', 'nosniff');
      expect(response.headers).toHaveProperty('x-frame-options', 'SAMEORIGIN');
    });
  });

  describe('Error handling', () => {
    it('should handle malformed JSON with 500 error', async () => {
      const response = await request(app)
        .post('/api/echo')
        .set('Content-Type', 'application/json')
        .send('{ invalid json }')
        .expect(500);

      // Express error handler catches JSON parsing errors
      expect(response.body).toHaveProperty('error', 'Internal Server Error');
    });
  });
});
