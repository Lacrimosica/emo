<script lang="ts">
  import type { Task, EnergyCost, Category } from "$lib/types";

  let { task, block, onSave, onCancel } = $props<{
    task: Task;
    block?: any;
    onSave: (payload: {
      name: string;
      energy_cost: EnergyCost;
      estimated_hours: number;
      category: Category;
      deadline: string | null;
      requires_transit: boolean;
      transit_minutes: number;
      startTime?: string;
      endTime?: string;
    }) => void;
    onCancel: () => void;
  }>();

  let name = $state('');
  let energy_cost = $state<EnergyCost>('medium');
  let estimated_minutes = $state(60);
  let category = $state<Category>('personal');
  let deadline = $state('');
  let requires_transit = $state(false);
  let transit_minutes = $state(30);
  let startTime = $state('');
  let endTime = $state('');

  $effect.pre(() => {
    name = task.name;
    energy_cost = task.energy_cost;
    estimated_minutes = Math.round(task.estimated_hours * 60);
    category = task.category || 'personal';
    deadline = task.deadline ? task.deadline.split('T')[0] : '';
    requires_transit = !!task.requires_transit;
    transit_minutes = task.transit_minutes || 30;

    // Populate time slot from block if available
    if (block) {
      const start = new Date(block.start_time);
      const end = new Date(block.end_time);
      startTime = `${String(start.getHours()).padStart(2,'0')}:${String(start.getMinutes()).padStart(2,'0')}`;
      endTime = `${String(end.getHours()).padStart(2,'0')}:${String(end.getMinutes()).padStart(2,'0')}`;
    }
  });

  function handleSubmit(e: Event) {
    e.preventDefault();
    if (!name.trim()) return;
    onSave({
      name,
      energy_cost,
      estimated_hours: estimated_minutes / 60,
      category,
      deadline: deadline ? new Date(deadline).toISOString() : null,
      requires_transit,
      transit_minutes: requires_transit ? transit_minutes : 0,
      startTime,
      endTime,
    });
  }
</script>

