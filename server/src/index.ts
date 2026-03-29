import { Hono } from 'hono';
import { authApp, authMiddleware } from './auth';
import { api as appApi } from './api';
import type { Bindings, Variables } from './auth';

const app = new Hono<{ Bindings: Bindings, Variables: Variables }>();

// Auth Routes (unprotected)
app.route('/api/auth', authApp);

// Protect all /api routes (except /auth handled above)
app.use('/api/*', authMiddleware);

// Mount core API logic
app.route('/api', appApi);

export default app;
