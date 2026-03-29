const CONTENT_API_URL = 'data/content-unlock.json';

const AETHER_CURRENTS_URL = 'data/aether-currents.json';

const WONDROUS_TAILS_URL = 'data/wondrous-tails.json';

let DATA = [];
const groupedData = [];
const sectionsMap = new Map();
const types = new Set();
let savedState = JSON.parse(localStorage.getItem('ffxiv_checklist_state')) || {};
let showCompleted = localStorage.getItem('ffxiv_show_completed') === 'true';
let openAetherSubcategories = JSON.parse(localStorage.getItem('ffxiv_aether_subcategories_open') || '{}');
let openWondrousSubcategories = JSON.parse(localStorage.getItem('ffxiv_wondrous_subcategories_open') || '{}');
let checklistStableMinHeight = 0;
const CHANGELOG_ENTRIES = [
    {
        version: 'v1.4.5',
        date: '2026-03-29',
        summary: 'Weekly content child pages were restored without cluttering the sidebar.',
        changes: [
            'Restored the Wondrous Tails and Jumbo Cactpot guide pages.',
            'Kept those pages out of the sidebar navigation.',
            'Added direct How To Do It links from Weekly Checklist back to the guide pages.'
        ]
    },
    {
        version: 'v1.4.4',
        date: '2026-03-29',
        summary: 'Weekly content pages were consolidated.',
        changes: [
            'Removed the separate Wondrous Tails and Jumbo Cactpot pages.',
            'Moved their instructions directly into Weekly Checklist.',
            'Simplified the weekly area to a single checklist page.'
        ]
    },
    {
        version: 'v1.4.3',
        date: '2026-03-29',
        summary: 'Weekly Content now has its own checklist page and child guides.',
        changes: [
            'Turned Weekly Content Guide into a weekly checklist with saved progress.',
            'Added a dedicated Jumbo Cactpot guide page.',
            'Linked the weekly systems to their own subpages inside the weekly content section.'
        ]
    },
    {
        version: 'v1.4.2',
        date: '2026-03-29',
        summary: 'Weekly systems were reorganized under Weekly Content.',
        changes: [
            'Moved Wondrous Tails into the Weekly Content category in the main checklist.',
            'Added a dedicated Weekly Content guide page.',
            'Grouped Jumbo Cactpot and Wondrous Tails under the same explanatory guide.'
        ]
    },
    {
        version: 'v1.4.1',
        date: '2026-03-29',
        summary: 'Gold Saucer and Jumbo Cactpot unlock details were expanded.',
        changes: [
            'Updated the Gold Saucer entry with the correct NPC, coordinates, and MSQ note.',
            'Added Jumbo Cactpot as its own unlock entry.',
            'Linked both entries to the relevant wiki and official guide pages.'
        ]
    },
    {
        version: 'v1.4.0',
        date: '2026-03-29',
        summary: 'Wondrous Tails was integrated into the main index.',
        changes: [
            'Added Wondrous Tails as a new category in the main checklist.',
            'Grouped Wondrous Tails into unlock, weekly flow, duty pools, rewards, second chance, and achievements.',
            'Added a local refresh script and static JSON dataset for the Wondrous Tails page.'
        ]
    },
    {
        version: 'v1.3.1',
        date: '2026-03-28',
        summary: 'Aether Currents integrated and stabilized in the main index.',
        changes: [
            'Added Aether Currents to the main checklist as a separate category.',
            'Grouped Aether Currents by map/zone as collapsible subcategories.',
            'Fixed checkbox handling for quest names with apostrophes.',
            'Fixed subcategory progress counters and completed-item behavior.'
        ]
    },
    {
        version: 'v1.2.0',
        date: '2026-03-25',
        summary: 'Content Unlock data pipeline moved to static JSON.',
        changes: [
            'Switched the site to consume local JSON instead of backend content routes.',
            'Added refresh scripts to rebuild content directly from the wiki.',
            'Archived legacy backend files that were no longer used.'
        ]
    },
    {
        version: 'v1.1.0',
        date: '2026-03-25',
        summary: 'Wiki links and location formatting were normalized.',
        changes: [
            'Normalized locations to the format X / Y / place.',
            'Preserved wiki links in quests, locations and relevant information fields.',
            'Refreshed the Content Unlock dataset to match the current wiki page.'
        ]
    },
    {
        version: 'v1.0.0',
        date: '2026-03-25',
        summary: 'Initial checklist version of the site.',
        changes: [
            'Added Content Unlock checklist UI with progress tracking.',
            'Added local progress persistence with localStorage.',
            'Added filters, search and expand / collapse controls.'
        ]
    }
];

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
        'Level 100',
        'Aether Currents',
        'Weekly Content'
    ];
    const idx = order.indexOf(section);
    return idx === -1 ? 999 : idx;
}

