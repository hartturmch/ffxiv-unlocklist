const AETHER_CURRENTS_URL = 'data/aether-currents.json';
const AETHER_STATE_KEY = 'ffxiv_checklist_state';
const AETHER_SHOW_COMPLETED_KEY = 'ffxiv_aether_guide_show_completed';
const AETHER_OPEN_SUBCATEGORIES_KEY = 'ffxiv_aether_guide_subcategories_open';

let aetherData = [];
let aetherState = JSON.parse(localStorage.getItem(AETHER_STATE_KEY) || '{}');
let aetherShowCompleted = localStorage.getItem(AETHER_SHOW_COMPLETED_KEY) === 'true';
let openSubcategories = JSON.parse(localStorage.getItem(AETHER_OPEN_SUBCATEGORIES_KEY) || '{}');

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function escapeAttr(value) {
    return escapeHtml(value);
}

function renderWikiLink(text, url) {
    const safeText = escapeHtml(text);
    if (!url) {
        return safeText;
    }

    return `<a href="${escapeAttr(url)}" target="_blank" rel="noopener noreferrer">${safeText}</a>`;
}

function getItemId(item) {
    return `aether|${item.id}`;
}

function getCleanId(item, index) {
    return `${String(item.id).replace(/\W+/g, '_')}_${index}`;
}

function getSubcategoryId(expansion, zone) {
    return `aether_${expansion}_${zone}`.replace(/\W+/g, '_').toLowerCase();
}

function isSubcategoryOpen(subcategoryId) {
    return openSubcategories[subcategoryId] !== false;
}

function saveSubcategoryState() {
    localStorage.setItem(AETHER_OPEN_SUBCATEGORIES_KEY, JSON.stringify(openSubcategories));
}

function setStatus(message, isError = false) {
    const container = document.getElementById('aether-checklist-container');
    container.innerHTML = `<div class="status-message" style="color:${isError ? '#fda4af' : '#94a3b8'};">${escapeHtml(message)}</div>`;
    updateProgress(0, 0);
}

function updateProgress(done, total) {
    const percentage = total === 0 ? 0 : Math.round((done / total) * 100);
    document.getElementById('aether-progress-text').innerText = `${done} / ${total} (${percentage}%)`;
    document.getElementById('aether-progress-bar').style.width = `${percentage}%`;
}

function updateToggleCompletedButton() {
    const button = document.getElementById('aether-toggle-completed-btn');
    button.textContent = aetherShowCompleted ? 'Hide Completed' : 'Show Completed';
}

function updateSearchClearButton() {
    const input = document.getElementById('aether-search-input');
    const button = document.getElementById('aether-clear-search-btn');
    button.hidden = !input.value.trim();
}

function clearSearch() {
    const input = document.getElementById('aether-search-input');
    input.value = '';
    updateSearchClearButton();
    filterItems();
    input.focus();
}

function buildSearchHaystack(item) {
    return [
        item.expansion,
        item.zone,
        item.primary,
        item.quest,
        item.coordinates,
        item.description,
        item.additional_information,
        item.type,
        item.entry_type
    ].filter(Boolean).join(' ').toLowerCase();
}

function renderItem(item, index) {
    const itemId = getItemId(item);
    const cleanId = getCleanId(item, index);
    const isCompleted = !!aetherState[itemId];
    const subcategoryId = getSubcategoryId(item.expansion, item.zone);
    const titleHtml = item.quest_parts && item.quest_parts.length
        ? renderWikiLink(item.quest_parts[0].text, item.quest_parts[0].url)
        : renderWikiLink(item.primary, '');
    const infoHtml = item.entry_type === 'Field'
        ? (item.description_html || escapeHtml(item.description || ''))
        : (item.additional_information_html || escapeHtml(item.additional_information || ''));
    const numberBadge = item.number ? `<span class="badge current">#${escapeHtml(item.number)}</span>` : '';
    const levelBadge = item.level ? `<span class="badge ilvl">LVL ${escapeHtml(item.level)}</span>` : '';

    return `
        <li
            class="checklist-item ${isCompleted ? 'completed' : ''}"
            id="item-${cleanId}"
            data-item-id="${escapeAttr(itemId)}"
            data-clean-id="${escapeAttr(cleanId)}"
            data-subcategory-id="${escapeAttr(subcategoryId)}"
            data-search="${escapeAttr(buildSearchHaystack(item))}"
            data-type="${escapeAttr(item.entry_type || '')}"
        >
            <div class="checkbox-wrapper">
                <input
                    type="checkbox"
                    class="item-checkbox"
                    id="check-${cleanId}"
                    data-item-id="${escapeAttr(itemId)}"
                    data-clean-id="${escapeAttr(cleanId)}"
                    data-subcategory-id="${escapeAttr(subcategoryId)}"
                    ${isCompleted ? 'checked' : ''}
                >
            </div>
            <div class="content-info">
                <div class="content-name">${titleHtml}</div>
                <div class="badges">
                    <span class="badge type">Aether Current</span>
                    <span class="badge type">${escapeHtml(item.entry_type || '')}</span>
                    <span class="badge expansion">${escapeHtml(item.expansion || '')}</span>
                    ${numberBadge}
                    ${levelBadge}
                </div>
                <div class="content-loc">Coordinates: ${escapeHtml(item.coordinates || '')}</div>
                ${infoHtml ? `<div class="content-desc">${infoHtml}</div>` : ''}
            </div>
        </li>
    `;
}

