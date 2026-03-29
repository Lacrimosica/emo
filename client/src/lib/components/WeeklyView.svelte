<script lang="ts">
  import type { ScheduleBlock } from '../types';

  let { dates, blocksByDate }: { dates: string[], blocksByDate: Record<string, ScheduleBlock[]> } = $props();

  const MIN_HOUR = 7;
  const MAX_HOUR = 22;
  const TOTAL_HOURS = MAX_HOUR - MIN_HOUR;
  const HOUR_HEIGHT = 56;
  const HEADER_HEIGHT = 44;

  function getPosition(startIso: string, endIso: string) {
    const start = new Date(startIso);
    const end = new Date(endIso);
    let startHour = start.getHours() + start.getMinutes() / 60;
    let endHour = end.getHours() + end.getMinutes() / 60;
    startHour = Math.max(MIN_HOUR, Math.min(MAX_HOUR, startHour));
    endHour = Math.max(MIN_HOUR, Math.min(MAX_HOUR, endHour));
    const heightHours = Math.max(0.25, endHour - startHour);
    return {
      top: (startHour - MIN_HOUR) * HOUR_HEIGHT,
      height: heightHours * HOUR_HEIGHT,
    };
  }

  function formatDayLabel(dateString: string) {
    const d = new Date(`${dateString}T12:00:00Z`);
    return {
      weekday: d.toLocaleDateString('en-US', { weekday: 'short' }),
      date: d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
    };
  }

  function isToday(dateString: string) {
    return dateString === new Date().toISOString().split('T')[0];
  }

  // Current time indicator
  function nowPosition() {
    const now = new Date();
    const h = now.getHours() + now.getMinutes() / 60;
    if (h < MIN_HOUR || h > MAX_HOUR) return null;
    return (h - MIN_HOUR) * HOUR_HEIGHT;
  }

  const hours = Array.from({ length: TOTAL_HOURS + 1 }, (_, i) => i + MIN_HOUR);

  function blockClass(block: ScheduleBlock) {
    if (block.type === 'transit') return 'transit';
    if (block.type === 'fixed_event') return 'fixed';
    if (block.type === 'buffer') return 'buffer';
    return block.task?.energy_cost || 'default';
  }
</script>

