<script lang="ts">
  let { title, message, onConfirm, onCancel } = $props<{
    title: string;
    message: string;
    onConfirm: () => void;
    onCancel: () => void;
  }>();
</script>

<div class="backdrop" onclick={onCancel} role="presentation">
  <div class="modal card" onclick={(e) => e.stopPropagation()} role="alertdialog" aria-modal="true">
    <div class="modal-header">
      <h3>{title}</h3>
    </div>
    <p class="modal-message">{message}</p>
    <div class="modal-actions">
      <button class="btn-cancel" onclick={onCancel}>Cancel</button>
      <button class="btn-confirm danger" onclick={onConfirm}>Delete</button>
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
    z-index: 999;
    padding: var(--spacing-4);
  }

  .modal {
    width: 100%;
    max-width: 360px;
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
    align-items: center;
  }

  h3 {
    font-size: var(--font-size-base);
    font-weight: 600;
  }

  .modal-message {
    font-size: var(--font-size-sm);
    color: var(--color-text-secondary);
    line-height: 1.5;
  }

  .modal-actions {
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

  .btn-confirm {
    font-size: var(--font-size-sm);
    font-weight: 600;
    padding: 8px 18px;
    border-radius: var(--radius-sm);
    color: white;
  }
  .btn-confirm.danger {
    background: var(--color-high);
    transition: background 0.15s;
  }
  .btn-confirm.danger:hover {
    background: var(--color-high-border);
  }
</style>