function renderSubcategories(items) {
    const groups = new Map();

    items.forEach((item, index) => {
        const key = `${item.expansion}|${item.zone}`;
        if (!groups.has(key)) {
            groups.set(key, {
                key,
                expansion: item.expansion || '',
                expansionOrder: item.expansion_order || 999,
                zone: item.zone || 'Unknown Zone',
                zoneOrder: item.zone_order || 999,
                items: []
            });
        }

        groups.get(key).items.push({ ...item, renderIndex: index });
    });

    return Array.from(groups.values())
        .sort((a, b) => {
            if (a.expansionOrder !== b.expansionOrder) return a.expansionOrder - b.expansionOrder;
            if (a.zoneOrder !== b.zoneOrder) return a.zoneOrder - b.zoneOrder;
            return a.zone.localeCompare(b.zone);
        })
        .map(group => {
            group.items.sort((a, b) => (a.item_order || 999) - (b.item_order || 999));
            const subcategoryId = getSubcategoryId(group.expansion, group.zone);
            const done = group.items.filter(item => aetherState[getItemId(item)]).length;
            const isOpen = isSubcategoryOpen(subcategoryId);

            return `
                <section class="subcategory" data-subcategory-id="${escapeAttr(subcategoryId)}">
                    <div class="subcategory-header" data-action="toggle-subcategory" data-subcategory-id="${escapeAttr(subcategoryId)}">
                        <div>
                            <div class="subcategory-title">${escapeHtml(group.zone)}</div>
                            <div class="subcategory-meta">${escapeHtml(group.expansion)}</div>
                        </div>
                        <div class="subcategory-header-right">
                            <div class="subcategory-stats" id="substats-${subcategoryId}">${done} / ${group.items.length}</div>
                            <button type="button" class="btn subcategory-toggle" id="subtoggle-${subcategoryId}">${isOpen ? 'Hide' : 'Show'}</button>
                        </div>
                    </div>
                    <div class="subcategory-content" id="sublist-${subcategoryId}" style="display:${isOpen ? 'block' : 'none'};">
                        <ul class="checklist">
                            ${group.items.map(item => renderItem(item, item.renderIndex)).join('')}
                        </ul>
                    </div>
                </section>
            `;
        })
        .join('');
}

function renderChecklist() {
    const container = document.getElementById('aether-checklist-container');
    const completedCount = aetherData.filter(item => aetherState[getItemId(item)]).length;

    container.innerHTML = `
        <div class="category">
            <div class="category-header">
                <div class="category-title">Aether Currents</div>
                <div class="category-stats" id="aether-category-stats">${completedCount} / ${aetherData.length}</div>
            </div>
            <div class="category-body" id="aether-category-body">
                ${renderSubcategories(aetherData)}
            </div>
        </div>
    `;

    updateProgress(completedCount, aetherData.length);
    updateToggleCompletedButton();
    updateSearchClearButton();
    filterItems();
}

function updateCategoryStats() {
    const done = aetherData.filter(item => aetherState[getItemId(item)]).length;
    const stats = document.getElementById('aether-category-stats');
    if (stats) {
        stats.innerText = `${done} / ${aetherData.length}`;
    }
    updateProgress(done, aetherData.length);
}

function updateSubcategoryStats(subcategoryId) {
    const section = document.querySelector(`.subcategory[data-subcategory-id="${subcategoryId}"]`);
    const stats = document.getElementById(`substats-${subcategoryId}`);
    if (!section || !stats) {
        return;
    }

    const items = Array.from(section.querySelectorAll('.checklist-item'));
    const done = items.filter(item => item.classList.contains('completed')).length;
    stats.innerText = `${done} / ${items.length}`;
}

