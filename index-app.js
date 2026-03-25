const CONTENT_API_URL = 'data/content-unlock.json';

let DATA = [];
const groupedData = [];
const sectionsMap = new Map();
const types = new Set();
let savedState = JSON.parse(localStorage.getItem('ffxiv_checklist_state')) || {};
let showCompleted = localStorage.getItem('ffxiv_show_completed') === 'true';

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

    return `<a href="${escapeAttr(url)}" target="_blank" rel="noopener noreferrer" style="color:inherit;text-decoration:underline;">${safeText}</a>`;
}

function normalizeParts(parts) {
    if (Array.isArray(parts)) return parts;
    return parts ? [parts] : [];
}

function renderTextParts(parts, fallback, separator = ' / ') {
    parts = normalizeParts(parts);
    if (Array.isArray(parts) && parts.length) {
        return parts.map(part => renderWikiLink(part.text, part.url)).join(separator);
    }

    return escapeHtml(fallback || '');
}

function renderLocationParts(parts, fallback) {
    parts = normalizeParts(parts);
    if (Array.isArray(parts) && parts.length) {
        return parts.map(part => {
            const placeHtml = renderWikiLink(part.place || part.display || '', part.url);
            return part.coords ? `${escapeHtml(part.coords)}:${placeHtml}` : placeHtml;
        }).join('; ');
    }

    return escapeHtml(fallback || '');
}

function renderTrustedHtml(html, fallback = '') {
    if (html && String(html).trim()) {
        return html;
    }

    return escapeHtml(fallback || '');
}

function sectionOrderValue(section) {
    const order = [
        'Level 1 - 50',
        'Level 50',
        'Level 51 - 60',
        'Level 60',
        'Level 61 - 70',
        'Level 70',
        'Level 71 - 80',
        'Level 80',
        'Level 81 - 90',
        'Level 90',
        'Level 91 - 100',
        'Level 100'
    ];
    const idx = order.indexOf(section);
    return idx === -1 ? 999 : idx;
}

function rebuildDerivedData() {
    groupedData.length = 0;
    sectionsMap.clear();
    types.clear();

    DATA.forEach((item, index) => {
        if (!sectionsMap.has(item.section)) {
            const newSection = { id: item.section.replace(/\W+/g, '_').toLowerCase(), title: item.section, items: [] };
            sectionsMap.set(item.section, newSection);
            groupedData.push(newSection);
        }

        if (item.type) {
            types.add(item.type);
        }

        item.cleanId = `${item.id.replace(/\W+/g, '_')}_${index}`;
        sectionsMap.get(item.section).items.push(item);
    });

    groupedData.sort((a, b) => sectionOrderValue(a.title) - sectionOrderValue(b.title));
}

function setChecklistStatus(message, isError = false) {
    const container = document.getElementById('checklist-container');
    container.innerHTML = `<div class="progress-container"><p style="margin:0;color:${isError ? '#fda4af' : '#94a3b8'};text-align:center;">${escapeHtml(message)}</p></div>`;
    document.getElementById('progress-text').innerText = '0 / 0 (0%)';
    document.getElementById('progress-bar').style.width = '0%';
}

async function loadContentData() {
    const response = await fetch(CONTENT_API_URL, {
        headers: { Accept: 'application/json' }
    });

    if (!response.ok) {
        throw new Error(`Failed to load content (${response.status})`);
    }

    const payload = await response.json();
    if (!Array.isArray(payload)) {
        throw new Error('Content JSON did not return an array.');
    }

    DATA = payload;
    rebuildDerivedData();
}

function populateTypeFilter() {
    const typeFilter = document.getElementById('type-filter');
    typeFilter.innerHTML = '<option value="">All types</option>';

    Array.from(types)
        .sort((a, b) => a.localeCompare(b))
        .forEach(type => {
            const option = document.createElement('option');
            option.value = type;
            option.textContent = type;
            typeFilter.appendChild(option);
        });
}

function updateCompletedToggleButton() {
    const button = document.getElementById('toggle-completed-btn');
    if (!button) {
        return;
    }

    button.textContent = showCompleted ? 'Hide Completed' : 'Show Completed';
}

