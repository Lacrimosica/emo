# Emo — AI-Powered Daily Task Scheduler

A personal web app that intelligently schedules your day around fixed calendar events, adapting to your energy and mood. Dump your tasks, let AI clarify what you need, and get an optimized daily schedule.

## Features

- **Free-form task input** — Text or voice
- **AI clarification** — One clarifying question at a time via Ollama
- **Daily check-in** — Track mood (1–5) and energy (1–5) levels
- **Smart scheduling** — Fits tasks around Google Calendar events with built-in transit buffers
- **Weekly backlog** — Pull tasks from backlog as capacity permits
- **Auto-reschedule** — Update schedule when tasks complete or get skipped
- **Persistent storage** — All data in Cloudflare D1

## Stack

| Component | Technology |
|-----------|-----------|
| **Frontend** | SvelteKit, deployed to Cloudflare Pages |
| **Backend** | Hono on Cloudflare Workers |
| **Database** | Cloudflare D1 (SQLite) |
| **AI** | Ollama Cloud (deepseek-v3:671b) |
| **Calendar** | Google Calendar API v3 |
| **Transit** | Google Maps Directions API |
| **Monorepo** | npm workspaces (`/client`, `/server`) |

## Project Structure

```
emo/
├── client/                 # SvelteKit frontend
│   ├── src/
│   │   ├── routes/        # Page routes
│   │   ├── lib/
│   │   │   └── components/ # Reusable UI components
│   │   └── app.css        # Global styles
│   └── package.json
├── server/                 # Cloudflare Workers (Hono)
│   ├── src/
│   │   ├── api.ts         # Route handlers
│   │   ├── auth.ts        # Google OAuth & session management
│   │   └── index.ts       # Worker entry point
│   ├── migrations/        # D1 schema
│   └── package.json
├── package.json           # Monorepo root
└── .env                   # Environment variables (not committed)
```

## Getting Started

### Prerequisites

- Node.js 18+
- Cloudflare account with:
  - D1 database
  - Workers deployed
  - Pages for deployment
- Google OAuth 2.0 credentials
- Ollama API key

### Installation

```bash
# Install dependencies
npm install

# Create .env from template
cp .env.example .env
# Fill in your credentials

# Run locally
npm run dev

# Build for deployment
npm run build

# Deploy
npm run deploy
```

### Environment Variables

```env
CLOUDFLARE_ACCOUNT_ID=your_id
D1_DATABASE_ID=your_db_id
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_secret
SESSION_SECRET=random_uuid
OLLAMA_HOST=https://ollama.com/api/chat
OLLAMA_API_KEY=your_api_key
ALLOWED_EMAIL=your.email@gmail.com
CLIENT_URL=http://localhost:5371
```

## Database Schema

See [DATABASE.md](DATABASE.md) for the complete ER diagram, table structure, and relationships.

## API Routes

All routes require authentication except `/api/auth/*`.

| Method | Route | Description |
|--------|-------|-------------|
| `POST` | `/api/auth/login` | Initiate Google OAuth flow |
| `GET` | `/api/auth/callback` | OAuth callback handler |
| `GET` | `/api/auth/me` | Get current user |
| `POST` | `/api/auth/logout` | Logout |
| `POST` | `/api/chat` | Submit task via conversation |
| `POST` | `/api/schedule/generate` | Generate schedule for date range |
| `GET` | `/api/schedule/:date` | Fetch schedule for a specific day |
| `GET` | `/api/schedule/weekly/:start` | Fetch 7-day schedule |
| `PATCH` | `/api/task/:id` | Update task (complete, skip, edit) |
| `DELETE` | `/api/task/:id` | Delete task |
| `POST` | `/api/checkin` | Submit mood & energy check-in |
| `GET` | `/api/calendar/events` | Fetch fixed events from Google Calendar |

## Scheduling Rules

- **Fixed events** are immovable — tasks schedule around them
- **Transit buffers** added before any out-of-home task (via Google Maps API)
- **High-effort tasks** prioritized in morning; low-effort in afternoon/evening
- **Energy scaling** — task count per day adjusted based on energy check-in
- **Daily buffer** — 90 min unscheduled time reserved per day
- **Rollover** — unfinished tasks move to next available slot
- **AI questions** — never more than one clarifying question per exchange

## Task Properties

```typescript
id: string
name: string
deadline: ISO 8601 | null
estimated_hours: number
energy_cost: 'low' | 'medium' | 'high'
requires_transit: boolean
transit_minutes: number
recurrence: 'none' | 'daily' | 'weekly'
category: 'external_commitment' | 'self_care' | 'personal' | 'leisure'
created_at: ISO 8601
completed_at: ISO 8601 | null
```

## Schedule Block Properties

```typescript
id: string
start_time: ISO 8601
end_time: ISO 8601
task_id: string | null
type: 'task' | 'fixed_event' | 'buffer' | 'transit'
notes: string | null
title: string
energy_cost: 'low' | 'medium' | 'high' | null
completed_at: ISO 8601 | null
```

## Authentication

Single-user app with Google OAuth 2.0:
- Session tokens stored in httpOnly cookies
- Validated by Workers middleware on protected routes
- Access tokens cached in D1 for Google Calendar API calls
- Refresh tokens handled automatically

## Development

```bash
# Watch mode for both client & server
npm run dev

# Build production bundle
npm run build

# Deploy to Cloudflare
npm run deploy
npm run deploy:client   # Frontend only
npm run deploy:server   # Backend only
```

## License

Personal project — not licensed.
