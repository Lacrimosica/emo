import { Hono } from 'hono';
import type { Bindings, Variables } from './auth';

export const api = new Hono<{ Bindings: Bindings, Variables: Variables }>();

// 1. GET /api/schedule/:date
api.get('/schedule/:date', async (c) => {
  const date = c.req.param('date');
  if (!date.match(/^\d{4}-\d{2}-\d{2}$/)) {
    return c.json({ error: 'Invalid date format (YYYY-MM-DD)' }, 400);
  }

  // Fetch the schedule base definition
  const scheduleRecord = await c.env.DB.prepare('SELECT * FROM schedule WHERE date = ?').bind(date).first();
  const schedule = scheduleRecord || { date, energy_level: null, mood: null, blocks: [] };

  // Fetch all blocks associated with the date, joined onto tasks
  const { results: rawBlocks } = await c.env.DB.prepare(`
    SELECT 
      b.id, b.start_time, b.end_time, b.task_id, b.type, b.notes, 
      t.name as task_name, t.estimated_hours, t.energy_cost, t.requires_transit, t.transit_minutes, t.recurrence, t.category, t.created_at, t.completed_at, t.deadline
    FROM schedule_block b
    LEFT JOIN task t ON b.task_id = t.id
    WHERE b.schedule_date = ?
    ORDER BY b.start_time ASC
  `).bind(date).all();

  // Map into output format
  schedule.blocks = rawBlocks.map((b: any) => ({
    id: b.id,
    start_time: b.start_time,
    end_time: b.end_time,
    task_id: b.task_id,
    type: b.type,
    notes: b.type === 'fixed_event' ? null : b.notes,
    title: b.task_name || (b.type === 'fixed_event' ? b.notes : null) || (b.type === 'transit' ? 'Transit' : b.type === 'buffer' ? 'Buffer' : 'Untitled Event'),
    energy_cost: b.energy_cost,
    completed_at: b.type === 'fixed_event' && new Date(b.end_time).getTime() < Date.now() ? b.end_time : b.completed_at,
    task: b.task_id ? {
      id: b.task_id,
      name: b.task_name,
      deadline: b.deadline,
      estimated_hours: b.estimated_hours,
      energy_cost: b.energy_cost,
      requires_transit: !!b.requires_transit,
      transit_minutes: b.transit_minutes || 0,
      recurrence: b.recurrence || 'none',
      category: b.category || 'personal',
      created_at: b.created_at,
      completed_at: b.completed_at
    } : undefined
  }));

  // Fetch Backlog (tasks that aren't finished and aren't scheduled today)
  const { results: backlog } = await c.env.DB.prepare(`
    SELECT * FROM task 
    WHERE completed_at IS NULL 
    AND id NOT IN (SELECT task_id FROM schedule_block WHERE schedule_date = ? AND task_id IS NOT NULL)
    ORDER BY created_at DESC
  `).bind(date).all();

  schedule.unscheduled_tasks = backlog || [];

  return c.json(schedule);
});

// GET /api/schedule/weekly/:start
api.get('/schedule/weekly/:start', async (c) => {
  const start = c.req.param('start');
  if (!start.match(/^\d{4}-\d{2}-\d{2}$/)) return c.json({ error: 'Invalid date format' }, 400);

  // Generate 7 consecutive dates
  const dates = [];
  const baseDate = new Date(`${start}T12:00:00Z`); // using midday UTC to safely step days
  for (let i = 0; i < 7; i++) {
    const d = new Date(baseDate.getTime() + i * 24 * 60 * 60 * 1000);
    dates.push(d.toISOString().split('T')[0]);
  }

  const placeholders = dates.map(() => '?').join(',');

  const { results: rawBlocks } = await c.env.DB.prepare(`
    SELECT 
      b.id, b.schedule_date, b.start_time, b.end_time, b.task_id, b.type, b.notes, 
      t.name as task_name, t.estimated_hours, t.energy_cost, t.requires_transit, t.transit_minutes, t.recurrence, t.category, t.created_at, t.completed_at, t.deadline
    FROM schedule_block b
    LEFT JOIN task t ON b.task_id = t.id
    WHERE b.schedule_date IN (${placeholders})
    ORDER BY b.start_time ASC
  `).bind(...dates).all();

  const blocksByDate: Record<string, any[]> = {};
  dates.forEach(d => blocksByDate[d] = []);

  rawBlocks.forEach((b: any) => {
    blocksByDate[b.schedule_date].push({
      id: b.id,
      start_time: b.start_time,
      end_time: b.end_time,
      task_id: b.task_id,
      type: b.type,
      notes: b.type === 'fixed_event' ? null : b.notes,
      title: b.task_name || (b.type === 'fixed_event' ? b.notes : null) || (b.type === 'transit' ? 'Transit' : b.type === 'buffer' ? 'Buffer' : 'Untitled Event'),
      energy_cost: b.energy_cost,
      completed_at: b.type === 'fixed_event' && new Date(b.end_time).getTime() < Date.now() ? b.end_time : b.completed_at
    });
  });

  return c.json({ dates, blocksByDate });
});

