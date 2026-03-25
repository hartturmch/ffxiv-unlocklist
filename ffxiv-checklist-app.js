const CONTENT_API_URL = 'data/content-unlock.json';
const OPEN_SECTIONS_KEY = 'ffxiv_content_unlock_open_sections';
const STORAGE_KEY = 'ffxiv-content-unlock-checklist-v5';

let DATA = [];
let state = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{"done":[],"showCompleted":false,"search":"","section":"","type":"","sortBy":"section"}');
state.done = new Set(state.done || []);

const $ = id => document.getElementById(id);
const els = {
  search: $('search'),
  sectionFilter: $('sectionFilter'),
  typeFilter: $('typeFilter'),
  sortBy: $('sortBy'),
  toggleCompleted: $('toggleCompleted'),
  clearProgress: $('clearProgress'),
  exportProgress: $('exportProgress'),
  app: $('app'),
  totalCount: $('totalCount'),
  doneCount: $('doneCount'),
  visibleCount: $('visibleCount'),
  progressCount: $('progressCount')
};

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

function save() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify({
    done: [...state.done],
    showCompleted: state.showCompleted,
    search: els.search.value,
    section: els.sectionFilter.value,
    type: els.typeFilter.value,
    sortBy: els.sortBy.value
  }));
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

function populateFilters() {
  els.sectionFilter.innerHTML = '<option value="">Todas as seções</option>';
  els.typeFilter.innerHTML = '<option value="">All types</option>';

  const sections = [...new Set(DATA.map(item => item.section).filter(Boolean))].sort((a, b) => {
    const sa = sectionOrderValue(a);
    const sb = sectionOrderValue(b);
    return sa === sb ? a.localeCompare(b) : sa - sb;
  });

  const types = [...new Set(DATA.map(item => item.type).filter(Boolean))].sort((a, b) => a.localeCompare(b));

  for (const section of sections) {
    const option = document.createElement('option');
    option.value = section;
    option.textContent = section;
    els.sectionFilter.appendChild(option);
  }

  for (const type of types) {
    const option = document.createElement('option');
    option.value = type;
    option.textContent = type;
    els.typeFilter.appendChild(option);
  }
}

function textHit(item, q) {
  const hay = [item.primary, item.secondary_unlock, item.unlock, item.quest, item.type, item.location, item.information, item.section, item.ilevel].join(' ').toLowerCase();
  return hay.includes(q);
}

function matches(item) {
  const q = (els.search.value || '').trim().toLowerCase();
  if (q && !textHit(item, q)) return false;
  if (els.sectionFilter.value && item.section !== els.sectionFilter.value) return false;
  if (els.typeFilter.value && item.type !== els.typeFilter.value) return false;
  if (!state.showCompleted && state.done.has(item.id)) return false;
  return true;
}

function parseIlevelValue(v) {
  if (v === undefined || v === null) return Number.POSITIVE_INFINITY;
  const s = String(v).trim();
  if (!s || s === '-' || s === '—') return Number.POSITIVE_INFINITY;
  const nums = (s.match(/\d+(?:\.\d+)?/g) || []).map(Number);
  if (!nums.length) return Number.POSITIVE_INFINITY;
  return Math.min(...nums);
}

function sortItems(items) {
  const by = els.sortBy.value;
  return items.sort((a, b) => {
    if (by === 'quest') return (a.primary || '').localeCompare(b.primary || '');
    if (by === 'unlock') return (a.unlock || '').localeCompare(b.unlock || '');

    const sa = sectionOrderValue(a.section);
    const sb = sectionOrderValue(b.section);
    if (sa !== sb) return sa - sb;

    const ia = parseIlevelValue(a.ilevel);
    const ib = parseIlevelValue(b.ilevel);
    if (ia !== ib) return ia - ib;

    return (a.primary || '').localeCompare(b.primary || '');
  });
}

function field(label, value, isHtml = false) {
  const rendered = isHtml ? value : escapeHtml(value || '');
  const fallback = '<span class="muted">—</span>';
  return `<div class="field"><div class="label">${escapeHtml(label)}</div><div class="value">${rendered || fallback}</div></div>`;
}

function getOpenSections() {
  try {
    return JSON.parse(localStorage.getItem(OPEN_SECTIONS_KEY) || '[]');
  } catch (e) {
    return [];
  }
}

function setOpenSections(arr) {
  localStorage.setItem(OPEN_SECTIONS_KEY, JSON.stringify(Array.from(new Set(arr))));
}

function isSectionOpen(name) {
  return getOpenSections().includes(name);
}

function toggleSectionState(name, forceOpen = null) {
  const curr = new Set(getOpenSections());
  if (forceOpen === true) curr.add(name);
  else if (forceOpen === false) curr.delete(name);
  else if (curr.has(name)) curr.delete(name);
  else curr.add(name);
  setOpenSections([...curr]);
}

function showStatus(message, isError = false) {
  els.app.innerHTML = `<section class="section"><div class="sectionTitle"><strong style="color:${isError ? '#fda4af' : 'inherit'};">${escapeHtml(message)}</strong></div></section>`;
  els.totalCount.textContent = '0';
  els.doneCount.textContent = state.done.size;
  els.visibleCount.textContent = '0';
  els.progressCount.textContent = '0%';
}

