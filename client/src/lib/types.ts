export type EnergyCost = 'low' | 'medium' | 'high';
export type Recurrence = 'none' | 'daily' | 'weekly';
export type Category = 'external_commitment' | 'self_care' | 'personal' | 'leisure';
export type BlockType = 'task' | 'fixed_event' | 'buffer' | 'transit';

export interface Task {
  id: string;
  name: string;
  deadline: string | null; // ISO Date String
  estimated_hours: number;
  energy_cost: EnergyCost;
  requires_transit: boolean;
  transit_minutes: number;
  recurrence: Recurrence;
  category: Category;
  created_at: string;
  completed_at: string | null;
}

export interface ScheduleBlock {
  id: string;
  start_time: string; // ISO DateTime
  end_time: string; // ISO DateTime
  task_id: string | null;
  type: BlockType;
  notes: string;
  title?: string; // Derived for UI convenience
  energy_cost?: EnergyCost; // Pulled from linked task
  completed_at?: string | null;
  task?: Task;
}

export interface Schedule {
  date: string; // YYYY-MM-DD
  energy_level: number | null; // 1-5
  mood: number | null; // 1-5
  blocks: ScheduleBlock[];
  unscheduled_tasks: Task[];
}
