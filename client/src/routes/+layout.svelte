<script lang="ts">
  import "../app.css";
  import { API } from "$lib/api";
  let { children, data } = $props();

  const user = $derived(data?.user ?? null);
  let dropdownOpen = $state(false);

  function getInitial(email: string) {
    return email ? email[0].toUpperCase() : '?';
  }

  async function handleLogout() {
    await API.logout();
  }
</script>

<div class="shell">
  <header class="header">
    <div class="header-brand">
      <div class="brand-mark"></div>
      <span class="brand-name">emo</span>
    </div>

    {#if user}
      <div class="profile-area">
        <button
          class="avatar-btn"
          onclick={() => (dropdownOpen = !dropdownOpen)}
          title={user.email}
          aria-expanded={dropdownOpen}
        >
          <span class="avatar-circle">{getInitial(user.email)}</span>
        </button>

        {#if dropdownOpen}
          <div class="dropdown-backdrop" onclick={() => (dropdownOpen = false)} role="presentation"></div>
          <div class="profile-dropdown card">
            <div class="profile-email">
              <span class="avatar-circle avatar-sm">{getInitial(user.email)}</span>
              <span class="email-text">{user.email}</span>
            </div>
            <div class="divider"></div>
            <button class="btn-logout" onclick={handleLogout}>Sign out</button>
          </div>
        {/if}
      </div>
    {/if}
  </header>

  <main class="content">
    {@render children()}
  </main>
</div>

<style>
  .shell {
    display: flex;
    flex-direction: column;
    height: 100vh;
    max-width: 1280px;
    margin: 0 auto;
    overflow: hidden;
  }

  .header {
    flex-shrink: 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 var(--spacing-5);
    height: 56px;
    background: var(--color-bg-surface);
    border-bottom: 1px solid var(--color-border);
    z-index: 10;
  }

  .header-brand {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
  }

  .brand-mark {
    width: 20px;
    height: 20px;
    background: var(--color-accent);
    border-radius: 6px;
    position: relative;
  }
  .brand-mark::after {
    content: '';
    position: absolute;
    bottom: -3px;
    right: -3px;
    width: 10px;
    height: 10px;
    background: var(--color-high);
    border-radius: 3px;
    border: 2px solid var(--color-bg-surface);
  }

  .brand-name {
    font-size: var(--font-size-lg);
    font-weight: 700;
    color: var(--color-text-primary);
    letter-spacing: -0.02em;
  }

  /* Profile */
  .profile-area {
    position: relative;
  }

  .avatar-btn {
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    border-radius: 50%;
    transition: box-shadow 0.15s;
  }
  .avatar-btn:hover {
    box-shadow: 0 0 0 3px var(--color-accent-light);
  }

  .avatar-circle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 34px;
    height: 34px;
    border-radius: 50%;
    background: var(--color-accent);
    color: white;
    font-weight: 700;
    font-size: 0.85rem;
    user-select: none;
  }

  .avatar-sm {
    width: 28px;
    height: 28px;
    font-size: 0.75rem;
    flex-shrink: 0;
  }

  .dropdown-backdrop {
    position: fixed;
    inset: 0;
    z-index: 99;
  }

  .profile-dropdown {
    position: absolute;
    top: calc(100% + 8px);
    right: 0;
    width: 220px;
    padding: var(--spacing-3);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-2);
    z-index: 100;
    animation: pop-in 0.12s ease-out;
  }

  @keyframes pop-in {
    from { opacity: 0; transform: translateY(-6px) scale(0.97); }
    to   { opacity: 1; transform: translateY(0) scale(1); }
  }

  .profile-email {
    display: flex;
    align-items: center;
    gap: var(--spacing-2);
    padding: var(--spacing-1);
  }

  .email-text {
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .divider {
    height: 1px;
    background: var(--color-border);
  }

  .btn-logout {
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
    padding: var(--spacing-2) var(--spacing-2);
    border-radius: var(--radius-sm);
    text-align: left;
    transition: background 0.1s, color 0.1s;
    width: 100%;
  }
  .btn-logout:hover {
    background: var(--color-bg-elevated);
    color: var(--color-text-primary);
  }

  .content {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
</style>
