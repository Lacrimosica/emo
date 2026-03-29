<script lang="ts">
  import type { ScheduleBlock } from '../types';

  let {
    blocks = [],
    onToggleTask,
    onEditTask,
    onDeleteTask,
    onUnscheduleTask,
    onAddTransit,
  }: {
    blocks: ScheduleBlock[];
    onToggleTask: (taskId: string, currentStatus: boolean) => void;
    onEditTask: (task: any, block?: ScheduleBlock) => void;
    onDeleteTask: (taskId: string) => void;
    onUnscheduleTask: (blockId: string) => void;
    onAddTransit: (start_time: string, duration_minutes: number, notes: string) => void;
  } = $props();

  let showTransitForm = $state(false);
  let transitStart = $state('');
  let transitDuration = $state(30);
  let transitNotes = $state('');

  function formatTime(iso: string) {
    return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function formatDuration(startIso: string, endIso: string) {
    const mins = Math.round((new Date(endIso).getTime() - new Date(startIso).getTime()) / 60000);
    if (mins < 60) return `${mins}m`;
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
  }

  function handleTransitSubmit(e: Event) {
    e.preventDefault();
    if (transitStart && transitDuration > 0) {
      onAddTransit(transitStart, transitDuration, transitNotes || 'Transit');
      showTransitForm = false;
      transitStart = '';
      transitDuration = 30;
      transitNotes = '';
    }
  }
</script>

<div class="timeline">
  {#if blocks.length === 0}
    <div class="empty-state">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="color: var(--color-text-tertiary)"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
      <p>No tasks scheduled yet</p>
    </div>
  {/if}

  {#each blocks as block}
    <div class="block type-{block.type}" class:is-done={!!block.completed_at}>
      <!-- Time column -->
      <div class="time-col">
        <span class="time-start">{formatTime(block.start_time)}</span>
        <div class="time-line"></div>
        <span class="time-end">{formatTime(block.end_time)}</span>
      </div>

      <!-- Content -->
      <div class="block-content">
        <div class="block-top">
          {#if block.type === 'transit'}
            <span class="type-icon transit-icon">
              <!-- car icon -->
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="3" width="15" height="13" rx="2"/><polygon points="16 8 20 8 23 11 23 16 16 16 16 8"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/></svg>
            </span>
          {:else if block.type === 'fixed_event'}
            <span class="type-icon fixed-icon">
              <!-- calendar icon -->
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
            </span>
          {:else if block.task_id}
            <input
              type="checkbox"
              class="task-check"
              checked={!!block.completed_at}
              onchange={() => onToggleTask(block.task_id!, !!block.completed_at)}
            />
          {/if}

          <h4 class="block-title private" class:is-done={!!block.completed_at}>
            {block.title || 'Untitled'}
          </h4>

          {#if block.energy_cost && block.type === 'task'}
            <span class="energy-badge {block.energy_cost}"></span>
          {/if}
        </div>

        <div class="block-meta">
          <span class="duration">{formatDuration(block.start_time, block.end_time)}</span>
          {#if block.notes && block.type === 'transit'}
            <span class="sep">·</span>
            <span class="note">{block.notes}</span>
          {/if}
        </div>

        {#if block.task || (block.type === 'transit' && !block.task_id)}
          <div class="block-actions">
            {#if block.task}
              <button class="action-btn" onclick={() => onEditTask(block.task!, block)} title="Edit">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                Edit
              </button>
              <button class="action-btn" onclick={() => onUnscheduleTask(block.id)} title="Remove from schedule">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="21 8 21 21 3 21 3 8"/><rect x="1" y="3" width="22" height="5"/><line x1="10" y1="12" x2="14" y2="12"/></svg>
                Unschedule
              </button>
              <button class="action-btn danger" onclick={() => onDeleteTask(block.task_id!)} title="Delete task">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>
                Delete
              </button>
            {/if}
            {#if block.type === 'transit' && !block.task_id}
              <button class="action-btn danger" onclick={() => onUnscheduleTask(block.id)} title="Remove transit">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                Remove
              </button>
            {/if}
          </div>
        {/if}
      </div>
    </div>
  {/each}

  <!-- Transit form -->
  {#if showTransitForm}
    <div class="transit-form">
      <span class="form-title">Add transit block</span>
      <form onsubmit={handleTransitSubmit}>
        <div class="form-row">
          <div class="field">
            <label for="tr-start">Start time</label>
            <input id="tr-start" type="time" bind:value={transitStart} required />
          </div>
          <div class="field">
            <label for="tr-dur">Duration (min)</label>
            <input id="tr-dur" type="number" min="5" step="5" bind:value={transitDuration} required />
          </div>
        </div>
        <div class="field">
          <label for="tr-notes">Label</label>
          <input id="tr-notes" type="text" placeholder="e.g. Drive to office" bind:value={transitNotes} />
        </div>
        <div class="form-actions">
          <button type="button" class="btn-ghost" onclick={() => (showTransitForm = false)}>Cancel</button>
          <button type="submit" class="btn-transit">Add transit</button>
        </div>
      </form>
    </div>
  {/if}

  <button
    class="add-transit-btn"
    onclick={() => (showTransitForm = !showTransitForm)}
  >
    {#if !showTransitForm}
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
    {/if}
    {showTransitForm ? 'Cancel' : 'Add transit'}
  </button>
</div>

<style>
  .timeline {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-3);
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-3);
    padding: var(--spacing-8) var(--spacing-4);
    color: var(--color-text-tertiary);
    font-size: var(--font-size-sm);
  }

  /* Block */
  .block {
    display: flex;
    gap: var(--spacing-3);
    background: var(--color-bg-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: var(--spacing-3) var(--spacing-4);
    border-left-width: 3px;
    transition: border-color 0.15s;
  }

  .block.type-task         { border-left-color: var(--color-accent); }
  .block.type-transit      { border-left-color: var(--color-transit); background: var(--color-transit-bg); border-color: var(--color-transit-border); }
  .block.type-fixed_event  { border-left-color: var(--color-fixed); background: var(--color-fixed-bg); border-color: var(--color-fixed-border); }
  .block.type-buffer       { border-left-color: var(--color-border); opacity: 0.6; }
  .block.is-done           { opacity: 0.55; }

  /* Time column */
  .time-col {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 3px;
    min-width: 52px;
    flex-shrink: 0;
  }

  .time-start,
  .time-end {
    font-size: var(--font-size-xs);
    font-weight: 500;
    color: var(--color-text-tertiary);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .time-line {
    flex: 1;
    width: 1px;
    background: var(--color-border);
    border-radius: 999px;
    min-height: 8px;
  }

  /* Content */
  .block-content {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .block-top {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
  }

  .type-icon {
    display: flex;
    align-items: center;
    flex-shrink: 0;
    color: var(--color-text-tertiary);
  }
  .transit-icon { color: var(--color-transit); }
  .fixed-icon   { color: var(--color-fixed); }

  .task-check {
    appearance: none;
    width: 16px;
    height: 16px;
    border: 1.5px solid var(--color-border-strong);
    border-radius: 4px;
    cursor: pointer;
    flex-shrink: 0;
    position: relative;
    transition: background 0.15s, border-color 0.15s;
  }
  .task-check:checked {
    background: var(--color-accent);
    border-color: var(--color-accent);
  }
  .task-check:checked::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 4px;
    width: 5px;
    height: 8px;
    border: 2px solid white;
    border-top: none;
    border-left: none;
    transform: rotate(45deg);
  }

  .block-title {
    font-size: var(--font-size-sm);
    font-weight: 500;
    color: var(--color-text-primary);
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .block-title.is-done {
    text-decoration: line-through;
    color: var(--color-text-tertiary);
  }

  .energy-badge {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }
  .energy-badge.high   { background: var(--color-high); }
  .energy-badge.medium { background: var(--color-medium); }
  .energy-badge.low    { background: var(--color-low); }

  .block-meta {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: var(--font-size-xs);
    color: var(--color-text-tertiary);
  }

  .sep { color: var(--color-border-strong); }

  /* Actions (visible on hover) */
  .block-actions {
    display: flex;
    gap: var(--spacing-1);
    margin-top: 4px;
    opacity: 0;
    transition: opacity 0.15s;
  }
  .block:hover .block-actions {
    opacity: 1;
  }

  .action-btn {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: var(--font-size-xs);
    font-weight: 500;
    padding: 3px 8px;
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    background: var(--color-bg-elevated);
    border: 1px solid var(--color-border);
    transition: background 0.1s, color 0.1s, border-color 0.1s;
  }
  .action-btn:hover {
    background: var(--color-bg-surface);
    color: var(--color-text-primary);
    border-color: var(--color-border-strong);
  }
  .action-btn.danger:hover {
    background: var(--color-high-bg);
    color: var(--color-high);
    border-color: var(--color-high-border);
  }

  /* Transit form */
  .transit-form {
    background: var(--color-bg-surface);
    border: 1px dashed var(--color-transit-border);
    border-radius: var(--radius-lg);
    padding: var(--spacing-4);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-3);
    animation: slide-in 0.12s ease-out;
  }

  @keyframes slide-in {
    from { opacity: 0; transform: translateY(-4px); }
    to   { opacity: 1; transform: translateY(0); }
  }

  .form-title {
    font-size: var(--font-size-sm);
    font-weight: 600;
    color: var(--color-transit);
  }

  .transit-form form {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-3);
  }

  .form-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--spacing-3);
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .field label {
    font-size: var(--font-size-xs);
    font-weight: 500;
    color: var(--color-text-secondary);
  }

  .field input {
    padding: 7px 10px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg-elevated);
    color: var(--color-text-primary);
    font-family: inherit;
    font-size: var(--font-size-sm);
    outline: none;
    transition: border-color 0.15s;
  }
  .field input:focus {
    border-color: var(--color-transit);
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--spacing-2);
  }

  .btn-ghost {
    font-size: var(--font-size-sm);
    color: var(--color-text-tertiary);
    padding: 6px 10px;
    border-radius: var(--radius-sm);
    transition: color 0.15s;
  }
  .btn-ghost:hover {
    color: var(--color-text-primary);
  }

  .btn-transit {
    font-size: var(--font-size-sm);
    font-weight: 500;
    padding: 6px 14px;
    border-radius: var(--radius-sm);
    background: var(--color-transit);
    color: white;
    transition: opacity 0.15s;
  }
  .btn-transit:hover { opacity: 0.88; }

  /* Add transit button */
  .add-transit-btn {
    align-self: flex-start;
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: var(--font-size-xs);
    font-weight: 500;
    color: var(--color-transit);
    padding: 5px 10px;
    border-radius: var(--radius-pill);
    border: 1px dashed var(--color-transit-border);
    background: transparent;
    transition: background 0.15s;
  }
  .add-transit-btn:hover {
    background: var(--color-transit-bg);
  }
</style>
