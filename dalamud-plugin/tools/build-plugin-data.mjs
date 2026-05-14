import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const toolDir = path.dirname(fileURLToPath(import.meta.url));
const pluginRoot = path.resolve(toolDir, "..");
const repoRoot = path.resolve(pluginRoot, "..");
const outputPath = path.join(pluginRoot, "VaelarisUnlockList", "Data", "unlockables.json");

const stripHtml = (value) =>
  String(value ?? "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&nbsp;/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const normalizeText = (value) => String(value ?? "").replace(/\s+/g, " ").trim();

const unique = (items) => {
  const seen = new Set();
  const result = [];
  for (const item of items) {
    const value = normalizeText(item);
    if (!value || seen.has(value.toLowerCase())) continue;
    seen.add(value.toLowerCase());
    result.push(value);
  }
  return result;
};

const readJson = async (relativePath) => {
  const fullPath = path.join(repoRoot, relativePath);
  const content = await readFile(fullPath, "utf8");
  return JSON.parse(content.replace(/^\uFEFF/, ""));
};

const parseCoordinateText = (text) => {
  const value = normalizeText(text);
  if (!value) return { text: "" };

  const x = /X:\s*(-?\d+(?:\.\d+)?)/i.exec(value)?.[1];
  const y = /Y:\s*(-?\d+(?:\.\d+)?)/i.exec(value)?.[1];
  const z = /Z:\s*(-?\d+(?:\.\d+)?)/i.exec(value)?.[1];

  return {
    text: value,
    x: x === undefined ? null : Number(x),
    y: y === undefined ? null : Number(y),
    z: z === undefined ? null : Number(z),
  };
};

const splitLocationFallback = (location) => {
  return String(location ?? "")
    .split(";")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const segments = part.split(":");
      const place = segments.length >= 4 ? segments.slice(3).join(":").trim() : "";
      return {
        place,
        ...parseCoordinateText(part),
      };
    });
};

const locationPartsToLocations = (parts, fallbackLocation = "") => {
  const locations = [];
  if (Array.isArray(parts) && parts.length) {
    for (const part of parts) {
      const parsed = parseCoordinateText(part.coords || part.display || fallbackLocation);
      locations.push({
        place: normalizeText(part.place || ""),
        text: normalizeText(part.display || `${part.coords || ""}${part.place ? `:${part.place}` : ""}`),
        x: parsed.x,
        y: parsed.y,
        z: parsed.z,
      });
    }
  }

  if (!locations.length) {
    locations.push(...splitLocationFallback(fallbackLocation));
  }

  return locations.filter((loc) => loc.text || loc.place || loc.x !== null || loc.y !== null);
};

const collectUrls = (...partLists) => {
  const urls = [];
  for (const parts of partLists) {
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (part?.url) urls.push(part.url);
      if (part?.href) urls.push(part.href);
    }
  }
  return unique(urls);
};

const questNamesFromParts = (item) => {
  const fromParts = Array.isArray(item.quest_parts)
    ? item.quest_parts.map((part) => part.text)
    : [];
  const fallback = String(item.quest ?? "")
    .split(/\s+\/\s+/)
    .map((part) => part.trim());
  return unique([...fromParts, ...fallback]);
};

const completionForQuests = (questNames, fallbackKind = "Manual") => {
  if (questNames.length) {
    return { kind: "Quest", questNames };
  }

  return { kind: fallbackKind, questNames: [] };
};

const fromContentUnlock = (item) => {
  const questNames = questNamesFromParts(item);
  return {
    id: `content:${item.id}`,
    source: "content-unlock",
    section: normalizeText(item.section),
    category: normalizeText(item.type || "Unlock"),
    subtype: "",
    title: normalizeText(item.primary || item.quest || item.unlock),
    unlockName: normalizeText(item.secondary_unlock || item.unlock || item.primary),
    questNames,
    level: normalizeText(item.ilevel),
    itemLevel: normalizeText(item.ilevel && item.ilevel !== "-" ? item.ilevel : ""),
    expansion: "",
    zone: normalizeText(item.location_parts?.[0]?.place || splitLocationFallback(item.location)?.[0]?.place || ""),
    locations: locationPartsToLocations(item.location_parts, item.location),
    instructions: stripHtml(item.information_html || item.information),
    wikiUrls: collectUrls(item.unlock_parts, item.quest_parts, item.location_parts),
    completion: completionForQuests(questNames),
  };
};

