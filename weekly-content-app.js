const WEEKLY_STORAGE_KEY = 'ffxiv_weekly_content_state';

function getWeeklyState() {
    try {
        return JSON.parse(localStorage.getItem(WEEKLY_STORAGE_KEY) || '{}');
    } catch (error) {
        console.error(error);
        return {};
    }
}

function saveWeeklyState(state) {
    localStorage.setItem(WEEKLY_STORAGE_KEY, JSON.stringify(state));
}

function updateWeeklyProgress() {
    const items = Array.from(document.querySelectorAll('.weekly-card'));
    const completed = items.filter(item => item.classList.contains('completed')).length;
    const total = items.length;
    const percent = total === 0 ? 0 : Math.round((completed / total) * 100);

    const countEl = document.getElementById('weekly-done-count');
    const percentEl = document.getElementById('weekly-progress-percent');

    if (countEl) {
        countEl.textContent = `${completed} / ${total}`;
    }

    if (percentEl) {
        percentEl.textContent = `${percent}%`;
    }
}

function applyWeeklyState() {
    const state = getWeeklyState();

    document.querySelectorAll('.weekly-card').forEach(card => {
        const itemId = card.dataset.itemId;
        const checkbox = card.querySelector('.weekly-checkbox');
        const isDone = Boolean(state[itemId]);

        if (checkbox) {
            checkbox.checked = isDone;
        }

        card.classList.toggle('completed', isDone);
    });

    updateWeeklyProgress();
}

function toggleWeeklyItem(itemId, checked) {
    const state = getWeeklyState();
    state[itemId] = checked;
    saveWeeklyState(state);
    applyWeeklyState();
}

function resetWeeklyChecklist() {
    if (!confirm('Reset the weekly checklist for this browser?')) {
        return;
    }

    localStorage.removeItem(WEEKLY_STORAGE_KEY);
    applyWeeklyState();
}

document.addEventListener('change', (event) => {
    const checkbox = event.target.closest('.weekly-checkbox');
    if (!checkbox) {
        return;
    }

    toggleWeeklyItem(checkbox.dataset.itemId || '', checkbox.checked);
});

document.addEventListener('click', (event) => {
    if (event.target.closest('#reset-weekly-btn')) {
        resetWeeklyChecklist();
    }
});

document.addEventListener('DOMContentLoaded', applyWeeklyState);
