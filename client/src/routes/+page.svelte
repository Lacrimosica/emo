<script lang="ts">
  import { onMount, tick } from "svelte";
  import { API } from "$lib/api";
  import type { Schedule, Task } from "$lib/types";
  import CheckInModal from "$lib/components/CheckInModal.svelte";
  import ScheduleTimeline from "$lib/components/ScheduleTimeline.svelte";
  import EditTaskModal from "$lib/components/EditTaskModal.svelte";
  import SettingsModal from "$lib/components/SettingsModal.svelte";
  import WeeklyView from "$lib/components/WeeklyView.svelte";
  import ConfirmModal from "$lib/components/ConfirmModal.svelte";
  import type { EnergyCost, Category, ScheduleBlock } from "$lib/types";

  let schedule = $state<Schedule | null>(null);
  let currentView = $state<"today" | "weekly">("today");
  let weeklyData = $state<{ dates: string[]; blocksByDate: Record<string, ScheduleBlock[]> } | null>(null);
  let loading = $state(true);

  let showSettings = $state(false);
  let globalSettings = $state<{ minimum_chunk_minutes: number; privacy_mode: boolean }>({
    minimum_chunk_minutes: 30,
    privacy_mode: false,
  });

  // Confirm modal
  let confirmModal = $state<{ title: string; message: string; onConfirm: () => void } | null>(null);

  // Chat
  let isChatting = $state(false);
  let chatHistory = $state<{ role: "user" | "ai"; text: string }[]>([]);
  let chatContainerEl = $state<HTMLElement | null>(null);
  let inputMessage = $state("");
  let aiTyping = $state(false);

  const _now = new Date();
  let todayISO = `${_now.getFullYear()}-${String(_now.getMonth() + 1).padStart(2, "0")}-${String(_now.getDate()).padStart(2, "0")}`;
  let editingTask = $state<Task | null>(null);
  let editingBlock = $state<ScheduleBlock | null>(null);
  let currentClock = $state(new Date());

  // Category labels and order
  const CATEGORY_META: Record<string, { label: string; color: string }> = {
    external_commitment: { label: "Commitments", color: "var(--color-fixed)" },
    self_care: { label: "Self Care", color: "var(--color-low)" },
    personal: { label: "Personal", color: "var(--color-accent)" },
    leisure: { label: "Leisure", color: "var(--color-medium)" },
  };
  const CATEGORY_ORDER = ["external_commitment", "self_care", "personal", "leisure"];

  // Group unscheduled tasks by category
  const groupedTasks = $derived(() => {
    if (!schedule?.unscheduled_tasks?.length) return [];
    const groups: { key: string; label: string; color: string; tasks: Task[] }[] = [];
    for (const cat of CATEGORY_ORDER) {
      const tasks = schedule.unscheduled_tasks.filter((t) => (t.category || "personal") === cat);
      if (tasks.length > 0) {
        groups.push({ key: cat, ...CATEGORY_META[cat], tasks });
      }
    }
    return groups;
  });

  // Urgency label for deadline
  function urgencyLabel(deadline: string | null): string | null {
    if (!deadline) return null;
    const days = Math.ceil((new Date(deadline).getTime() - Date.now()) / 86400000);
    if (days < 0) return "overdue";
    if (days === 0) return "today";
    if (days === 1) return "tomorrow";
    if (days <= 7) return `${days}d`;
    return null;
  }

  // Auto-scroll chat to bottom when history changes
  $effect(() => {
    chatHistory.length;
    aiTyping;
    tick().then(() => {
      if (chatContainerEl) {
        chatContainerEl.scrollTop = chatContainerEl.scrollHeight;
      }
    });
  });

  onMount(() => {
    const timer = setInterval(() => { currentClock = new Date(); }, 1000);
    API.getSettings().then((s) => (globalSettings = s)).catch(console.error);
    API.getSchedule(todayISO).then((s) => { schedule = s; loading = false; });
    return () => clearInterval(timer);
  });

  async function handleCheckIn(mood: number, energy: number) {
    loading = true;
    schedule = await API.submitCheckIn(mood, energy, todayISO);
    loading = false;
  }

  async function sendMessage() {
    const text = inputMessage.trim();
    if (!text) return;
    inputMessage = "";

    if (!isChatting) chatHistory = [];
    isChatting = true;
    chatHistory = [...chatHistory, { role: "user", text }];
    aiTyping = true;

    const plainHistory = chatHistory.map((h) => ({ role: h.role, text: h.text }));
    const response = await API.chat(plainHistory as any);
    aiTyping = false;

    let resolvedTask = null;
    try {
      if (response.includes("{")) {
        const raw = response.substring(response.indexOf("{"));
        const parsed = JSON.parse(raw);
        if (parsed.ready && parsed.task) resolvedTask = parsed.task;
      }
    } catch (_) {}

    if (resolvedTask) {
      await API.createTask(resolvedTask);
      schedule = await API.getSchedule(todayISO);
      isChatting = false;
      chatHistory = [];
    } else {
      chatHistory = [...chatHistory, { role: "ai", text: response }];
    }
  }

  function handleChatKeydown(e: KeyboardEvent) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  }

  function cancelChat() {
    isChatting = false;
    chatHistory = [];
    inputMessage = "";
  }

  async function handleDeleteTask(id: string) {
    confirmModal = {
      title: "Delete task?",
      message: "This will permanently remove this task and all associated scheduling. This action cannot be undone.",
      onConfirm: async () => {
        await API.deleteTask(id);
        schedule = await API.getSchedule(todayISO);
        confirmModal = null;
      }
    };
  }

  async function handleSaveTask(payload: {
    name: string;
    energy_cost: EnergyCost;
    estimated_hours: number;
    category: Category;
    deadline: string | null;
    requires_transit: boolean;
    transit_minutes: number;
    startTime?: string;
    endTime?: string;
  }) {
    if (!editingTask) return;
    await API.updateTask(editingTask.id, {
      name: payload.name,
      energy_cost: payload.energy_cost,
      estimated_hours: payload.estimated_hours,
      category: payload.category,
      deadline: payload.deadline,
      requires_transit: payload.requires_transit,
      transit_minutes: payload.transit_minutes,
    });
    if (payload.startTime && payload.endTime) {
      await API.scheduleTask(editingTask.id, todayISO, payload.startTime, payload.endTime);
    }
    editingTask = null;
    editingBlock = null;
    schedule = await API.getSchedule(todayISO);
  }

  async function handleGenerateSchedule() {
    loading = true;
    try {
      await API.generateSchedule(todayISO);
      schedule = await API.getSchedule(todayISO);
    } catch (e) { console.error(e); }
    loading = false;
  }

  async function handleToggleTask(taskId: string, isCompleted: boolean) {
    await API.updateTask(taskId, { completed: !isCompleted });
    schedule = await API.getSchedule(todayISO);
  }

  async function toggleView(view: "today" | "weekly") {
    currentView = view;
    if (view === "weekly" && !weeklyData) {
      loading = true;
      weeklyData = await API.getWeeklySchedule(todayISO);
      loading = false;
    }
  }

  async function handleSyncCalendar() {
    loading = true;
    try {
      await API.syncCalendar(todayISO);
      schedule = await API.getSchedule(todayISO);
      weeklyData = await API.getWeeklySchedule(todayISO);
    } catch (e) { console.error(e); }
    loading = false;
  }

  async function handleUnscheduleTask(blockId: string) {
    loading = true;
    try {
      await API.unscheduleBlock(blockId);
      schedule = await API.getSchedule(todayISO);
      if (currentView === "weekly") weeklyData = await API.getWeeklySchedule(todayISO);
    } catch (e) { console.error(e); }
    loading = false;
  }

  async function handleSaveSettings(payload: { minimum_chunk_minutes: number; privacy_mode: boolean }) {
    await API.updateSettings(payload);
    globalSettings = payload;
    showSettings = false;
  }

  async function handleAddTransit(start_time: string, duration_minutes: number, notes: string) {
    loading = true;
    try {
      await API.addTransitBlock(todayISO, start_time, duration_minutes, notes);
      schedule = await API.getSchedule(todayISO);
    } catch (e) { console.error(e); }
    loading = false;
  }