function adaptAetherCurrents(items) {
    return items.map(item => ({
        id: `aether|${item.id}`,
        section: 'Aether Currents',
        unlock: item.primary || '',
        unlock_parts: [],
        type: 'Aether Current',
        quest: item.quest || '',
        quest_parts: normalizeParts(item.quest_parts),
        location: item.coordinates || '',
        location_parts: [],
        information: item.entry_type === 'Field'
            ? (item.description || '')
            : (item.additional_information || ''),
        information_html: item.entry_type === 'Field'
            ? (item.description_html || '')
            : (item.additional_information_html || ''),
        raw: `${item.expansion} | ${item.zone} | ${item.primary}`,
        primary: item.primary || '',
        secondary_unlock: '',
        ilevel: '',
        is_aether_current: true,
        expansion: item.expansion || '',
        expansion_order: item.expansion_order || 999,
        zone: item.zone || '',
        zone_order: item.zone_order || 999,
        subcategory_title: item.zone || '',
        subcategory_meta: item.expansion || '',
        subcategory_order: ((item.expansion_order || 999) * 1000) + (item.zone_order || 999),
        item_order: item.item_order || 999,
        subtype: item.entry_type || '',
        number: item.number || '',
        map_number: item.map_number || '',
        level: item.level || ''
    }));
}

