import type { Schedule, ScheduleBlock, Task } from '../types';

export class API {
  static async getSchedule(dateStr: string): Promise<Schedule> {
    const res = await fetch(`/api/schedule/${dateStr}`);
    if (!res.ok) throw new Error('Failed to fetch schedule');
    return res.json();
  }

  static async getWeeklySchedule(startDateStr: string): Promise<{ dates: string[], blocksByDate: Record<string, ScheduleBlock[]> }> {
    const res = await fetch(`/api/schedule/weekly/${startDateStr}`);
    if (!res.ok) throw new Error('Failed to fetch weekly schedule');
    return res.json();
  }

  static async syncCalendar(dateStr: string): Promise<void> {
    const res = await fetch(`/api/schedule/sync-calendar/${dateStr}`, { method: 'POST' });
    if (res.status === 401) {
      window.location.href = '/api/auth/login';
      return;
    }
    if (!res.ok) throw new Error('Failed to sync calendar');
    return res.json();
  }

  static async unscheduleBlock(blockId: string): Promise<void> {
    const res = await fetch(`/api/schedule/block/${blockId}`, { method: 'DELETE' });
    if (!res.ok) throw new Error('Failed to unschedule block');
    return res.json();
  }

  static async addTransitBlock(date: string, start_time: string, duration_minutes: number, notes: string): Promise<void> {
    const res = await fetch(`/api/schedule/${date}/transit`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ start_time, duration_minutes, notes })
    });
    if (!res.ok) throw new Error('Failed to add transit block');
    return res.json();
  }

  static async logout(): Promise<void> {
    await fetch('/api/auth/logout', { method: 'POST' });
    window.location.href = '/login';
  }

  static async getSettings(): Promise<{ minimum_chunk_minutes: number; privacy_mode: boolean }> {
    const res = await fetch('/api/settings');
    if (!res.ok) throw new Error('Failed to fetch settings');
    const data = await res.json();
    // Ensure defaults for fields that may be missing from older stored settings
    return { minimum_chunk_minutes: 30, privacy_mode: false, ...data };
  }

  static async updateSettings(settings: { minimum_chunk_minutes: number; privacy_mode: boolean }): Promise<void> {
    const res = await fetch('/api/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(settings)
    });
    if (!res.ok) throw new Error('Failed to update settings');
    return res.json();
  }

  static async submitCheckIn(mood: number, energy: number, date: string): Promise<Schedule> {
    const res = await fetch(`/api/checkin`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mood, energy, date }),
    });

    if (!res.ok) throw new Error('Checkin failed');

    // In Phase 3, we simply refetch the schedule state after checking in.
    return API.getSchedule(date);
  }

  static async chat(history: { role: string, text: string }[]): Promise<string> {
    const res = await fetch(`/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ history }),
    });

    if (!res.ok) throw new Error('Chat failed');
    const data = await res.json();
    return data.response;
  }

  static async createTask(payload: any): Promise<string> {
    const res = await fetch('/api/task', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (!res.ok) throw new Error('Task creation failed');
    const data = await res.json();
    return data.id;
  }

  static async updateTask(id: string, payload: any): Promise<void> {
    const res = await fetch(`/api/task/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (!res.ok) throw new Error('Task update failed');
  }

  static async deleteTask(id: string): Promise<void> {
    const res = await fetch(`/api/task/${id}`, {
      method: 'DELETE'
    });
    if (!res.ok) throw new Error('Task deletion failed');
  }

  static async scheduleTask(id: string, date: string, start_time: string, end_time: string): Promise<void> {
    const res = await fetch(`/api/schedule/${date}/task/${id}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ start_time, end_time })
    });
    if (!res.ok) throw new Error('Task scheduling failed');
  }

  static async generateSchedule(date: string): Promise<void> {
    const res = await fetch(`/api/schedule/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ date })
    });
    if (!res.ok) throw new Error('Generation failed');
  }
}
