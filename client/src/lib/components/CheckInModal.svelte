<script lang="ts">
  let { onSubmit }: { onSubmit: (mood: number, energy: number) => void } = $props();

  let mood = $state(3);
  let energy = $state(3);

  const moodLabels = ['', 'Rough', 'Low', 'Okay', 'Good', 'Great'];
  const energyLabels = ['', 'Drained', 'Tired', 'Neutral', 'Alert', 'Energised'];
  const moodEmoji = ['', '😞', '😕', '😐', '🙂', '😄'];
  const energyEmoji = ['', '🪫', '😴', '⚡', '🔥', '🚀'];
</script>

<div class="backdrop">
  <div class="modal card">
    <div class="modal-top">
      <h2>Daily check-in</h2>
      <p class="subtitle">How are you showing up today?</p>
    </div>

    <div class="sliders">
      <!-- Mood -->
      <div class="slider-group">
        <div class="slider-header">
          <span class="slider-label">Mood</span>
          <span class="slider-value">
            <span class="emoji">{moodEmoji[mood]}</span>
            {moodLabels[mood]}
          </span>
        </div>
        <div class="track-wrap">
          <input type="range" min="1" max="5" step="1" bind:value={mood} class="slider" />
          <div class="track-fill" style="width: {((mood - 1) / 4) * 100}%"></div>
        </div>
        <div class="scale">
          {#each [1,2,3,4,5] as n}
            <button
              type="button"
              class="scale-pip"
              class:active={mood === n}
              onclick={() => (mood = n)}
              aria-label={moodLabels[n]}
            ></button>
          {/each}
        </div>
      </div>

      <!-- Energy -->
      <div class="slider-group">
        <div class="slider-header">
          <span class="slider-label">Energy</span>
          <span class="slider-value">
            <span class="emoji">{energyEmoji[energy]}</span>
            {energyLabels[energy]}
          </span>
        </div>
        <div class="track-wrap">
          <input type="range" min="1" max="5" step="1" bind:value={energy} class="slider" />
          <div class="track-fill energy" style="width: {((energy - 1) / 4) * 100}%"></div>
        </div>
        <div class="scale">
          {#each [1,2,3,4,5] as n}
            <button
              type="button"
              class="scale-pip energy-pip"
              class:active={energy === n}
              onclick={() => (energy = n)}
              aria-label={energyLabels[n]}
            ></button>
          {/each}
        </div>
      </div>
    </div>

    <button class="start-btn" onclick={() => onSubmit(mood, energy)}>
      Start my day
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>
    </button>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(4px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 200;
    padding: var(--spacing-4);
  }

  .modal {
    width: 100%;
    max-width: 400px;
    padding: var(--spacing-6);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-6);
    animation: modal-in 0.15s ease-out;
  }

  @keyframes modal-in {
    from { opacity: 0; transform: scale(0.96) translateY(10px); }
    to   { opacity: 1; transform: scale(1) translateY(0); }
  }

  .modal-top {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  h2 {
    font-size: var(--font-size-xl);
    font-weight: 700;
  }

  .subtitle {
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
  }

  .sliders {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-6);
  }

  .slider-group {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-2);
  }

  .slider-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .slider-label {
    font-size: var(--font-size-sm);
    font-weight: 600;
    color: var(--color-text-primary);
  }

  .slider-value {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
    font-weight: 500;
  }

  .emoji {
    font-size: 1.1rem;
  }

  /* Slider */
  .track-wrap {
    position: relative;
    height: 6px;
    background: var(--color-bg-elevated);
    border-radius: var(--radius-pill);
    overflow: visible;
  }

  .track-fill {
    position: absolute;
    top: 0;
    left: 0;
    height: 100%;
    border-radius: var(--radius-pill);
    background: var(--color-accent);
    pointer-events: none;
    transition: width 0.1s;
  }
  .track-fill.energy {
    background: var(--color-low);
  }

  .slider {
    position: absolute;
    inset: 0;
    width: 100%;
    margin: 0;
    opacity: 0;
    cursor: pointer;
    height: 100%;
    z-index: 1;
  }

  /* Scale pips */
  .scale {
    display: flex;
    justify-content: space-between;
    padding: 0 2px;
  }

  .scale-pip {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--color-border-strong);
    border: none;
    cursor: pointer;
    transition: background 0.15s, transform 0.15s;
  }
  .scale-pip.active {
    background: var(--color-accent);
    transform: scale(1.3);
  }
  .energy-pip.active {
    background: var(--color-low);
  }

  .start-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-2);
    width: 100%;
    padding: 12px var(--spacing-5);
    background: var(--color-accent);
    color: white;
    font-size: var(--font-size-base);
    font-weight: 600;
    border-radius: var(--radius-md);
    transition: background 0.15s, transform 0.1s;
  }
  .start-btn:hover {
    background: var(--color-accent-hover);
    transform: translateY(-1px);
  }
  .start-btn:active {
    transform: translateY(0);
  }
</style>