function toggleItem(itemId, cleanId, subcategoryId, checked) {
    aetherState[itemId] = checked;
    localStorage.setItem(AETHER_STATE_KEY, JSON.stringify(aetherState));

    const itemEl = document.getElementById(`item-${cleanId}`);
    if (itemEl) {
        itemEl.classList.toggle('completed', checked);
    }

    updateSubcategoryStats(subcategoryId);
    updateCategoryStats();
    filterItems();
}

function toggleSubcategory(subcategoryId) {
    const content = document.getElementById(`sublist-${subcategoryId}`);
    const button = document.getElementById(`subtoggle-${subcategoryId}`);
    if (!content) {
        return;
    }

    const isOpening = content.style.display === 'none';
    content.style.display = isOpening ? 'block' : 'none';
    openSubcategories[subcategoryId] = isOpening;
    saveSubcategoryState();

    if (button) {
        button.textContent = isOpening ? 'Hide' : 'Show';
    }
}

function setAllSubcategories(isOpen) {
    document.querySelectorAll('.subcategory').forEach(subcategory => {
        const subcategoryId = subcategory.dataset.subcategoryId;
        const content = document.getElementById(`sublist-${subcategoryId}`);
        const button = document.getElementById(`subtoggle-${subcategoryId}`);

        if (content) {
            content.style.display = isOpen ? 'block' : 'none';
        }
        if (button) {
            button.textContent = isOpen ? 'Hide' : 'Show';
        }
        openSubcategories[subcategoryId] = isOpen;
    });

    saveSubcategoryState();
}

function filterItems() {
    const searchTerm = document.getElementById('aether-search-input').value.toLowerCase();
    const typeTerm = document.getElementById('aether-type-filter').value;

    updateSearchClearButton();

    document.querySelectorAll('.checklist-item').forEach(item => {
        const matchesSearch = item.dataset.search.includes(searchTerm);
        const matchesType = !typeTerm || item.dataset.type === typeTerm;
        const isCompleted = item.classList.contains('completed');
        item.style.display = matchesSearch && matchesType && (aetherShowCompleted || !isCompleted) ? 'flex' : 'none';
    });

    document.querySelectorAll('.subcategory').forEach(subcategory => {
        const hasVisible = Array.from(subcategory.querySelectorAll('.checklist-item')).some(item => item.style.display !== 'none');
        subcategory.style.display = hasVisible ? 'block' : 'none';
    });
}

async function loadAetherData() {
    const response = await fetch(AETHER_CURRENTS_URL, { headers: { Accept: 'application/json' } });
    if (!response.ok) {
        throw new Error(`Failed to load aether currents (${response.status})`);
    }

    const payload = await response.json();
    if (!Array.isArray(payload)) {
        throw new Error('Aether currents JSON did not return an array.');
    }

    aetherData = payload;
}

async function initializeAetherGuide() {
    setStatus('Loading Aether Currents...');

    try {
        await loadAetherData();
        renderChecklist();
    } catch (error) {
        console.error(error);
        setStatus('Could not load Aether Currents from the local JSON file.', true);
    }
}

document.addEventListener('change', event => {
    const checkbox = event.target.closest('.item-checkbox');
    if (!checkbox) {
        return;
    }

    toggleItem(
        checkbox.dataset.itemId,
        checkbox.dataset.cleanId,
        checkbox.dataset.subcategoryId,
        checkbox.checked
    );
});

document.addEventListener('click', event => {
    const clearButton = event.target.closest('#aether-clear-search-btn');
    if (clearButton) {
        clearSearch();
        return;
    }

    const toggleArea = event.target.closest('[data-action="toggle-subcategory"]');
    if (toggleArea) {
        toggleSubcategory(toggleArea.dataset.subcategoryId);
        return;
    }
});

document.getElementById('aether-search-input').addEventListener('input', filterItems);
document.getElementById('aether-type-filter').addEventListener('change', filterItems);
document.getElementById('aether-toggle-completed-btn').addEventListener('click', () => {
    aetherShowCompleted = !aetherShowCompleted;
    localStorage.setItem(AETHER_SHOW_COMPLETED_KEY, String(aetherShowCompleted));
    updateToggleCompletedButton();
    filterItems();
});
document.getElementById('aether-expand-btn').addEventListener('click', () => setAllSubcategories(true));
document.getElementById('aether-collapse-btn').addEventListener('click', () => setAllSubcategories(false));

initializeAetherGuide();