<div class="weekly-outer">
  <div class="weekly-scroll">
    <!-- Time ruler -->
    <div class="time-ruler">
      <div class="ruler-header" style="height: {HEADER_HEIGHT}px"></div>
      {#each hours as hr}
        <div class="ruler-cell" style="height: {HOUR_HEIGHT}px">
          {hr < 10 ? '0' + hr : hr}:00
        </div>
      {/each}
    </div>

    <!-- Day columns -->
    {#each dates as d}
      {@const label = formatDayLabel(d)}
      {@const today = isToday(d)}
      {@const nowPos = today ? nowPosition() : null}
      <div class="day-col" class:is-today={today}>
        <div class="day-header" style="height: {HEADER_HEIGHT}px" class:today-header={today}>
          <span class="weekday">{label.weekday}</span>
          <span class="day-date" class:today-date={today}>{label.date}</span>
        </div>
        <div class="day-body" style="height: {TOTAL_HOURS * HOUR_HEIGHT}px">
          <!-- Grid lines -->
          {#each hours as hr}
            <div class="grid-line" style="top: {(hr - MIN_HOUR) * HOUR_HEIGHT}px"></div>
          {/each}

          <!-- Now indicator -->
          {#if nowPos !== null}
            <div class="now-line" style="top: {nowPos}px">
              <div class="now-dot"></div>
            </div>
          {/if}

          <!-- Blocks -->
          {#each (blocksByDate[d] || []) as block}
            {@const pos = getPosition(block.start_time, block.end_time)}
            <div
              class="week-block {blockClass(block)}"
              style="top: {pos.top}px; height: {Math.max(pos.height, 20)}px;"
              title="{block.title}"
              class:done={!!block.completed_at}
            >
              {#if pos.height > 22}
                <span class="block-name">{block.title}</span>
              {/if}
            </div>
          {/each}
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  .weekly-outer {
    flex: 1;
    overflow: hidden;
    background: var(--color-bg-surface);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
  }

  .weekly-scroll {
    display: flex;
    height: 100%;
    overflow-x: auto;
    overflow-y: auto;
  }

  /* Time ruler */
  .time-ruler {
    flex-shrink: 0;
    width: 48px;
    display: flex;
    flex-direction: column;
    border-right: 1px solid var(--color-border);
    background: var(--color-bg-surface);
    position: sticky;
    left: 0;
    z-index: 2;
  }

  .ruler-header {
    flex-shrink: 0;
    border-bottom: 1px solid var(--color-border);
  }

  .ruler-cell {
    flex-shrink: 0;
    display: flex;
    align-items: flex-start;
    justify-content: flex-end;
    padding-right: 8px;
    padding-top: 4px;
    font-size: 10px;
    font-weight: 500;
    color: var(--color-text-tertiary);
    font-variant-numeric: tabular-nums;
    border-bottom: 1px solid var(--color-border);
    box-sizing: border-box;
  }

  /* Day columns */
  .day-col {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-width: 110px;
    border-right: 1px solid var(--color-border);
  }
  .day-col:last-child {
    border-right: none;
  }

  .day-header {
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 2px;
    border-bottom: 1px solid var(--color-border);
    background: var(--color-bg-surface);
    position: sticky;
    top: 0;
    z-index: 1;
  }

  .today-header {
    background: var(--color-accent-light);
    border-bottom-color: var(--color-accent);
  }

  .weekday {
    font-size: var(--font-size-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--color-text-tertiary);
  }

  .day-date {
    font-size: var(--font-size-xs);
    font-weight: 500;
    color: var(--color-text-secondary);
  }
  .today-date {
    color: var(--color-accent);
    font-weight: 700;
  }

  /* Day body */
  .day-body {
    position: relative;
    flex-shrink: 0;
  }

  .grid-line {
    position: absolute;
    left: 0;
    right: 0;
    height: 1px;
    background: var(--color-border);
    opacity: 0.5;
  }

  /* Now line */
  .now-line {
    position: absolute;
    left: 0;
    right: 0;
    height: 1px;
    background: var(--color-high);
    z-index: 3;
    display: flex;
    align-items: center;
  }
  .now-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--color-high);
    flex-shrink: 0;
    margin-left: -4px;
  }

  /* Blocks */
  .week-block {
    position: absolute;
    left: 3px;
    right: 3px;
    border-radius: 5px;
    padding: 3px 5px;
    font-size: 10px;
    font-weight: 500;
    overflow: hidden;
    cursor: default;
    transition: transform 0.1s;
    z-index: 1;
  }
  .week-block:hover {
    transform: scaleX(1.02);
    z-index: 2;
  }

  .week-block.high    { background: var(--color-high-bg);    color: var(--color-high);    border: 1px solid var(--color-high-border); }
  .week-block.medium  { background: var(--color-medium-bg);  color: var(--color-medium);  border: 1px solid var(--color-medium-border); }
  .week-block.low     { background: var(--color-low-bg);     color: var(--color-low);     border: 1px solid var(--color-low-border); }
  .week-block.transit { background: var(--color-transit-bg); color: var(--color-transit); border: 1px solid var(--color-transit-border); }
  .week-block.fixed   { background: var(--color-fixed-bg);   color: var(--color-fixed);   border: 1px solid var(--color-fixed-border); }
  .week-block.buffer  { background: var(--color-bg-elevated); color: var(--color-text-tertiary); border: 1px solid var(--color-border); opacity: 0.6; }
  .week-block.default { background: var(--color-accent-light); color: var(--color-accent); border: 1px solid var(--color-border); }

  .week-block.done {
    opacity: 0.4;
    text-decoration: line-through;
  }

  .block-name {
    display: -webkit-box;
    -webkit-line-clamp: 3;
    line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
    line-height: 1.3;
  }
</style>