// POST /api/schedule/:date/task/:id - Manual fixed-task chronological binding
api.post('/schedule/:date/task/:id', async (c) => {
  const date = c.req.param('date');
  const taskId = c.req.param('id');
  const { start_time, end_time } = await c.req.json();

  const blockId = `blk_${crypto.randomUUID()}`;
  const startISO = `${date}T${start_time}:00`;
  const endISO = `${date}T${end_time}:00`;

  // Clear any existing blocks for this task on this date first so it can be moved cleanly
  await c.env.DB.prepare('DELETE FROM schedule_block WHERE task_id = ? AND schedule_date = ?').bind(taskId, date).run();

  await c.env.DB.prepare(`
    INSERT INTO schedule_block (id, schedule_date, start_time, end_time, task_id, type)
    VALUES (?, ?, ?, ?, ?, 'task')
  `).bind(blockId, date, startISO, endISO, taskId).run();

  return c.json({ success: true, blockId });
});

// POST /api/schedule/sync-calendar/:date
api.post('/schedule/sync-calendar/:date', async (c) => {
  const date = c.req.param('date');
  const user = c.get('user');
  if (!user) return c.json({ error: 'Unauthorized' }, 401);

  const tokenRow = await c.env.DB.prepare('SELECT access_token, refresh_token, expires_at FROM oauth_token WHERE user_id = ?').bind(user.id).first();
  if (!tokenRow) return c.json({ error: 'Google Calendar not connected' }, 401);

  let accessToken = tokenRow.access_token as string;
  const expiresAt = new Date(tokenRow.expires_at as string);

  if (expiresAt < new Date()) {
    if (!tokenRow.refresh_token) return c.json({ error: 'Session expired and no refresh token available' }, 401);

    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: c.env.GOOGLE_CLIENT_ID,
        client_secret: c.env.GOOGLE_CLIENT_SECRET,
        refresh_token: tokenRow.refresh_token as string,
        grant_type: 'refresh_token'
      })
    });

    const tokens = await tokenRes.json();
    if (!tokens.access_token) return c.json({ error: 'Failed to refresh calendar token' }, 401);

    accessToken = tokens.access_token;
    const newExpiry = new Date(Date.now() + tokens.expires_in * 1000).toISOString();
    await c.env.DB.prepare('UPDATE oauth_token SET access_token = ?, expires_at = ? WHERE user_id = ?')
      .bind(accessToken, newExpiry, user.id).run();
  }

  const startObj = new Date(`${date}T00:00:00Z`);
  const timeMin = startObj.toISOString();

  const endObj = new Date(startObj.getTime() + 6 * 24 * 60 * 60 * 1000);
  endObj.setUTCHours(23, 59, 59, 999);
  const timeMax = endObj.toISOString();

  const calRes = await fetch(`https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${encodeURIComponent(timeMin)}&timeMax=${encodeURIComponent(timeMax)}&singleEvents=true&orderBy=startTime`, {
    headers: { Authorization: `Bearer ${accessToken}` }
  });

  if (!calRes.ok) return c.json({ error: 'Failed to fetch calendar from Google' }, 502);
  const calendarData = await calRes.json();

  const dates = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(startObj.getTime() + i * 24 * 60 * 60 * 1000);
    dates.push(d.toISOString().split('T')[0]);
  }
  const placeholders = dates.map(() => '?').join(',');

  await c.env.DB.prepare(`DELETE FROM schedule_block WHERE schedule_date IN (${placeholders}) AND type = 'fixed_event'`).bind(...dates).run();

  const insertSchedule = c.env.DB.prepare(`INSERT INTO schedule (date) VALUES (?) ON CONFLICT DO NOTHING`);
  for (const d of dates) {
    await insertSchedule.bind(d).run();
  }

  const insertEvent = c.env.DB.prepare(`
    INSERT INTO schedule_block (id, schedule_date, start_time, end_time, type, notes)
    VALUES (?, ?, ?, ?, 'fixed_event', ?)
  `);

  for (const item of calendarData.items || []) {
    if (!item.start?.dateTime || !item.end?.dateTime) continue;
    const schedDate = item.start.dateTime.split('T')[0];
    const blockId = `cal_${item.id}`;
    await insertEvent.bind(blockId, schedDate, item.start.dateTime, item.end.dateTime, item.summary || 'Busy').run();
  }

  // --- START SMART COLLISION REPAIR ---
  // 1. Identify and Eject any Task blocks that now overlap with any Fixed Event blocks for these dates
  await c.env.DB.prepare(`
    DELETE FROM schedule_block 
    WHERE id IN (
      SELECT t.id 
      FROM schedule_block t
      JOIN schedule_block f ON t.schedule_date = f.schedule_date
      WHERE t.type = 'task' 
      AND f.type = 'fixed_event'
      AND f.schedule_date IN (${placeholders})
      AND t.start_time < f.end_time 
      AND f.start_time < t.end_time
    )
  `).bind(...dates).run();

  // 2. Auto-heal: Trigger the scheduling engine for each affected date
  for (const d of dates) {
    await generateScheduleForDate(c.env.DB, c.env, d);
  }
  // --- END SMART COLLISION REPAIR ---

  return c.json({ success: true });
});