</script>

<svelte:head>
  <title>emo — your day</title>
</svelte:head>

<!-- Check-in gate (non-blocking overlay) -->
{#if schedule && schedule.energy_level === null}
  <CheckInModal onSubmit={handleCheckIn} />
{/if}

<div class="page" class:privacy-mode={globalSettings.privacy_mode}>
  <!-- Top bar -->
  <div class="topbar">
    <div class="tabs">
      <button class="tab" class:active={currentView === "today"} onclick={() => toggleView("today")}>
        Today
      </button>
      <button class="tab" class:active={currentView === "weekly"} onclick={() => toggleView("weekly")}>
        Week
      </button>
    </div>

    <div class="topbar-right">
      {#if loading}
        <span class="loading-dot"></span>
      {/if}
      <button class="icon-btn" onclick={handleSyncCalendar} title="Sync Google Calendar">
        <!-- sync icon -->
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
      </button>
      <button class="icon-btn" onclick={() => (showSettings = true)} title="Settings">
        <!-- gear icon -->
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
      </button>
    </div>
  </div>

  {#if currentView === "today"}
    <div class="dashboard">
      <!-- Left: Timeline -->
      <div class="timeline-col">
        <div class="col-header">
          <div>
            <h2 class="col-title">
              {new Date().toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" })}
            </h2>
            <p class="col-subtitle">Today's schedule</p>
          </div>
          <div class="clock">
            {currentClock.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
          </div>
        </div>

        {#if schedule}
          <ScheduleTimeline
            blocks={schedule.blocks}
            onToggleTask={handleToggleTask}
            onEditTask={(t, b) => { editingTask = t; editingBlock = b; }}
            onDeleteTask={handleDeleteTask}
            onUnscheduleTask={handleUnscheduleTask}
            onAddTransit={handleAddTransit}
          />
        {/if}
      </div>

      <!-- Right: Sidebar -->
      <div class="sidebar">

        <!-- Backlog -->
        <div class="sidebar-section backlog-section">
          <div class="section-header">
            <span class="section-title">Backlog</span>
            <button class="pill-btn accent" onclick={handleGenerateSchedule} title="Auto-schedule tasks">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
              Auto-fill
            </button>
          </div>

          {#if schedule && groupedTasks().length > 0}
            <div class="task-groups">
              {#each groupedTasks() as group}
                <div class="task-group">
                  <div class="group-label" style="--group-color: {group.color}">
                    <span class="group-dot"></span>
                    {group.label}
                    <span class="group-count">{group.tasks.length}</span>
                  </div>
                  {#each group.tasks as task}
                    {@const urgency = urgencyLabel(task.deadline)}
                    <div class="task-row">
                      <input
                        type="checkbox"
                        class="task-check"
                        checked={!!task.completed_at}
                        onchange={() => handleToggleTask(task.id, !!task.completed_at)}
                      />
                      <div class="task-body">
                        <span class="task-name private" class:done={!!task.completed_at}>{task.name}</span>
                        <div class="task-meta">
                          <span class="energy-dot {task.energy_cost}"></span>
                          <span class="meta-text">{Math.round(task.estimated_hours * 60)}min</span>
                          {#if urgency}
                            <span class="urgency-tag" class:overdue={urgency === 'overdue'}>{urgency}</span>
                          {/if}
                        </div>
                      </div>
                      <div class="task-actions">
                        <button class="row-btn" onclick={() => { editingTask = task; editingBlock = undefined; }} title="Edit">
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                        </button>
                        <button class="row-btn danger" onclick={() => handleDeleteTask(task.id)} title="Delete">
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>
                        </button>
                      </div>
                    </div>
                  {/each}
                </div>
              {/each}
            </div>
          {:else if schedule}
            <p class="empty-msg">All tasks are scheduled or completed.</p>
          {/if}
        </div>

        <!-- Chat -->
        {#if schedule && schedule.energy_level !== null}
          <div class="sidebar-section chat-section">
            <div class="section-header">
              <span class="section-title">Add task</span>
              {#if isChatting}
                <button class="ghost-btn" onclick={cancelChat}>Cancel</button>
              {/if}
            </div>

            {#if isChatting && chatHistory.length > 0}
              <div class="chat-history" bind:this={chatContainerEl}>
                {#each chatHistory as msg}
                  <div class="bubble {msg.role}">
                    <span class="private">{msg.text}</span>
                  </div>
                {/each}
                {#if aiTyping}
                  <div class="bubble ai typing">
                    <span class="dot-1"></span><span class="dot-2"></span><span class="dot-3"></span>
                  </div>
                {/if}
              </div>
            {/if}

            <div class="chat-input-row">
              <input
                class="chat-input"
                type="text"
                bind:value={inputMessage}
                onkeydown={handleChatKeydown}
                placeholder={isChatting ? "Reply..." : "What do you need to do?"}
                disabled={aiTyping}
              />
              <button class="send-btn" onclick={sendMessage} disabled={aiTyping || !inputMessage.trim()} aria-label="Send">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>
              </button>
            </div>
          </div>
        {/if}
      </div>
    </div>

  {:else if weeklyData}
    <div class="weekly-wrapper">
      <WeeklyView dates={weeklyData.dates} blocksByDate={weeklyData.blocksByDate} />
    </div>
  {/if}
</div>

{#if editingTask}
  <EditTaskModal task={editingTask} block={editingBlock} onSave={handleSaveTask} onCancel={() => { editingTask = null; editingBlock = null; }} />
{/if}

{#if showSettings}
  <SettingsModal settings={globalSettings} onSave={handleSaveSettings} onClose={() => (showSettings = false)} />
{/if}

{#if confirmModal}
  <ConfirmModal
    title={confirmModal.title}
    message={confirmModal.message}
    onConfirm={confirmModal.onConfirm}
    onCancel={() => (confirmModal = null)}
  />
{/if}

<style>
  .page {
    display: flex;
    flex-direction: column;
    height: 100%;
    overflow: hidden;
  }

  /* Top bar */
  .topbar {
    flex-shrink: 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: var(--spacing-3) var(--spacing-5);
    border-bottom: 1px solid var(--color-border);
    background: var(--color-bg-surface);
    gap: var(--spacing-4);
  }

  .tabs {
    display: flex;
    gap: var(--spacing-1);
    background: var(--color-bg-elevated);
    border-radius: var(--radius-md);
    padding: 3px;
  }

  .tab {
    padding: 5px 14px;
    border-radius: var(--radius-sm);
    font-size: var(--font-size-sm);
    font-weight: 500;
    color: var(--color-text-secondary);
    transition: background 0.15s, color 0.15s;
  }
  .tab.active {
    background: var(--color-bg-surface);
    color: var(--color-text-primary);
    box-shadow: var(--shadow-xs);
  }

  .topbar-right {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
  }

  .loading-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--color-accent);
    animation: pulse 1.2s ease-in-out infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 0.3; transform: scale(0.8); }
    50% { opacity: 1; transform: scale(1); }
  }

  .icon-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    transition: background 0.15s, color 0.15s;
  }
  .icon-btn:hover {
    background: var(--color-bg-elevated);
    color: var(--color-text-primary);
  }

  /* Dashboard grid */
  .dashboard {
    flex: 1;
    display: grid;
    grid-template-columns: 1fr;
    overflow: hidden;
  }

  @media (min-width: 820px) {
    .dashboard {
      grid-template-columns: 1fr 360px;
    }
  }

  /* Timeline column */
  .timeline-col {
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    padding: var(--spacing-5);
    gap: var(--spacing-4);
    border-right: 1px solid var(--color-border);
  }

  .col-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    flex-shrink: 0;
  }

  .col-title {
    font-size: var(--font-size-lg);
    font-weight: 600;
  }

  .col-subtitle {
    font-size: var(--font-size-sm);
    color: var(--color-text-tertiary);
    margin-top: 2px;
  }

  .clock {
    font-variant-numeric: tabular-nums;
    font-size: var(--font-size-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    background: var(--color-bg-elevated);
    padding: 4px 10px;
    border-radius: var(--radius-pill);
    border: 1px solid var(--color-border);
  }

  /* Sidebar */
  .sidebar {
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .sidebar-section {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-3);
    padding: var(--spacing-4) var(--spacing-4);
    border-bottom: 1px solid var(--color-border);
  }

  .backlog-section {
    flex: 1;
    overflow-y: auto;
    min-height: 0;
  }

  .chat-section {
    flex-shrink: 0;
  }

  .section-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-shrink: 0;
  }

  .section-title {
    font-size: var(--font-size-sm);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .pill-btn {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: var(--font-size-xs);
    font-weight: 600;
    padding: 5px 10px;
    border-radius: var(--radius-pill);
    border: 1px solid var(--color-border);
    color: var(--color-text-secondary);
    transition: background 0.15s, color 0.15s, border-color 0.15s;
  }
  .pill-btn.accent {
    background: var(--color-accent-light);
    border-color: var(--color-accent);
    color: var(--color-accent);
  }
  .pill-btn.accent:hover {
    background: var(--color-accent);
    color: white;
  }

  .ghost-btn {
    font-size: var(--font-size-xs);
    color: var(--color-text-tertiary);
    padding: 2px 6px;
    border-radius: var(--radius-sm);
    transition: color 0.15s;
  }
  .ghost-btn:hover {
    color: var(--color-text-primary);
  }

  /* Task groups */
  .task-groups {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-4);
  }

  .task-group {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-1);
  }

  .group-label {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: var(--font-size-xs);
    font-weight: 600;
    color: var(--color-text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    margin-bottom: 4px;
  }

  .group-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--group-color, var(--color-accent));
    flex-shrink: 0;
  }

  .group-count {
    margin-left: auto;
    background: var(--color-bg-elevated);
    border-radius: var(--radius-pill);
    padding: 1px 6px;
    font-size: 10px;
    color: var(--color-text-tertiary);
  }

  .task-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
    padding: 7px 10px;
    border-radius: var(--radius-md);
    background: var(--color-bg-elevated);
    border: 1px solid transparent;
    transition: border-color 0.15s;
  }
  .task-row:hover {
    border-color: var(--color-border);
  }

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

  .task-body {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .task-name {
    font-size: var(--font-size-sm);
    font-weight: 500;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .task-name.done {
    text-decoration: line-through;
    color: var(--color-text-tertiary);
  }

  .task-meta {
    display: flex;
    align-items: center;
    gap: 5px;
  }

  .energy-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }
  .energy-dot.high   { background: var(--color-high); }
  .energy-dot.medium { background: var(--color-medium); }
  .energy-dot.low    { background: var(--color-low); }

  .meta-text {
    font-size: var(--font-size-xs);
    color: var(--color-text-tertiary);
  }

  .urgency-tag {
    font-size: 10px;
    font-weight: 600;
    padding: 1px 5px;
    border-radius: var(--radius-pill);
    background: var(--color-medium-bg);
    color: var(--color-medium);
    border: 1px solid var(--color-medium-border);
  }
  .urgency-tag.overdue {
    background: var(--color-high-bg);
    color: var(--color-high);
    border-color: var(--color-high-border);
  }

  .task-actions {
    display: flex;
    gap: 2px;
    opacity: 0;
    transition: opacity 0.15s;
  }
  .task-row:hover .task-actions {
    opacity: 1;
  }

  .row-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 26px;
    border-radius: var(--radius-sm);
    color: var(--color-text-tertiary);
    transition: background 0.15s, color 0.15s;
  }
  .row-btn:hover {
    background: var(--color-bg-surface);
    color: var(--color-text-primary);
  }
  .row-btn.danger:hover {
    background: var(--color-high-bg);
    color: var(--color-high);
  }

  .empty-msg {
    font-size: var(--font-size-sm);
    color: var(--color-text-tertiary);
    text-align: center;
    padding: var(--spacing-4) 0;
  }

  /* Chat */
  .chat-history {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-2);
    max-height: 220px;
    overflow-y: auto;
    padding: var(--spacing-1) 0;
  }

  .bubble {
    max-width: 85%;
    padding: 8px 12px;
    border-radius: var(--radius-lg);
    font-size: var(--font-size-sm);
    line-height: 1.45;
    word-break: break-word;
  }
  .bubble.user {
    align-self: flex-end;
    background: var(--color-accent);
    color: white;
    border-bottom-right-radius: 4px;
  }
  .bubble.ai {
    align-self: flex-start;
    background: var(--color-bg-elevated);
    color: var(--color-text-primary);
    border: 1px solid var(--color-border);
    border-bottom-left-radius: 4px;
  }
  .bubble.typing {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 10px 14px;
  }
  .bubble.typing span {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--color-text-tertiary);
    animation: bounce 1.2s infinite ease-in-out;
  }
  .dot-1 { animation-delay: 0s; }
  .dot-2 { animation-delay: 0.2s; }
  .dot-3 { animation-delay: 0.4s; }
  @keyframes bounce {
    0%, 80%, 100% { transform: scale(0.7); opacity: 0.4; }
    40% { transform: scale(1); opacity: 1; }
  }

  .chat-input-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
    background: var(--color-bg-elevated);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-lg);
    padding: 6px 6px 6px 12px;
    transition: border-color 0.15s;
  }
  .chat-input-row:focus-within {
    border-color: var(--color-accent);
  }

  .chat-input {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    font-family: inherit;
    font-size: var(--font-size-sm);
    color: var(--color-text-primary);
    min-width: 0;
  }
  .chat-input::placeholder {
    color: var(--color-text-tertiary);
  }

  .send-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    height: 30px;
    border-radius: var(--radius-md);
    background: var(--color-accent);
    color: white;
    flex-shrink: 0;
    transition: background 0.15s, opacity 0.15s;
  }
  .send-btn:hover:not(:disabled) {
    background: var(--color-accent-hover);
  }
  .send-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  /* Weekly view wrapper */
  .weekly-wrapper {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    padding: var(--spacing-4);
  }
</style>
