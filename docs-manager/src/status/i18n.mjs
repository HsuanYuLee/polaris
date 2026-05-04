import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const docsManagerRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const workspaceRoot = path.resolve(docsManagerRoot, '..');

const SUPPORTED_LOCALES = new Set(['en', 'zh-TW']);

const DICTIONARIES = {
  en: {
    'locale.label': 'English',
    'nav.home': 'Home',
    'nav.quickStart': 'Quick Start',
    'nav.statusDashboard': 'Status Dashboard',
    'page.title': 'Status Dashboard',
    'page.description': 'Active Polaris specs, design plans, blockers, and suggested next commands.',
    'section.designPlans': 'Design Plans',
    'section.companySpecs': 'Company Specs',
    'toolchain.title': 'Toolchain Health',
    'toolchain.failMessage': 'Required Polaris runtime tools are missing or incomplete.',
    'toolchain.okMessage': 'Required Polaris runtime tools are installed.',
    'toolchain.repairLabel': 'Repair',
    'toolchain.check.manifest': 'Root toolchain manifest',
    'toolchain.check.runner': 'Toolchain runner',
    'toolchain.check.docs.viewer': 'docs.viewer dependencies',
    'toolchain.check.tools.package': 'tools/polaris-toolchain package',
    'toolchain.check.tools.dependencies': 'Playwright and Mockoon dependencies',
    'navSync.title': 'Navigation Sync',
    'navSync.message':
      'Status Dashboard reads specs at runtime. Sidebar navigation is built by Starlight; reload the viewer after adding or moving specs.',
    'navSync.reloadLabel': 'Reload',
    'meta.activeItems': '{count} active items',
    'empty.noActiveItems': 'No active items',
    'table.source': 'Source',
    'table.title': 'Title',
    'table.status': 'Status',
    'table.stage': 'Stage',
    'table.tasks': 'Tasks',
    'table.blockers': 'Blockers',
    'table.nextCommand': 'Next Command',
    'status.seeded': 'Seeded',
    'status.discussion': 'Discussion',
    'status.locked': 'Locked',
    'status.in_progress': 'In Progress',
    'status.implementing': 'Implementing',
    'status.implemented': 'Implemented',
    'status.blocked': 'Blocked',
    'status.abandoned': 'Abandoned',
    'status.unknown': 'Unknown',
    'stage.needsAttention': 'Needs attention',
    'stage.done': 'Done',
    'stage.ready': 'Ready',
    'stage.execution': 'Execution',
    'stage.refinement': 'Refinement',
    'stage.unknown': 'Unknown',
    'tasks.total': '{count} total',
    'tasks.done': '{count} done',
    'tasks.active': '{count} active',
    'tasks.blocked': '{count} blocked',
    'tasks.unknown': '{count} unknown',
    'command.workOn': 'work on {id}',
    'command.inspectBlocker': 'inspect blocker {id}',
  },
  'zh-TW': {
    'locale.label': '繁體中文',
    'nav.home': '首頁',
    'nav.quickStart': '快速開始',
    'nav.statusDashboard': '狀態儀表板',
    'page.title': '狀態儀表板',
    'page.description': '顯示 Polaris specs、設計計畫、阻塞與建議下一步指令。',
    'section.designPlans': '設計計畫',
    'section.companySpecs': '公司規格',
    'toolchain.title': '工具鏈健康狀態',
    'toolchain.failMessage': '必要的 Polaris runtime 工具缺失或安裝不完整。',
    'toolchain.okMessage': '必要的 Polaris runtime 工具已安裝。',
    'toolchain.repairLabel': '修復',
    'toolchain.check.manifest': 'Root toolchain manifest',
    'toolchain.check.runner': 'Toolchain runner',
    'toolchain.check.docs.viewer': 'docs.viewer dependencies',
    'toolchain.check.tools.package': 'tools/polaris-toolchain package',
    'toolchain.check.tools.dependencies': 'Playwright 與 Mockoon dependencies',
    'navSync.title': '導覽同步',
    'navSync.message':
      '狀態儀表板會在 runtime 讀取 specs。左側導覽由 Starlight 建置；新增或移動 specs 後請重新載入 viewer。',
    'navSync.reloadLabel': '重新載入',
    'meta.activeItems': '{count} 個 active items',
    'empty.noActiveItems': '沒有 active items',
    'table.source': '來源',
    'table.title': '標題',
    'table.status': '狀態',
    'table.stage': '階段',
    'table.tasks': '任務',
    'table.blockers': '阻塞',
    'table.nextCommand': '下一步指令',
    'status.seeded': '已建 Seed',
    'status.discussion': '討論中',
    'status.locked': '已鎖定',
    'status.in_progress': '進行中',
    'status.implementing': '實作中',
    'status.implemented': '已完成',
    'status.blocked': '阻塞',
    'status.abandoned': '已放棄',
    'status.unknown': '未知',
    'stage.needsAttention': '需處理',
    'stage.done': '完成',
    'stage.ready': '可拆工',
    'stage.execution': '執行中',
    'stage.refinement': '需求收斂',
    'stage.unknown': '未知',
    'tasks.total': '共 {count}',
    'tasks.done': '{count} 已完成',
    'tasks.active': '{count} 進行中',
    'tasks.blocked': '{count} 阻塞',
    'tasks.unknown': '{count} 未知',
    'command.workOn': '做 {id}',
    'command.inspectBlocker': '檢查 blocker {id}',
  },
};

export function resolveDocsManagerLocale(options = {}) {
  const rawLanguage = options.language ?? readWorkspaceLanguage(options.workspaceConfigPath);
  return normalizeLocale(rawLanguage);
}

export function createTranslator(locale = 'en') {
  const normalizedLocale = normalizeLocale(locale);
  return (key, values = {}) => translate(normalizedLocale, key, values);
}

export function translate(locale, key, values = {}, fallbackKey = undefined) {
  const normalizedLocale = normalizeLocale(locale);
  const message =
    DICTIONARIES[normalizedLocale]?.[key] ??
    DICTIONARIES.en[key] ??
    (fallbackKey ? translate(normalizedLocale, fallbackKey, values) : key);
  return interpolate(message, values);
}

export function starlightLocaleConfig(locale = 'en') {
  const normalizedLocale = normalizeLocale(locale);
  return {
    label: translate(normalizedLocale, 'locale.label'),
    lang: normalizedLocale,
  };
}

export function normalizeLocale(language) {
  if (!language) return 'en';
  const normalized = String(language).trim().replace(/^['"]|['"]$/g, '');
  if (SUPPORTED_LOCALES.has(normalized)) return normalized;

  const lower = normalized.toLowerCase().replace('_', '-');
  if (lower === 'zh' || lower === 'zh-tw' || lower === 'zh-hant' || lower === 'zh-hant-tw') {
    return 'zh-TW';
  }
  if (lower === 'en' || lower.startsWith('en-')) return 'en';
  return 'en';
}

function readWorkspaceLanguage(configPath = path.join(workspaceRoot, 'workspace-config.yaml')) {
  try {
    const source = fs.readFileSync(configPath, 'utf8');
    const match = source.match(/^\s*language:\s*([^#\n]+)/m);
    return match?.[1]?.trim();
  } catch {
    return undefined;
  }
}

function interpolate(message, values) {
  return message.replace(/\{([a-zA-Z0-9_]+)\}/g, (placeholder, key) =>
    Object.hasOwn(values, key) ? String(values[key]) : placeholder
  );
}
