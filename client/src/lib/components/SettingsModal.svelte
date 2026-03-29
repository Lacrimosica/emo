<script lang="ts">
  let { settings, onSave, onClose } = $props<{
    settings: { minimum_chunk_minutes: number; privacy_mode: boolean };
    onSave: (payload: { minimum_chunk_minutes: number; privacy_mode: boolean }) => void;
    onClose: () => void;
  }>();

  let minChunk = $state(0);
  let privacyMode = $state(false);
  $effect.pre(() => {
    minChunk = settings.minimum_chunk_minutes || 30;
    privacyMode = settings.privacy_mode ?? false;
  });
</script>

<div class="backdrop" onclick={onClose} role="presentation">
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="modal card" onclick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" tabindex="-1">
    <div class="modal-header">
      <h2>Settings</h2>
      <button class="close-btn" onclick={onClose} aria-label="Close">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
      </button>
    </div>

    <div class="fields">
      <!-- Min chunk -->
      <div class="field-group">
        <div class="field-label">
          <span class="label-main">Minimum task chunk</span>
          <span class="label-sub">Smallest slot the auto-scheduler will use</span>
        </div>
        <div class="number-input">
          <button type="button" aria-label="Decrease" onclick={() => (minChunk = Math.max(5, minChunk - 5))}>−</button>
          <span class="number-val">{minChunk}<span class="unit">min</span></span>
          <button type="button" aria-label="Increase" onclick={() => (minChunk = Math.min(120, minChunk + 5))}>+</button>
        </div>
      </div>

      <!-- Privacy -->
      <div class="field-group">
        <div class="field-label">
          <span class="label-main">Privacy mode</span>
          <span class="label-sub">Blurs task names — hover to reveal</span>
        </div>
        <button
          class="toggle"
          class:on={privacyMode}
          onclick={() => (privacyMode = !privacyMode)}
          role="switch"
          aria-checked={privacyMode}
          aria-label="Toggle privacy mode"
        >
          <span class="toggle-thumb"></span>
        </button>
      </div>
    </div>

    <div class="footer">
      <button class="btn-cancel" onclick={onClose}>Cancel</button>
      <button
        class="btn-save"
        onclick={() => onSave({ minimum_chunk_minutes: minChunk, privacy_mode: privacyMode })}
      >
        Save
      </button>
    </div>
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
    max-width: 400px;
    padding: var(--spacing-5);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-5);
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

  h2 { font-size: var(--font-size-lg); }

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

  .fields {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-1);
  }

  .field-group {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--spacing-4);
    padding: var(--spacing-3) var(--spacing-4);
    border-radius: var(--radius-md);
    background: var(--color-bg-elevated);
    border: 1px solid var(--color-border);
  }

  .field-label {
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .label-main {
    font-size: var(--font-size-sm);
    font-weight: 500;
    color: var(--color-text-primary);
  }

  .label-sub {
    font-size: var(--font-size-xs);
    color: var(--color-text-tertiary);
  }

  /* Number stepper */
  .number-input {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
    flex-shrink: 0;
  }

  .number-input button {
    width: 28px;
    height: 28px;
    border-radius: var(--radius-sm);
    border: 1px solid var(--color-border);
    background: var(--color-bg-surface);
    font-size: 1.1rem;
    line-height: 1;
    color: var(--color-text-secondary);
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.1s, color 0.1s;
  }
  .number-input button:hover {
    background: var(--color-accent-light);
    color: var(--color-accent);
    border-color: var(--color-accent);
  }

  .number-val {
    font-size: var(--font-size-sm);
    font-weight: 600;
    min-width: 52px;
    text-align: center;
    color: var(--color-text-primary);
  }

  .unit {
    font-size: var(--font-size-xs);
    font-weight: 400;
    color: var(--color-text-tertiary);
    margin-left: 2px;
  }

  /* Toggle */
  .toggle {
    width: 40px;
    height: 22px;
    border-radius: var(--radius-pill);
    background: var(--color-border-strong);
    padding: 2px;
    transition: background 0.2s;
    flex-shrink: 0;
    cursor: pointer;
  }
  .toggle.on {
    background: var(--color-accent);
  }
  .toggle-thumb {
    display: block;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: white;
    box-shadow: var(--shadow-xs);
    transition: transform 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }
  .toggle.on .toggle-thumb {
    transform: translateX(18px);
  }

  .footer {
    display: flex;
    justify-content: flex-end;
    gap: var(--spacing-2);
    padding-top: var(--spacing-3);
    border-top: 1px solid var(--color-border);
  }

  .btn-cancel {
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
    padding: 8px 14px;
    border-radius: var(--radius-sm);
    transition: color 0.15s;
  }
  .btn-cancel:hover { color: var(--color-text-primary); }

  .btn-save {
    font-size: var(--font-size-sm);
    font-weight: 600;
    padding: 8px 18px;
    border-radius: var(--radius-sm);
    background: var(--color-accent);
    color: white;
    transition: background 0.15s;
  }
  .btn-save:hover { background: var(--color-accent-hover); }
</style>