// 2. POST /api/checkin
api.post('/checkin', async (c) => {
  const { mood, energy, date } = await c.req.json();
  if (!mood || !energy || !date) return c.json({ error: 'Missing defined parameters' }, 400);

  // Upsert checkin record
  await c.env.DB.prepare(`
    INSERT INTO checkin (date, mood, energy) 
    VALUES (?, ?, ?) 
    ON CONFLICT(date) DO UPDATE SET mood=excluded.mood, energy=excluded.energy
  `).bind(date, mood, energy).run();

  // Ensure schedule record exists for this date and gets initialized with checkin values
  await c.env.DB.prepare(`
    INSERT INTO schedule (date, energy_level, mood) 
    VALUES (?, ?, ?) 
    ON CONFLICT(date) DO UPDATE SET energy_level=excluded.energy_level, mood=excluded.mood
  `).bind(date, energy, mood).run();

  // For Phase 3, we don't dynamically build the complex timeline. We just return the updated schedule context.
  return c.json({ success: true, date, mood, energy });
});

// Internal helper for triggering the math engine from other endpoints
async function generateScheduleForDate(db: any, env: any, date: string) {
  const settingsRow = await db.prepare('SELECT settings_json FROM user_settings WHERE id = "default"').first();
  const settings = settingsRow ? JSON.parse(settingsRow.settings_json as string) : { minimum_chunk_minutes: 30 };
  const minChunkMs = (settings.minimum_chunk_minutes || 30) * 60 * 1000;

  const scheduleRecord = await db.prepare('SELECT * FROM schedule WHERE date = ?').bind(date).first();
  if (!scheduleRecord) return { success: false, error: 'No checkin' };

  const energyLevel = (scheduleRecord.energy_level as number) || 3;
  // Energy 1→2h, 2→3.5h, 3→5h, 4→6.5h, 5→8h
  const ENERGY_HOURS = [0, 2, 3.5, 5, 6.5, 8];
  const allowedHours = ENERGY_HOURS[Math.min(5, Math.max(1, energyLevel))];

  const { results: existingBlocks } = await db.prepare(`
    SELECT start_time, end_time FROM schedule_block WHERE schedule_date = ? ORDER BY start_time ASC
  `).bind(date).all();

  const existingBusySpans = existingBlocks.map((b: any) => ({
    start: new Date(b.start_time).getTime(),
    end: new Date(b.end_time).getTime()
  }));

  const busySpans: any[] = [];
  if (existingBusySpans.length > 0) {
    existingBusySpans.sort((a: any, b: any) => a.start - b.start);
    let currentSpan = existingBusySpans[0];
    for (let i = 1; i < existingBusySpans.length; i++) {
      if (existingBusySpans[i].start <= currentSpan.end) {
        currentSpan.end = Math.max(currentSpan.end, existingBusySpans[i].end);
      } else {
        busySpans.push(currentSpan);
        currentSpan = existingBusySpans[i];
      }
    }
    busySpans.push(currentSpan);
  }

  const freeSpans = [];
  let currentTime = new Date(`${date}T09:00:00`).getTime();

  const nowLocal = new Date();
  const localDateStr = `${nowLocal.getFullYear()}-${String(nowLocal.getMonth()+1).padStart(2,'0')}-${String(nowLocal.getDate()).padStart(2,'0')}`;
  const isToday = date === localDateStr;
  if (isToday) {
    currentTime = Math.max(currentTime, Date.now());
  }

  const cutoffBoundary = new Date(`${date}T22:00:00`).getTime();

  for (const block of busySpans) {
    if (currentTime < block.start && (block.start - currentTime) >= minChunkMs) {
      freeSpans.push({ start: currentTime, end: block.start });
    }
    currentTime = Math.max(currentTime, block.end);
  }
  if (currentTime < cutoffBoundary && (cutoffBoundary - currentTime) >= minChunkMs) {
    freeSpans.push({ start: currentTime, end: cutoffBoundary });
  }

  const { results: rawTasks } = await db.prepare(`
    SELECT t.*,
           COALESCE((SELECT SUM((julianday(b.end_time) - julianday(b.start_time)) * 24)
                     FROM schedule_block b WHERE b.task_id = t.id), 0) as completed_hours
    FROM task t
    WHERE t.completed_at IS NULL
    AND t.id NOT IN (SELECT task_id FROM schedule_block WHERE schedule_date = ? AND task_id IS NOT NULL)
  `).bind(date).all();

  const activeTasks = rawTasks.filter((t: any) => {
    const remaining = t.estimated_hours - t.completed_hours;
    return remaining > 0;
  });

  const nowMs = Date.now();
  for (const t of activeTasks) {
    let score = 0;
    if ((t as any).energy_cost === 'high') score += 100;
    else if ((t as any).energy_cost === 'medium') score += 50;
    else score += 10;

    if ((t as any).deadline) {
      const deadlineMs = new Date((t as any).deadline).getTime();
      const daysLeft = (deadlineMs - nowMs) / (1000 * 60 * 60 * 24);
      if (daysLeft <= 1) score += 500;
      else if (daysLeft <= 3) score += 200;
      else if (daysLeft <= 7) score += 50;
    }
    (t as any).heuristic_score = score;
    (t as any).remaining_ms = ((t as any).estimated_hours - (t as any).completed_hours) * 3600000;
  }

  activeTasks.sort((a: any, b: any) => b.heuristic_score - a.heuristic_score);

  let scheduledHours = 0;
  let unscheduledTasks: any[] = [];
  const insertBlock = db.prepare(`
    INSERT INTO schedule_block (id, schedule_date, start_time, end_time, task_id, type)
    VALUES (?, ?, ?, ?, ?, 'task')
  `);
  const insertTransit = db.prepare(`
    INSERT INTO schedule_block (id, schedule_date, start_time, end_time, task_id, type, notes)
    VALUES (?, ?, ?, ?, NULL, 'transit', ?)
  `);

  for (const task of activeTasks) {
    if (scheduledHours >= allowedHours) {
      unscheduledTasks.push(task);
      continue;
    }
    let remainingMs = (task as any).remaining_ms;
    const transitMs = (task as any).requires_transit && (task as any).transit_minutes > 0
      ? (task as any).transit_minutes * 60 * 1000
      : 0;

    let scheduled = false;
    for (let i = 0; i < freeSpans.length; i++) {
      const span = freeSpans[i];
      if (span.start >= cutoffBoundary || remainingMs < minChunkMs) break;
      const gapMs = span.end - span.start;
      const neededMs = transitMs + minChunkMs;
      if (gapMs >= neededMs) {
        let taskStart = span.start;
        if (transitMs > 0 && remainingMs === (task as any).remaining_ms) {
          const tBlockId = `transit_${crypto.randomUUID()}`;
          const tStartISO = new Date(span.start).toISOString();
          const tEndISO = new Date(span.start + transitMs).toISOString();
          await insertTransit.bind(tBlockId, date, tStartISO, tEndISO, `Transit → ${(task as any).name}`).run();
          taskStart = span.start + transitMs;
          freeSpans[i].start += transitMs;
        }
        const availableMs = span.end - freeSpans[i].start;
        const allocMs = Math.min(remainingMs, availableMs);
        if (allocMs >= minChunkMs) {
          const blockId = `auto_${crypto.randomUUID()}`;
          const startISO = new Date(freeSpans[i].start).toISOString();
          const endISO = new Date(freeSpans[i].start + allocMs).toISOString();
          await insertBlock.bind(blockId, date, startISO, endISO, (task as any).id).run();
          scheduledHours += (allocMs / 3600000);
          remainingMs -= allocMs;
          freeSpans[i].start += allocMs;
          scheduled = true;
        }
      } else if (gapMs >= minChunkMs && transitMs === 0) {
        const allocMs = Math.min(remainingMs, gapMs);
        const blockId = `auto_${crypto.randomUUID()}`;
        const startISO = new Date(span.start).toISOString();
        const endISO = new Date(span.start + allocMs).toISOString();
        await insertBlock.bind(blockId, date, startISO, endISO, (task as any).id).run();
        scheduledHours += (allocMs / 3600000);
        remainingMs -= allocMs;
        freeSpans[i].start += allocMs;
        scheduled = true;
      }
      if (remainingMs < minChunkMs) break;
    }
    if (!scheduled) {
      unscheduledTasks.push(task);
    }
  }

  // Try next day for overflow tasks
  if (unscheduledTasks.length > 0) {
    const nextDate = new Date(`${date}T12:00:00`);
    nextDate.setDate(nextDate.getDate() + 1);
    const nextDateStr = nextDate.toISOString().split('T')[0];

    // Ensure schedule record exists for next day
    await db.prepare('INSERT INTO schedule (date) VALUES (?) ON CONFLICT DO NOTHING').bind(nextDateStr).run();

    // Try scheduling overflow tasks on next day
    await generateScheduleForDate(db, env, nextDateStr);
  }

  return { success: true, scheduledHours };
}

