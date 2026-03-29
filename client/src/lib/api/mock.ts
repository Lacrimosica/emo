import type { Task, Schedule, ScheduleBlock } from '../types';

// Mock Data
const MOCK_TASKS: Task[] = [
  {
    id: 't_1',
    name: 'Doctor Appointment',
    deadline: '2026-03-30T10:00:00Z',
    estimated_hours: 1,
    energy_cost: 'medium',
    requires_transit: true,
    transit_minutes: 30,
    recurrence: 'none',
    category: 'external_commitment',
    created_at: new Date().toISOString(),
    completed_at: null
  },
  {
    id: 't_2',
    name: 'Read 20 pages',
    deadline: null,
    estimated_hours: 0.5,
    energy_cost: 'low',
    requires_transit: false,
    transit_minutes: 0,
    recurrence: 'daily',
    category: 'self_care',
    created_at: new Date().toISOString(),
    completed_at: null
  }
];

const MOCK_BLOCKS: ScheduleBlock[] = [
  {
    id: 'b_1',
    start_time: '2026-03-29T09:00:00Z',
    end_time: '2026-03-29T09:30:00Z',
    task_id: null,
    type: 'transit',
    notes: 'Drive to clinic',
    title: 'Transit to Clinic'
  },
  {
    id: 'b_2',
    start_time: '2026-03-29T09:30:00Z',
    end_time: '2026-03-29T10:30:00Z',
    task_id: 't_1',
    type: 'fixed_event',
    notes: 'Bring ID and insurance card',
    title: 'Doctor Appointment'
  },
  {
    id: 'b_3',
    start_time: '2026-03-29T12:00:00Z',
    end_time: '2026-03-29T12:30:00Z',
    task_id: 't_2',
    type: 'task',
    notes: 'Read atomic habits',
    title: 'Read 20 pages'
  }
];

const MOCK_SCHEDULE: Schedule = {
  date: '2026-03-29',
  energy_level: null, // User needs to check in
  mood: null,
  blocks: MOCK_BLOCKS,
  unscheduled_tasks: MOCK_TASKS
};

// Mock API Service
export class MockAPI {
  static async getSchedule(date: string): Promise<Schedule> {
    return new Promise((resolve) => {
      setTimeout(() => resolve(MOCK_SCHEDULE), 600);
    });
  }

  static async submitCheckIn(mood: number, energy: number): Promise<Schedule> {
    return new Promise((resolve) => {
      setTimeout(() => {
        MOCK_SCHEDULE.mood = mood;
        MOCK_SCHEDULE.energy_level = energy;
        resolve(MOCK_SCHEDULE);
      }, 800);
    });
  }

  static async chat(message: string): Promise<string> {
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve("Does that task need to happen at a specific location, or can you do it from home?");
      }, 1000);
    });
  }
}
