<script lang="ts">
  let { onSend }: { onSend: (msg: string) => void } = $props();
  let message = $state('');

  function send() {
    if (!message.trim()) return;
    onSend(message);
    message = '';
  }
  
  function handleKeydown(event: KeyboardEvent) {
    if (event.key === 'Enter') {
      send();
    }
  }
</script>

<div class="input-wrapper glass card">
  <input 
    type="text" 
    bind:value={message} 
    onkeydown={handleKeydown}
    placeholder="What's on your mind?" 
  />
  <button onclick={send} aria-label="Send Task" class="send-btn">
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>
  </button>
</div>

<style>
  .input-wrapper {
    position: fixed;
    bottom: var(--spacing-5);
    left: 50%;
    transform: translateX(-50%);
    width: calc(100% - var(--spacing-5) * 2);
    max-width: 560px;
    display: flex;
    align-items: center;
    gap: var(--spacing-3);
    padding: var(--spacing-2) var(--spacing-3);
    border-radius: var(--radius-xl);
    z-index: 50;
  }

  input {
    flex: 1;
    background: transparent;
    border: none;
    padding: var(--spacing-2);
    font-family: inherit;
    font-size: var(--font-size-base);
    color: var(--color-text-primary);
    outline: none;
  }
  
  input::placeholder {
    color: var(--color-text-tertiary);
  }

  .send-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background-color: var(--color-accent-primary);
    color: white;
    transition: background-color 0.2s;
  }

  .send-btn:hover {
    background-color: var(--color-accent-hover);
  }
</style>