function adaptWondrousTails(items) {
    return items.map(item => ({
        id: `wondrous|${item.id}`,
        section: 'Weekly Content',
        unlock: item.primary || '',
        unlock_parts: normalizeParts(item.primary_parts),
        type: item.subtype || 'Wondrous Tails',
        quest: '',
        quest_parts: [],
        location: item.location || '',
        location_parts: [],
        information: item.information || '',
        information_html: item.information_html || '',
        raw: `Weekly Content | ${item.group_title} | ${item.group_meta} | ${item.primary}`,
        primary: item.primary || '',
        secondary_html: item.secondary_html || '',
        secondary_label: item.secondary_label || '',
        ilevel: '',
        is_wondrous_tail: true,
        subtype: item.subtype || '',
        level: item.level || '',
        subcategory_title: item.group_title || 'General',
        subcategory_meta: item.group_meta || '',
        subcategory_order: item.group_order || 999,
        item_order: item.item_order || 999
    }));
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

async function fetchJsonArray(url, label) {
    const response = await fetch(url, {
        headers: { Accept: 'application/json' }
    });

    if (!response.ok) {
        throw new Error(`Failed to load ${label} (${response.status})`);
    }

    const payload = await response.json();
    if (!Array.isArray(payload)) {
        throw new Error(`${label} JSON did not return an array.`);
    }

    return payload;
}

async function loadContentData() {
    const [contentPayload, aetherPayload, wondrousPayload] = await Promise.all([
        fetchJsonArray(CONTENT_API_URL, 'content'),
        fetchJsonArray(AETHER_CURRENTS_URL, 'aether currents'),
        fetchJsonArray(WONDROUS_TAILS_URL, 'wondrous tails')
    ]);

    DATA = [
        ...contentPayload,
        ...adaptAetherCurrents(aetherPayload),
        ...adaptWondrousTails(wondrousPayload)
    ];
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

function updateSearchClearButton() {
    const input = document.getElementById('search-input');
    const button = document.getElementById('clear-search-btn');
    if (!input || !button) {
        return;
    }

    button.hidden = !input.value.trim();
}

function clearSearch() {
    const input = document.getElementById('search-input');
    if (!input) {
        return;
    }

    input.value = '';
    updateSearchClearButton();
    filterItems();
    input.focus();
}

function primaryFiltersAreActive() {
    const searchInput = document.getElementById('search-input');
    const typeFilter = document.getElementById('type-filter');
    const searchTerm = (searchInput?.value || '').trim();
    const typeTerm = typeFilter?.value || '';
    return Boolean(searchTerm || typeTerm);
}

function syncChecklistContainerHeight() {
    const container = document.getElementById('checklist-container');
    if (!container) {
        return;
    }

    if (primaryFiltersAreActive()) {
        if (!checklistStableMinHeight) {
            checklistStableMinHeight = Math.ceil(container.scrollHeight);
        }
        if (checklistStableMinHeight > 0) {
            container.style.minHeight = `${checklistStableMinHeight}px`;
        }
        return;
    }

    container.style.minHeight = '';
    checklistStableMinHeight = Math.max(checklistStableMinHeight, Math.ceil(container.scrollHeight));
}

function queueChecklistContainerHeightSync() {
    requestAnimationFrame(() => {
        syncChecklistContainerHeight();
    });
}

function renderChangelog() {
    const container = document.getElementById('changelog-content');
    if (!container) {
        return;
    }

    container.innerHTML = CHANGELOG_ENTRIES.map(entry => `
        <section class="changelog-entry">
            <div class="changelog-entry-head">
                <div class="changelog-version">${escapeHtml(entry.version)}</div>
                <div class="changelog-date">${escapeHtml(entry.date)}</div>
            </div>
            <div class="changelog-summary">${escapeHtml(entry.summary)}</div>
            <ul class="changelog-list">
                ${entry.changes.map(change => `<li>${escapeHtml(change)}</li>`).join('')}
            </ul>
        </section>
    `).join('');
}

function openChangelog() {
    const modal = document.getElementById('changelog-modal');
    if (!modal) {
        return;
    }

    modal.hidden = false;
    document.body.classList.add('modal-open');
}

function closeChangelog() {
    const modal = document.getElementById('changelog-modal');
    if (!modal) {
        return;
    }

    modal.hidden = true;
    document.body.classList.remove('modal-open');
}

function getAetherSubcategoryId(expansion, zone) {
    return `aether_${expansion}_${zone}`.replace(/\W+/g, '_').toLowerCase();
}

function isAetherSubcategoryOpen(subcategoryId) {
    return openAetherSubcategories[subcategoryId] !== false;
}

function saveAetherSubcategoryState() {
    localStorage.setItem('ffxiv_aether_subcategories_open', JSON.stringify(openAetherSubcategories));
}

function toggleAetherSubcategory(subcategoryId) {
    const content = document.getElementById(`sublist-${subcategoryId}`);
    const button = document.getElementById(`subtoggle-${subcategoryId}`);
    if (!content) {
        return;
    }

    const shouldOpen = content.style.display === 'none';
    content.style.display = shouldOpen ? 'block' : 'none';
    openAetherSubcategories[subcategoryId] = shouldOpen;
    saveAetherSubcategoryState();

    if (button) {
        button.textContent = shouldOpen ? 'Hide' : 'Show';
    }
}

function setAllAetherSubcategories(isOpen) {
    document.querySelectorAll('.subcategory-content').forEach(content => {
        if (content.closest('.category-body')?.id === 'list-aether_currents') {
            content.style.display = isOpen ? 'block' : 'none';
        }
    });

    document.querySelectorAll('.subcategory-toggle').forEach(button => {
        if (button.closest('.category-body')?.id === 'list-aether_currents') {
            button.textContent = isOpen ? 'Hide' : 'Show';
        }
    });

    document.querySelectorAll('.subcategory').forEach(subcategory => {
        const subcategoryId = subcategory.dataset.subcategoryId;
        if (subcategoryId) {
            openAetherSubcategories[subcategoryId] = isOpen;
        }
    });

    saveAetherSubcategoryState();
}

function getWondrousSubcategoryId(groupTitle, groupMeta) {
    return `wondrous_${groupTitle}_${groupMeta}`.replace(/\W+/g, '_').toLowerCase();
}

function isWondrousSubcategoryOpen(subcategoryId) {
    return openWondrousSubcategories[subcategoryId] !== false;
}

function saveWondrousSubcategoryState() {
    localStorage.setItem('ffxiv_wondrous_subcategories_open', JSON.stringify(openWondrousSubcategories));
}

function toggleWondrousSubcategory(subcategoryId) {
    const content = document.getElementById(`sublist-${subcategoryId}`);
    const button = document.getElementById(`subtoggle-${subcategoryId}`);
    if (!content) {
        return;
    }

    const shouldOpen = content.style.display === 'none';
    content.style.display = shouldOpen ? 'block' : 'none';
    openWondrousSubcategories[subcategoryId] = shouldOpen;
    saveWondrousSubcategoryState();

    if (button) {
        button.textContent = shouldOpen ? 'Hide' : 'Show';
    }
}

function setAllWondrousSubcategories(isOpen) {
    document.querySelectorAll('.subcategory-content').forEach(content => {
        if (content.closest('.category-body')?.id === 'list-weekly_content') {
            content.style.display = isOpen ? 'block' : 'none';
        }
    });

    document.querySelectorAll('.subcategory-toggle').forEach(button => {
        if (button.closest('.category-body')?.id === 'list-weekly_content') {
            button.textContent = isOpen ? 'Hide' : 'Show';
        }
    });

    document.querySelectorAll('.subcategory').forEach(subcategory => {
        if (subcategory.closest('.category-body')?.id !== 'list-weekly_content') {
            return;
        }

        const subcategoryId = subcategory.dataset.subcategoryId;
        if (subcategoryId) {
            openWondrousSubcategories[subcategoryId] = isOpen;
        }
    });

    saveWondrousSubcategoryState();
}

function renderChecklistItem(item, categoryId) {
    let badgesHtml = '';
    let titleHtml = '';
    let unlockHtml = '';
    let locHtml = '';
    let infoHtml = '';

    if (item.is_aether_current) {
        badgesHtml += `<span class="badge type">${escapeHtml(item.type)}</span>`;
        if (item.subtype) badgesHtml += `<span class="badge expansion">${escapeHtml(item.subtype)}</span>`;
        if (item.expansion) badgesHtml += `<span class="badge expansion">${escapeHtml(item.expansion)}</span>`;
        if (item.level) badgesHtml += `<span class="badge ilvl">Lvl ${escapeHtml(item.level)}</span>`;
        if (item.number) badgesHtml += `<span class="badge current">#${escapeHtml(item.number)}</span>`;
        if (item.map_number) badgesHtml += `<span class="badge map">Map ${escapeHtml(item.map_number)}</span>`;

        titleHtml = normalizeParts(item.quest_parts).length > 0
            ? renderTextParts(item.quest_parts, item.primary)
            : escapeHtml(item.primary);
        locHtml = item.location
            ? `<div class="content-loc">Coordinates: ${escapeHtml(item.location)}</div>`
            : '';
        infoHtml = (item.information_html || item.information)
            ? `<div class="content-desc">${renderTrustedHtml(item.information_html, item.information)}</div>`
            : '';
    } else if (item.is_wondrous_tail) {
        badgesHtml += `<span class="badge type">Wondrous Tails</span>`;
        if (item.type) badgesHtml += `<span class="badge expansion">${escapeHtml(item.type)}</span>`;
        if (item.level) badgesHtml += `<span class="badge ilvl">Lvl ${escapeHtml(item.level)}</span>`;

        titleHtml = normalizeParts(item.unlock_parts).length > 0
            ? renderTextParts(item.unlock_parts, item.primary)
            : escapeHtml(item.primary);
        unlockHtml = item.secondary_html
            ? `<div class="content-quest">${escapeHtml(item.secondary_label || 'Details')}: ${renderTrustedHtml(item.secondary_html, '')}</div>`
            : '';
        locHtml = item.location
            ? `<div class="content-loc">Location: ${escapeHtml(item.location)}</div>`
            : '';
        infoHtml = (item.information_html || item.information)
            ? `<div class="content-desc">${renderTrustedHtml(item.information_html, item.information)}</div>`
            : '';
    } else {
        if (item.type) badgesHtml += `<span class="badge type">${escapeHtml(item.type)}</span>`;
        if (item.ilevel && item.ilevel !== '-') badgesHtml += `<span class="badge ilvl">iLvl ${escapeHtml(item.ilevel)}</span>`;

        const hasQuest = normalizeParts(item.quest_parts).length > 0;
        titleHtml = hasQuest
            ? renderTextParts(item.quest_parts, item.primary)
            : renderTextParts(item.unlock_parts, item.primary);
        unlockHtml = hasQuest
            ? `<div class="content-quest">Unlock: ${renderTextParts(item.unlock_parts, item.secondary_unlock || item.unlock)}</div>`
            : '';
        locHtml = item.location
            ? `<div class="content-loc">Location: ${renderLocationParts(item.location_parts, item.location)}</div>`
            : '';
        infoHtml = (item.information_html || item.information)
            ? `<div class="content-desc">${renderTrustedHtml(item.information_html, item.information)}</div>`
            : '';
    }

    const searchHaystack = [
        item.unlock,
        item.quest,
        item.location,
        item.type,
        item.information,
        item.expansion,
        item.zone,
        item.subtype,
        item.primary,
        item.subcategory_title,
        item.subcategory_meta
    ].join(' ').toLowerCase();

    const subcategoryId = item.subcategory_id || item.aether_subcategory_id || '';
    const subcategoryAttr = subcategoryId
        ? ` data-subcategory-id="${escapeAttr(subcategoryId)}"`
        : '';

    return `
        <li class="checklist-item ${savedState[item.id] ? 'completed' : ''}" id="item-${item.cleanId}" data-search="${escapeAttr(searchHaystack)}" data-type="${escapeAttr(item.type || '')}"${subcategoryAttr}>
            <div class="checkbox-wrapper">
                <input type="checkbox"
                       class="item-checkbox"
                       id="check-${item.cleanId}"
                       data-category-id="${escapeAttr(categoryId)}"
                       data-original-id="${escapeAttr(item.id)}"
                       data-clean-id="${escapeAttr(item.cleanId)}"
                       ${savedState[item.id] ? 'checked' : ''}
                       >
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
}

function renderAetherSubcategories(items, categoryId) {
    const groups = new Map();

    items.forEach(item => {
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

        groups.get(key).items.push(item);
    });

    return Array.from(groups.values())
        .sort((a, b) => {
            if (a.expansionOrder !== b.expansionOrder) return a.expansionOrder - b.expansionOrder;
            if (a.zoneOrder !== b.zoneOrder) return a.zoneOrder - b.zoneOrder;
            return a.zone.localeCompare(b.zone);
        })
        .map(group => {
            const subcategoryId = getAetherSubcategoryId(group.expansion, group.zone);
            const isOpen = isAetherSubcategoryOpen(subcategoryId);
            group.items.sort((a, b) => (a.item_order || 999) - (b.item_order || 999));
            group.items.forEach(item => {
                item.subcategory_id = subcategoryId;
            });
            const completedCount = group.items.filter(item => savedState[item.id]).length;
            const itemsHtml = group.items.map(item => renderChecklistItem(item, categoryId)).join('');

            return `
                <section class="subcategory" data-subcategory="${escapeAttr(group.key)}" data-subcategory-id="${escapeAttr(subcategoryId)}">
                    <div class="subcategory-header" onclick="toggleAetherSubcategory('${escapeAttr(subcategoryId)}')">
                        <div>
                            <div class="subcategory-title">${escapeHtml(group.zone)}</div>
                            <div class="subcategory-meta">${escapeHtml(group.expansion)}</div>
                        </div>
                        <div class="subcategory-header-right">
                            <div class="subcategory-stats" id="substats-${subcategoryId}">${completedCount} / ${group.items.length}</div>
                            <button type="button" class="subcategory-toggle" id="subtoggle-${subcategoryId}">${isOpen ? 'Hide' : 'Show'}</button>
                        </div>
                    </div>
                    <div class="subcategory-content" id="sublist-${subcategoryId}" style="display:${isOpen ? 'block' : 'none'};">
                        <ul class="checklist">
                            ${itemsHtml}
                        </ul>
                    </div>
                </section>
            `;
        })
        .join('');
}

function renderWondrousSubcategories(items, categoryId) {
    const groups = new Map();

    items.forEach(item => {
        const key = `${item.subcategory_title}|${item.subcategory_meta}`;
        if (!groups.has(key)) {
            groups.set(key, {
                key,
                title: item.subcategory_title || 'General',
                meta: item.subcategory_meta || '',
                order: item.subcategory_order || 999,
                items: []
            });
        }

        groups.get(key).items.push(item);
    });

    return Array.from(groups.values())
        .sort((a, b) => {
            if (a.order !== b.order) return a.order - b.order;
            return a.title.localeCompare(b.title);
        })
        .map(group => {
            const subcategoryId = getWondrousSubcategoryId(group.title, group.meta);
            const isOpen = isWondrousSubcategoryOpen(subcategoryId);
            group.items.sort((a, b) => (a.item_order || 999) - (b.item_order || 999));
            group.items.forEach(item => {
                item.subcategory_id = subcategoryId;
            });
            const completedCount = group.items.filter(item => savedState[item.id]).length;
            const itemsHtml = group.items.map(item => renderChecklistItem(item, categoryId)).join('');

            return `
                <section class="subcategory" data-subcategory="${escapeAttr(group.key)}" data-subcategory-id="${escapeAttr(subcategoryId)}">
                    <div class="subcategory-header" onclick="toggleWondrousSubcategory('${escapeAttr(subcategoryId)}')">
                        <div>
                            <div class="subcategory-title">${escapeHtml(group.title)}</div>
                            <div class="subcategory-meta">${escapeHtml(group.meta)}</div>
                        </div>
                        <div class="subcategory-header-right">
                            <div class="subcategory-stats" id="substats-${subcategoryId}">${completedCount} / ${group.items.length}</div>
                            <button type="button" class="subcategory-toggle" id="subtoggle-${subcategoryId}">${isOpen ? 'Hide' : 'Show'}</button>
                        </div>
                    </div>
                    <div class="subcategory-content" id="sublist-${subcategoryId}" style="display:${isOpen ? 'block' : 'none'};">
                        <ul class="checklist">
                            ${itemsHtml}
                        </ul>
                    </div>
                </section>
            `;
        })
        .join('');
}

function updateAetherSubcategoryStats(subcategoryId) {
    if (!subcategoryId) {
        return;
    }

    const section = document.querySelector(`.subcategory[data-subcategory-id="${subcategoryId}"]`);
    const statsEl = document.getElementById(`substats-${subcategoryId}`);
    if (!section || !statsEl || section.closest('.category-body')?.id !== 'list-aether_currents') {
        return;
    }

    const items = Array.from(section.querySelectorAll('.checklist-item'));
    const completedCount = items.filter(item => item.classList.contains('completed')).length;
    statsEl.innerText = `${completedCount} / ${items.length}`;
}

function updateWondrousSubcategoryStats(subcategoryId) {
    if (!subcategoryId) {
        return;
    }

    const section = document.querySelector(`.subcategory[data-subcategory-id="${subcategoryId}"]`);
    const statsEl = document.getElementById(`substats-${subcategoryId}`);
    if (!section || !statsEl || section.closest('.category-body')?.id !== 'list-weekly_content') {
        return;
    }

    const items = Array.from(section.querySelectorAll('.checklist-item'));
    const completedCount = items.filter(item => item.classList.contains('completed')).length;
    statsEl.innerText = `${completedCount} / ${items.length}`;
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

        const bodyHtml = category.title === 'Aether Currents'
            ? renderAetherSubcategories(category.items, category.id)
            : category.title === 'Weekly Content'
                ? renderWondrousSubcategories(category.items, category.id)
                : `<ul class="checklist">${category.items.map(item => renderChecklistItem(item, category.id)).join('')}</ul>`;

        categoryEl.innerHTML = `
            <div class="category-header" onclick="toggleCategory('${category.id}')">
                <div class="category-title">${escapeHtml(category.title)}</div>
                <div class="category-stats" id="stats-${category.id}">
                    ${completedCount} / ${totalCount}
                </div>
            </div>
            <div class="category-body" id="list-${category.id}">
                ${bodyHtml}
            </div>
        `;
        container.appendChild(categoryEl);
    });

    updateMainProgress();
    filterItems();
    queueChecklistContainerHeightSync();
}

function toggleItem(categoryId, originalId, cleanId) {
    const checkbox = document.getElementById(`check-${cleanId}`);
    const itemEl = document.getElementById(`item-${cleanId}`);

    savedState[originalId] = checkbox.checked;
    localStorage.setItem('ffxiv_checklist_state', JSON.stringify(savedState));

    if (checkbox.checked) itemEl.classList.add('completed');
    else itemEl.classList.remove('completed');

    updateCategoryStats(categoryId);
    updateAetherSubcategoryStats(itemEl?.dataset?.subcategoryId || '');
    updateWondrousSubcategoryStats(itemEl?.dataset?.subcategoryId || '');
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
    const body = document.getElementById(`list-${categoryId}`);
    if (!body) return;
    const category = body.closest('.category');
    if (!category) return;
    const shouldOpen = category.classList.contains('collapsed');
    category.classList.toggle('collapsed', !shouldOpen);
    queueChecklistContainerHeightSync();
}

function expandAll() {
    groupedData.forEach(category => {
        const body = document.getElementById(`list-${category.id}`);
        if (body) {
            body.closest('.category')?.classList.remove('collapsed');
        }
    });
    setAllAetherSubcategories(true);
    setAllWondrousSubcategories(true);
    queueChecklistContainerHeightSync();
}

function collapseAll() {
    groupedData.forEach(category => {
        const body = document.getElementById(`list-${category.id}`);
        if (body) {
            body.closest('.category')?.classList.add('collapsed');
        }
    });
    setAllAetherSubcategories(false);
    setAllWondrousSubcategories(false);
    queueChecklistContainerHeightSync();
}

function resetProgress() {
    if (confirm('Are you sure you want to reset all progress?')) {
        savedState = {};
        localStorage.removeItem('ffxiv_checklist_state');
        renderChecklist();
    }
}

function filterItems() {
    const searchInput = document.getElementById('search-input');
    const searchTerm = searchInput.value.toLowerCase();
    const typeTerm = document.getElementById('type-filter').value;

    updateSearchClearButton();

    document.querySelectorAll('.checklist-item').forEach(el => {
        const matchesSearch = el.dataset.search.includes(searchTerm);
        const matchesType = !typeTerm || el.dataset.type === typeTerm;
        const isCompleted = el.classList.contains('completed');
        el.style.display = (matchesSearch && matchesType && (showCompleted || !isCompleted)) ? 'flex' : 'none';
    });

    document.querySelectorAll('.subcategory').forEach(subcategory => {
        const hasVisible = Array.from(subcategory.querySelectorAll('.checklist-item')).some(li => li.style.display !== 'none');
        subcategory.style.display = hasVisible ? 'block' : 'none';
    });

    groupedData.forEach(category => {
        const body = document.getElementById(`list-${category.id}`);
        if (!body) return;

        const hasVisible = Array.from(body.querySelectorAll('.checklist-item')).some(li => li.style.display !== 'none');
        body.parentElement.style.display = hasVisible ? 'block' : 'none';
    });

    queueChecklistContainerHeightSync();
}

async function initializeApp() {
    setChecklistStatus('Loading content...');

    try {
        renderChangelog();
        await loadContentData();
        populateTypeFilter();
        updateCompletedToggleButton();
        updateSearchClearButton();
        renderChecklist();
    } catch (error) {
        console.error(error);
        setChecklistStatus('Could not load content from the local JSON files.', true);
    }
}

document.addEventListener('change', (event) => {
    const checkbox = event.target.closest('.item-checkbox');
    if (!checkbox) {
        return;
    }

    toggleItem(
        checkbox.dataset.categoryId || '',
        checkbox.dataset.originalId || '',
        checkbox.dataset.cleanId || ''
    );
});

document.addEventListener('click', (event) => {
    if (event.target.closest('#open-changelog-btn')) {
        openChangelog();
        return;
    }

    if (event.target.closest('#close-changelog-btn')) {
        closeChangelog();
        return;
    }

    const modal = document.getElementById('changelog-modal');
    if (modal && event.target === modal) {
        closeChangelog();
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        closeChangelog();
    }
});

document.addEventListener('DOMContentLoaded', initializeApp);


