import { Hono } from 'hono';
import { getCookie, setCookie, deleteCookie } from 'hono/cookie';

export type Bindings = {
  DB: any;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  SESSION_SECRET: string;
  ALLOWED_EMAIL: string;
  CLIENT_URL?: string;
  OLLAMA_HOST?: string;
  OLLAMA_API_KEY?: string;
};

export type Variables = {
  user: { id: string; email: string; google_id: string } | null;
};

export const authApp = new Hono<{ Bindings: Bindings, Variables: Variables }>();

const getRedirectUri = (c: any) => {
  const base = c.env.CLIENT_URL || 'http://localhost:5173';
  return `${base}/api/auth/callback`;
};

authApp.get('/login', async (c) => {
  const state = crypto.randomUUID();
  setCookie(c, 'oauth_state', state, { httpOnly: true, maxAge: 60 * 10, path: '/' });

  const redirectUri = getRedirectUri(c);
  const scope = 'openid email profile https://www.googleapis.com/auth/calendar';

  const url = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${c.env.GOOGLE_CLIENT_ID}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&scope=${encodeURIComponent(scope)}&access_type=offline&prompt=consent&state=${state}`;

  return c.redirect(url);
});

authApp.get('/callback', async (c) => {
  const url = new URL(c.req.url);
  const code = url.searchParams.get('code');
  const returnedState = url.searchParams.get('state');
  const storedState = getCookie(c, 'oauth_state');

  if (!code || !returnedState || returnedState !== storedState) {
    return c.text('Invalid state or missing code', 400);
  }

  const redirectUri = getRedirectUri(c);

  // Exchange code for tokens
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: c.env.GOOGLE_CLIENT_ID,
      client_secret: c.env.GOOGLE_CLIENT_SECRET,
      code,
      grant_type: 'authorization_code',
      redirect_uri: redirectUri
    })
  });

  const tokens = await tokenRes.json();
  if (!tokens.access_token) {
    return c.text(`Failed to fetch tokens: ${JSON.stringify(tokens)}\nTargeted URI was: ${redirectUri}`, 400);
  }

  // Get user profile
  const profileRes = await fetch('https://www.googleapis.com/oauth2/v2/userinfo', {
    headers: { Authorization: `Bearer ${tokens.access_token}` }
  });
  const profile = await profileRes.json();

  if (!c.env.ALLOWED_EMAIL) {
    console.error("Missing ALLOWED_EMAIL in bounding environment! Existing keys:", Object.keys(c.env));
    return c.text(`ALLOWED_EMAIL not configured on server. Bound env keys located: ${Object.keys(c.env).join(', ')}`, 500);
  }

  if (profile.email !== c.env.ALLOWED_EMAIL) {
    console.error(`Email mismatch security trap. Received Profile: ${profile.email}, Allowed Bound: ${c.env.ALLOWED_EMAIL}`);
    return c.text(`Unauthorized email address. Received: ${profile.email}, Configured Server Match: ${c.env.ALLOWED_EMAIL}`, 403);
  }

  const db = c.env.DB;
  const userId = `usr_${profile.id}`;

  // Purge the local dev_mock user if it mapped your ALLOWED_EMAIL previously, so the real formal Google ID can cleanly take ownership of the UNIQUE constraint!
  await db.prepare('DELETE FROM "user" WHERE google_id = "dev_mock_123"').run();

  // Upsert formal user
  await db.prepare('INSERT INTO "user" (id, email, google_id) VALUES (?, ?, ?) ON CONFLICT(google_id) DO UPDATE SET email=excluded.email').bind(userId, profile.email, profile.id).run();

  // Upsert tokens
  const tokenExpiry = new Date(Date.now() + tokens.expires_in * 1000).toISOString();
  await db.prepare('INSERT INTO oauth_token (user_id, access_token, refresh_token, expires_at) VALUES (?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET access_token=excluded.access_token, refresh_token=COALESCE(excluded.refresh_token, oauth_token.refresh_token), expires_at=excluded.expires_at').bind(userId, tokens.access_token, tokens.refresh_token || null, tokenExpiry).run();

  // Create session
  const sessionId = crypto.randomUUID();
  const sessionExpiry = new Date(Date.now() + 1000 * 60 * 60 * 24 * 30).toISOString(); // 30 days
  await db.prepare('INSERT INTO session (id, user_id, expires_at) VALUES (?, ?, ?)').bind(sessionId, userId, sessionExpiry).run();

  setCookie(c, 'emo_session', sessionId, { httpOnly: true, maxAge: 60 * 60 * 24 * 30, path: '/' });

  return c.redirect('/');
});


authApp.get('/me', async (c) => {
  const sessionId = getCookie(c, 'emo_session');
  if (!sessionId) return c.json({ error: 'No session' }, 401);

  const session = await c.env.DB.prepare('SELECT user_id, expires_at FROM session WHERE id = ?').bind(sessionId).first();
  if (!session || new Date(session.expires_at as string) < new Date()) {
    deleteCookie(c, 'emo_session');
    return c.json({ error: 'Invalid or expired session' }, 401);
  }

  const user = await c.env.DB.prepare('SELECT id, email, google_id FROM "user" WHERE id = ?').bind(session.user_id).first();
  if (!user) return c.json({ error: 'User not found' }, 404);

  return c.json({ user });
});

authApp.post('/logout', async (c) => {
  const sessionId = getCookie(c, 'emo_session');
  if (sessionId) {
    await c.env.DB.prepare('DELETE FROM session WHERE id = ?').bind(sessionId).run();
    deleteCookie(c, 'emo_session', { path: '/' });
  }
  return c.json({ success: true });
});

// Middleware for protected routes
export const authMiddleware = async (c: any, next: any) => {
  const sessionId = getCookie(c, 'emo_session');
  if (!sessionId) return c.json({ error: 'Unauthorized' }, 401);

  const session = await c.env.DB.prepare('SELECT user_id, expires_at FROM session WHERE id = ?').bind(sessionId).first();
  if (!session || new Date(session.expires_at as string) < new Date()) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const user = await c.env.DB.prepare('SELECT id, email, google_id FROM "user" WHERE id = ?').bind(session.user_id).first();
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  c.set('user', user);
  await next();
};