const fromAetherCurrent = (item) => {
  const questNames = questNamesFromParts(item);
  const parsed = parseCoordinateText(item.coordinates);
  const isField = item.entry_type === "Field";
  return {
    id: `aether:${item.id}`,
    source: "aether-currents",
    section: "Aether Currents",
    category: "Aether Current",
    subtype: normalizeText(item.entry_type),
    title: normalizeText(item.primary || item.quest || `Aether Current ${item.number || ""}`),
    unlockName: normalizeText(item.primary || item.quest),
    questNames,
    level: normalizeText(item.level),
    itemLevel: "",
    expansion: normalizeText(item.expansion),
    zone: normalizeText(item.zone),
    locations: [
      {
        place: normalizeText(item.zone),
        text: normalizeText(item.coordinates),
        x: parsed.x,
        y: parsed.y,
        z: parsed.z,
      },
    ].filter((loc) => loc.text || loc.x !== null || loc.y !== null),
    instructions: stripHtml(isField ? item.description_html || item.description : item.additional_information_html || item.additional_information),
    wikiUrls: collectUrls(item.quest_parts),
    completion: isField ? { kind: "AetherCurrent", questNames: [] } : completionForQuests(questNames),
  };
};

const fromWondrousTails = (item) => {
  const secondaryText = stripHtml(item.secondary_html);
  const questNames = /quest/i.test(item.secondary_label || "") && secondaryText ? [secondaryText] : [];
  return {
    id: `wondrous:${item.id}`,
    source: "wondrous-tails",
    section: "Weekly Content",
    category: "Wondrous Tails",
    subtype: normalizeText(item.subtype || item.type),
    title: normalizeText(item.primary),
    unlockName: normalizeText(item.primary),
    questNames,
    level: normalizeText(item.level),
    itemLevel: "",
    expansion: "",
    zone: splitLocationFallback(item.location)?.[0]?.place || "",
    locations: splitLocationFallback(item.location),
    instructions: stripHtml(item.information_html || item.information),
    wikiUrls: collectUrls(item.primary_parts),
    completion: completionForQuests(questNames),
  };
};

const [contentUnlocks, aetherCurrents, wondrousTails] = await Promise.all([
  readJson("data/content-unlock.json"),
  readJson("data/aether-currents.json"),
  readJson("data/wondrous-tails.json"),
]);

const items = [
  ...contentUnlocks.map(fromContentUnlock),
  ...aetherCurrents.map(fromAetherCurrent),
  ...wondrousTails.map(fromWondrousTails),
].map((item, index) => ({
  ...item,
  sortOrder: index + 1,
  gameData: {
    questId: null,
    territoryTypeId: null,
    mapId: null,
    aetherCurrentId: null,
    unlockLinkId: null,
  },
  locations: item.locations.map((loc) => ({
    place: normalizeText(loc.place),
    text: normalizeText(loc.text),
    x: Number.isFinite(loc.x) ? loc.x : null,
    y: Number.isFinite(loc.y) ? loc.y : null,
    z: Number.isFinite(loc.z) ? loc.z : null,
  })),
}));

const dataset = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  sourceFiles: [
    "data/content-unlock.json",
    "data/aether-currents.json",
    "data/wondrous-tails.json",
  ],
  notes: [
    "IDs are stable source IDs from the website data.",
    "Quest, territory, map, and aether current row IDs are resolved in the Dalamud plugin when possible.",
  ],
  items,
};

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(dataset, null, 2)}\n`, "utf8");

console.log(`Wrote ${items.length} unlockables to ${path.relative(repoRoot, outputPath)}`);