// 3. POST /schedule/generate - The Auto-Scheduler Math Engine
api.post('/schedule/generate', async (c) => {
  const { date } = await c.req.json();
  const res = await generateScheduleForDate(c.env.DB, c.env, date);
  if (!res.success) return c.json({ error: res.error }, 400);
  return c.json(res);
});

// 4. POST /api/task
api.post('/task', async (c) => {
  const payload = await c.req.json();
  const taskId = `tsk_${crypto.randomUUID()}`;
  const now = new Date().toISOString();

  const estHours = payload.estimated_hours || 1;
  const eCost = payload.energy_cost || 'medium';
  const category = payload.category || 'personal';
  const deadline = payload.deadline || null;
  const requiresTransit = payload.requires_transit ? 1 : 0;
  const transitMinutes = payload.transit_minutes || 0;

  await c.env.DB.prepare(`
    INSERT INTO task (id, name, estimated_hours, energy_cost, category, deadline, requires_transit, transit_minutes, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(taskId, payload.name, estHours, eCost, category, deadline, requiresTransit, transitMinutes, now).run();

  return c.json({ id: taskId, success: true });
});

// 4. PATCH /api/task/:id
api.patch('/task/:id', async (c) => {
  const id = c.req.param('id');
  const payload = await c.req.json();

  const updates: string[] = [];
  const params: any[] = [];

  if (payload.completed !== undefined) {
    updates.push('completed_at = ?');
    params.push(payload.completed ? new Date().toISOString() : null);
  }
  if (payload.name !== undefined) {
    updates.push('name = ?');
    params.push(payload.name);
  }
  if (payload.energy_cost !== undefined) {
    updates.push('energy_cost = ?');
    params.push(payload.energy_cost);
  }
  if (payload.estimated_hours !== undefined) {
    updates.push('estimated_hours = ?');
    params.push(payload.estimated_hours);
  }
  if ('deadline' in payload) {
    updates.push('deadline = ?');
    params.push(payload.deadline || null);
  }
  if (payload.category !== undefined) {
    updates.push('category = ?');
    params.push(payload.category);
  }
  if (payload.requires_transit !== undefined) {
    updates.push('requires_transit = ?');
    params.push(payload.requires_transit ? 1 : 0);
  }
  if (payload.transit_minutes !== undefined) {
    updates.push('transit_minutes = ?');
    params.push(payload.transit_minutes);
  }

  if (updates.length > 0) {
    params.push(id);
    const sql = `UPDATE task SET ${updates.join(', ')} WHERE id = ?`;
    await c.env.DB.prepare(sql).bind(...params).run();
  }

  return c.json({ success: true, id });
});

// 5. DELETE /api/task/:id
api.delete('/task/:id', async (c) => {
  const id = c.req.param('id');

  await c.env.DB.prepare('DELETE FROM schedule_block WHERE task_id = ?').bind(id).run();
  await c.env.DB.prepare('DELETE FROM task WHERE id = ?').bind(id).run();

  return c.json({ success: true, id });
});

// 6. DELETE /api/schedule/block/:id
api.delete('/schedule/block/:id', async (c) => {
  const id = c.req.param('id');
  await c.env.DB.prepare('DELETE FROM schedule_block WHERE id = ?').bind(id).run();
  return c.json({ success: true, id });
});

// 6b. POST /api/schedule/:date/transit — Manual standalone transit block
api.post('/schedule/:date/transit', async (c) => {
  const date = c.req.param('date');
  const { start_time, duration_minutes, notes } = await c.req.json();
  if (!start_time || !duration_minutes) return c.json({ error: 'Missing start_time or duration_minutes' }, 400);

  const startISO = `${date}T${start_time}:00`;
  const endISO = new Date(new Date(startISO).getTime() + duration_minutes * 60 * 1000).toISOString();
  const blockId = `transit_${crypto.randomUUID()}`;

  await c.env.DB.prepare(`
    INSERT INTO schedule (date) VALUES (?) ON CONFLICT DO NOTHING
  `).bind(date).run();

  await c.env.DB.prepare(`
    INSERT INTO schedule_block (id, schedule_date, start_time, end_time, task_id, type, notes)
    VALUES (?, ?, ?, ?, NULL, 'transit', ?)
  `).bind(blockId, date, startISO, endISO, notes || 'Transit').run();

  return c.json({ success: true, blockId });
});

// 7. GET /api/settings
api.get('/settings', async (c) => {
  const row = await c.env.DB.prepare('SELECT settings_json FROM user_settings WHERE id = "default"').first();
  const settings = row ? JSON.parse(row.settings_json as string) : { minimum_chunk_minutes: 30 };
  return c.json(settings);
});

// 8. POST /api/settings
api.post('/settings', async (c) => {
  const payload = await c.req.json();
  await c.env.DB.prepare('INSERT INTO user_settings (id, settings_json) VALUES ("default", ?) ON CONFLICT(id) DO UPDATE SET settings_json=excluded.settings_json')
    .bind(JSON.stringify(payload)).run();
  return c.json({ success: true, settings: payload });
});

// Mock Chat (Phase 3 still uses mock AI until we plug in Ollama)
api.post('/chat', async (c) => {
  let body: any = {};
  try {
    body = await c.req.json();
  } catch (e) {
    console.error('Failed to parse JSON. Body might be malformed or empty.');
    return c.json({ error: 'Invalid JSON payload' }, 400);
  }

  const { history } = body;
  if (!history || !Array.isArray(history)) {
    console.error('Invalid history format. Received body:', body);
    return c.json({ error: 'Invalid history format', received: body }, 400);
  }

  const systemPrompt = `You are a personal scheduling assistant. Evaluate the user's task request.
To properly schedule a task, you need to decide:
1. "name" (string, short description)
2. "estimated_hours" (number)
3. "energy_cost" (low, medium, or high string)
4. "category" (external_commitment, self_care, personal, leisure)

RULES:
- NEVER ask more than ONE clarifying question at a time.
- If you lack information, reply plainly with your single conversational question.
- IF you confidently have all the required information, output NOTHING but a valid JSON object matching this exact format:
{"ready": true, "task": {"name": string, "estimated_hours": number, "energy_cost": string, "category": string}}`;

  const messages = [
    { role: 'system', content: systemPrompt },
    ...history.map((msg: any) => ({
      role: msg.role === 'ai' ? 'assistant' : 'user',
      content: msg.text,
    }))
  ];

  try {
    const hostUrl = c.env.OLLAMA_HOST || 'https://ollama.com/api/chat';
    const isNativeOllama = hostUrl.endsWith('/api/chat') || hostUrl.includes('ollama.com');

    const res = await fetch(hostUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${c.env.OLLAMA_API_KEY || ''}`
      },
      body: JSON.stringify({
        model: 'gemma3:12b',
        messages,
        stream: false,
        options: { temperature: 0.1 }
      })
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error("Upstream Error Details:", errText);
      return c.json({ error: 'Upstream AI returned error' }, 502);
    }

    const data: any = await res.json();

    // Polyfill resolving string based on Ollama or standard OpenAI formatting
    const reply = isNativeOllama
      ? data.message?.content?.trim()
      : data.choices?.[0]?.message?.content?.trim();

    return c.json({ response: reply });
  } catch (err: any) {
    console.error('Fatal AI Request Error:', err);
    return c.json({ error: err.message }, 500);
  }
});