<div class="backdrop" onclick={onCancel} role="presentation">
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="modal card" onclick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" tabindex="-1">
    <div class="modal-header">
      <h2>Edit task</h2>
      <button class="close-btn" onclick={onCancel} aria-label="Close">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
      </button>
    </div>

    <form onsubmit={handleSubmit}>
      <!-- Name -->
      <div class="field">
        <label for="e-name">Task name</label>
        <input id="e-name" type="text" bind:value={name} required placeholder="What needs to be done?" />
      </div>

      <!-- Energy + Duration row -->
      <div class="row-2">
        <div class="field">
          <label for="e-energy">Energy level</label>
          <select id="e-energy" bind:value={energy_cost}>
            <option value="low">Low — easy, routine</option>
            <option value="medium">Medium — focused work</option>
            <option value="high">High — deep / demanding</option>
          </select>
        </div>
        <div class="field">
          <label for="e-hours">
            Duration
            <span class="label-hint">in minutes</span>
          </label>
          <input id="e-hours" type="number" step="5" min="5" bind:value={estimated_minutes} required />
        </div>
      </div>

      <!-- Category + Deadline row -->
      <div class="row-2">
        <div class="field">
          <label for="e-cat">Category</label>
          <select id="e-cat" bind:value={category}>
            <option value="external_commitment">Commitment</option>
            <option value="self_care">Self Care</option>
            <option value="personal">Personal</option>
            <option value="leisure">Leisure</option>
          </select>
        </div>
        <div class="field">
          <label for="e-deadline">Deadline <span class="label-hint">optional</span></label>
          <input id="e-deadline" type="date" bind:value={deadline} />
        </div>
      </div>

      <!-- Transit -->
      <div class="transit-section" class:active={requires_transit}>
        <label class="toggle-row">
          <input type="checkbox" class="sr-only" bind:checked={requires_transit} />
          <div class="toggle" class:on={requires_transit}>
            <div class="toggle-thumb"></div>
          </div>
          <span class="toggle-label">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="3" width="15" height="13" rx="2"/><polygon points="16 8 20 8 23 11 23 16 16 16 16 8"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/></svg>
            Requires travel
          </span>
        </label>
        {#if requires_transit}
          <div class="transit-duration">
            <label for="e-transit-min">Travel time <span class="label-hint">minutes</span></label>
            <input id="e-transit-min" type="number" min="5" step="5" bind:value={transit_minutes} />
          </div>
        {/if}
      </div>

      <!-- Lock time (optional) -->
      <div class="lock-section">
        <span class="lock-label">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          Lock to time slot <span class="label-hint">optional</span>
        </span>
        <div class="row-2">
          <div class="field">
            <label for="e-start">Start</label>
            <input id="e-start" type="time" bind:value={startTime} />
          </div>
          <div class="field">
            <label for="e-end">End</label>
            <input id="e-end" type="time" bind:value={endTime} />
          </div>
        </div>
      </div>

      <div class="modal-footer">
        <button type="button" class="btn-cancel" onclick={onCancel}>Cancel</button>
        <button type="submit" class="btn-save">Save changes</button>
      </div>
    </form>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    backdrop-filter: blur(3px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    padding: var(--spacing-4);
  }

  .modal {
    width: 100%;
    max-width: 460px;
    max-height: 90vh;
    overflow-y: auto;
    padding: var(--spacing-5);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-4);
    animation: modal-in 0.15s ease-out;
  }

  @keyframes modal-in {
    from { opacity: 0; transform: scale(0.97) translateY(8px); }
    to   { opacity: 1; transform: scale(1) translateY(0); }
  }

  .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .modal-header h2 {
    font-size: var(--font-size-lg);
  }

  .close-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 28px;
    height: 28px;
    border-radius: var(--radius-sm);
    color: var(--color-text-tertiary);
    transition: background 0.1s, color 0.1s;
  }
  .close-btn:hover {
    background: var(--color-bg-elevated);
    color: var(--color-text-primary);
  }

  form {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-4);
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .row-2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--spacing-3);
  }

  label {
    font-size: var(--font-size-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    display: flex;
    align-items: center;
    gap: 5px;
  }

  .label-hint {
    font-size: 10px;
    font-weight: 400;
    text-transform: none;
    color: var(--color-text-tertiary);
    letter-spacing: 0;
  }

  input, select {
    padding: 8px 10px;
    border: 1px solid var(--color-border);
    border-radius: var(--radius-sm);
    background: var(--color-bg-elevated);
    color: var(--color-text-primary);
    font-family: inherit;
    font-size: var(--font-size-sm);
    outline: none;
    transition: border-color 0.15s, box-shadow 0.15s;
  }
  input:focus, select:focus {
    border-color: var(--color-accent);
    box-shadow: 0 0 0 3px var(--color-accent-light);
  }

  /* Transit section */
  .transit-section {
    padding: var(--spacing-3);
    border-radius: var(--radius-md);
    border: 1px solid var(--color-border);
    background: var(--color-bg-elevated);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-3);
    transition: border-color 0.15s;
  }
  .transit-section.active {
    border-color: var(--color-transit-border);
    background: var(--color-transit-bg);
  }

  .toggle-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
    cursor: pointer;
    text-transform: none;
    letter-spacing: 0;
    font-size: var(--font-size-sm);
    font-weight: 500;
    color: var(--color-text-primary);
  }

  .sr-only {
    position: absolute;
    width: 1px;
    height: 1px;
    clip: rect(0, 0, 0, 0);
    overflow: hidden;
  }

  .toggle {
    width: 36px;
    height: 20px;
    border-radius: var(--radius-pill);
    background: var(--color-border-strong);
    padding: 2px;
    transition: background 0.2s;
    flex-shrink: 0;
  }
  .toggle.on {
    background: var(--color-accent);
  }
  .toggle-thumb {
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: white;
    box-shadow: var(--shadow-xs);
    transition: transform 0.2s;
  }
  .toggle.on .toggle-thumb {
    transform: translateX(16px);
  }

  .toggle-label {
    display: flex;
    align-items: center;
    gap: 6px;
    color: var(--color-transit);
  }

  .transit-duration {
    display: flex;
    align-items: center;
    gap: var(--spacing-3);
  }
  .transit-duration label {
    white-space: nowrap;
  }
  .transit-duration input {
    width: 90px;
  }

  /* Lock section */
  .lock-section {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-2);
    padding-top: var(--spacing-3);
    border-top: 1px dashed var(--color-border);
  }

  .lock-label {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--font-size-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .modal-footer {
    display: flex;
    justify-content: flex-end;
    gap: var(--spacing-2);
    padding-top: var(--spacing-2);
    border-top: 1px solid var(--color-border);
  }

  .btn-cancel {
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
    padding: 8px 14px;
    border-radius: var(--radius-sm);
    transition: color 0.15s;
  }
  .btn-cancel:hover {
    color: var(--color-text-primary);
  }

  .btn-save {
    font-size: var(--font-size-sm);
    font-weight: 600;
    padding: 8px 18px;
    border-radius: var(--radius-sm);
    background: var(--color-accent);
    color: white;
    transition: background 0.15s;
  }
  .btn-save:hover {
    background: var(--color-accent-hover);
  }
</style>