function render() {
  const filtered = sortItems([...DATA].filter(matches));
  els.totalCount.textContent = DATA.length;
  els.doneCount.textContent = state.done.size;
  els.visibleCount.textContent = filtered.length;
  els.progressCount.textContent = Math.round((state.done.size / Math.max(DATA.length, 1)) * 100) + '%';
  els.toggleCompleted.textContent = state.showCompleted ? 'Hide completed' : 'Show completed';

  const groups = new Map();
  for (const item of filtered) {
    if (!groups.has(item.section)) groups.set(item.section, []);
    groups.get(item.section).push(item);
  }

  els.app.innerHTML = '';

  for (const [section, items] of groups) {
    const sec = document.createElement('section');
    sec.className = 'section';
    const openClass = isSectionOpen(section) ? ' open' : '';
    const btnText = isSectionOpen(section) ? 'Close' : 'Open';

    sec.innerHTML = `<div class="sectionTitle section-header" data-section="${escapeAttr(section)}"><strong>${escapeHtml(section)}</strong><span style="display:flex;align-items:center;gap:10px;"><span>${items.length} item(s)</span><button type="button" class="section-toggle" aria-label="Open or close section">${btnText}</button></span></div><div class="section-content${openClass}"><div class="list"></div></div>`;

    const list = sec.querySelector('.list');
    for (const item of items) {
      const article = document.createElement('article');
      article.className = 'card' + (state.done.has(item.id) ? ' done' : '');
      const titleHtml = (normalizeParts(item.quest_parts).length)
        ? renderTextParts(item.quest_parts, item.primary)
        : renderTextParts(item.unlock_parts, item.primary);
      const unlockHtml = renderTextParts(item.unlock_parts, item.secondary_unlock || item.unlock);
      const locationHtml = renderLocationParts(item.location_parts, item.location);
      const typeHtml = escapeHtml(item.type || '');
      const infoHtml = renderTrustedHtml(item.information_html, item.information);

      article.innerHTML = `<div class="check"><input type="checkbox" ${state.done.has(item.id) ? 'checked' : ''} aria-label="Marcar concluído"></div>
      <div>
        <div class="mainTitle">${titleHtml}</div>
        <div class="chips">${item.ilevel ? `<span class="chip">${escapeHtml(item.ilevel)}</span>` : ''}${item.type ? `<span class="chip">${typeHtml}</span>` : ''}${item.secondary_unlock ? `<span class="chip">Unlock: ${escapeHtml(item.secondary_unlock)}</span>` : ''}</div>
        <div class="fields">
          ${field('Unlock', unlockHtml, true)}
          ${field('Location', locationHtml, true)}
          ${field('Type', typeHtml, true)}
          ${field('Information', infoHtml, true)}
        </div>
      </div>`;

      article.querySelector('input').addEventListener('change', e => {
        if (e.target.checked) state.done.add(item.id);
        else state.done.delete(item.id);
        save();
        render();
      });

      list.appendChild(article);
    }

    els.app.appendChild(sec);
  }
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
}

async function initApp() {
  showStatus('Loading content...');

  try {
    await loadContentData();
    populateFilters();
    els.search.value = state.search || '';
    els.sectionFilter.value = state.section || '';
    els.typeFilter.value = state.type || '';
    els.sortBy.value = state.sortBy || 'section';
    render();
  } catch (error) {
    console.error(error);
    showStatus('Could not load content from data/content-unlock.json.', true);
  }
}

['input', 'change'].forEach(ev => {
  els.search.addEventListener(ev, () => { save(); render(); });
  els.sectionFilter.addEventListener(ev, () => { save(); render(); });
  els.typeFilter.addEventListener(ev, () => { save(); render(); });
  els.sortBy.addEventListener(ev, () => { save(); render(); });
});

els.toggleCompleted.addEventListener('click', () => {
  state.showCompleted = !state.showCompleted;
  save();
  render();
});

els.clearProgress.addEventListener('click', () => {
  if (confirm('Limpar todo o progresso salvo?')) {
    state.done = new Set();
    save();
    render();
  }
});

els.exportProgress.addEventListener('click', () => {
  const blob = new Blob([JSON.stringify({ done: [...state.done] }, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'ffxiv-progress.json';
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 500);
});

document.addEventListener('click', function (e) {
  const header = e.target.closest('.section-header');
  if (!header) return;

  const clickedCheckbox = e.target.closest('input[type="checkbox"]');
  if (clickedCheckbox) return;

  const content = header.nextElementSibling;
  if (!content || !content.classList.contains('section-content')) return;

  const sectionName = header.getAttribute('data-section') || header.textContent.trim();
  const isOpen = content.classList.toggle('open');
  toggleSectionState(sectionName, isOpen);

  const btn = header.querySelector('.section-toggle');
  if (btn) btn.textContent = isOpen ? 'Close' : 'Open';
});

document.addEventListener('DOMContentLoaded', initApp);