function renderChecklist() {
    const container = document.getElementById('checklist-container');
    container.innerHTML = '';

    groupedData.forEach((category, idx) => {
        const completedCount = category.items.filter(item => savedState[item.id]).length;
        const totalCount = category.items.length;

        const categoryEl = document.createElement('div');
        categoryEl.className = 'category';
        categoryEl.style.animationDelay = `${(idx % 5) * 0.1}s`;

        const itemsHtml = category.items.map(item => {
            let badgesHtml = '';
            if (item.type) badgesHtml += `<span class="badge type">${escapeHtml(item.type)}</span>`;
            if (item.ilevel && item.ilevel !== '-') badgesHtml += `<span class="badge ilvl">iLvl ${escapeHtml(item.ilevel)}</span>`;

            const hasQuest = normalizeParts(item.quest_parts).length > 0;
            const titleHtml = hasQuest
                ? renderTextParts(item.quest_parts, item.primary)
                : renderTextParts(item.unlock_parts, item.primary);
            const unlockHtml = hasQuest
                ? `<div class="content-quest">Unlock: ${renderTextParts(item.unlock_parts, item.secondary_unlock || item.unlock)}</div>`
                : '';
            const locHtml = item.location
                ? `<div class="content-loc">Location: ${renderLocationParts(item.location_parts, item.location)}</div>`
                : '';
            const infoHtml = (item.information_html || item.information) ? `<div class="content-desc">${renderTrustedHtml(item.information_html, item.information)}</div>` : '';

            return `
                <li class="checklist-item ${savedState[item.id] ? 'completed' : ''}" id="item-${item.cleanId}" data-search="${escapeAttr((item.unlock + ' ' + item.quest + ' ' + item.location + ' ' + item.type + ' ' + item.information).toLowerCase())}" data-type="${escapeAttr(item.type || '')}">
                    <div class="checkbox-wrapper">
                        <input type="checkbox"
                               id="check-${item.cleanId}"
                               ${savedState[item.id] ? 'checked' : ''}
                               onchange="toggleItem('${category.id}', '${item.id}', '${item.cleanId}')">
                    </div>
                    <div class="content-info">
                        <div class="content-name">${titleHtml}</div>
                        <div class="badges">${badgesHtml}</div>
                        ${unlockHtml}
                        ${locHtml}
                        ${infoHtml}
                    </div>
                </li>
            `;
        }).join('');

        categoryEl.innerHTML = `
            <div class="category-header" onclick="toggleCategory('${category.id}')">
                <div class="category-title">${escapeHtml(category.title)}</div>
                <div class="category-stats" id="stats-${category.id}">
                    ${completedCount} / ${totalCount}
                </div>
            </div>
            <ul class="checklist" id="list-${category.id}">
                ${itemsHtml}
            </ul>
        `;
        container.appendChild(categoryEl);
    });

    updateMainProgress();
    filterItems();
}

function toggleItem(categoryId, originalId, cleanId) {
    const checkbox = document.getElementById(`check-${cleanId}`);
    const itemEl = document.getElementById(`item-${cleanId}`);

    savedState[originalId] = checkbox.checked;
    localStorage.setItem('ffxiv_checklist_state', JSON.stringify(savedState));

    if (checkbox.checked) itemEl.classList.add('completed');
    else itemEl.classList.remove('completed');

    updateCategoryStats(categoryId);
    updateMainProgress();
    filterItems();
}

function toggleCompletedVisibility() {
    showCompleted = !showCompleted;
    localStorage.setItem('ffxiv_show_completed', String(showCompleted));
    updateCompletedToggleButton();
    filterItems();
}

function updateCategoryStats(categoryId) {
    const category = groupedData.find(c => c.id === categoryId);
    const statsEl = document.getElementById(`stats-${categoryId}`);
    if (!category || !statsEl) {
        return;
    }

    const completedCount = category.items.filter(item => savedState[item.id]).length;
    statsEl.innerText = `${completedCount} / ${category.items.length}`;
}

function updateMainProgress() {
    let totalItems = 0;
    let completedItems = 0;

    groupedData.forEach(category => {
        totalItems += category.items.length;
        completedItems += category.items.filter(item => savedState[item.id]).length;
    });

    const percentage = totalItems === 0 ? 0 : Math.round((completedItems / totalItems) * 100);
    document.getElementById('progress-text').innerText = `${completedItems} / ${totalItems} (${percentage}%)`;
    document.getElementById('progress-bar').style.width = `${percentage}%`;
}

function toggleCategory(categoryId) {
    const list = document.getElementById(`list-${categoryId}`);
    if (!list) return;
    list.style.display = list.style.display === 'none' ? 'grid' : 'none';
}

function expandAll() {
    groupedData.forEach(category => {
        const list = document.getElementById(`list-${category.id}`);
        if (list) list.style.display = 'grid';
    });
}

function collapseAll() {
    groupedData.forEach(category => {
        const list = document.getElementById(`list-${category.id}`);
        if (list) list.style.display = 'none';
    });
}

function resetProgress() {
    if (confirm('Are you sure you want to reset all progress?')) {
        savedState = {};
        localStorage.removeItem('ffxiv_checklist_state');
        renderChecklist();
    }
}

function filterItems() {
    const searchTerm = document.getElementById('search-input').value.toLowerCase();
    const typeTerm = document.getElementById('type-filter').value;

    document.querySelectorAll('.checklist-item').forEach(el => {
        const matchesSearch = el.dataset.search.includes(searchTerm);
        const matchesType = !typeTerm || el.dataset.type === typeTerm;
        const isCompleted = el.classList.contains('completed');
        el.style.display = (matchesSearch && matchesType && (showCompleted || !isCompleted)) ? 'flex' : 'none';
    });

    groupedData.forEach(category => {
        const list = document.getElementById(`list-${category.id}`);
        if (!list) return;

        const hasVisible = Array.from(list.children).some(li => li.style.display !== 'none');
        list.parentElement.style.display = hasVisible ? 'block' : 'none';
    });
}

async function initializeApp() {
    setChecklistStatus('Loading content...');

    try {
        await loadContentData();
        populateTypeFilter();
        updateCompletedToggleButton();
        renderChecklist();
    } catch (error) {
        console.error(error);
        setChecklistStatus('Could not load content from data/content-unlock.json.', true);
    }
}

document.addEventListener('DOMContentLoaded', initializeApp);


