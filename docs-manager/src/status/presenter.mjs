const STATUS_LABELS = {
  seeded: 'Seeded',
  discussion: 'Discussion',
  locked: 'Locked',
  in_progress: 'In Progress',
  implementing: 'Implementing',
  implemented: 'Implemented',
  blocked: 'Blocked',
  abandoned: 'Abandoned',
  unknown: 'Unknown',
};

export function groupDashboardItems(items) {
  return {
    designPlans: items.filter((item) => item.sourceType === 'design-plan'),
    companySpecs: items.filter((item) => item.sourceType === 'company-spec'),
  };
}

export function statusLabel(status) {
  return STATUS_LABELS[status] ?? 'Unknown';
}

export function stageLabel(item) {
  if (item.blockers.length > 0) return 'Needs attention';
  if (item.status === 'implemented') return 'Done';
  if (item.status === 'locked') return 'Ready';
  if (item.tasks.total > 0) return 'Execution';
  if (item.status === 'discussion' || item.status === 'seeded') return 'Refinement';
  return 'Unknown';
}

export function nextCommand(item) {
  if (item.sourceType === 'design-plan') {
    if (item.status === 'seeded' || item.status === 'discussion' || item.status === 'unknown') {
      return `refinement ${item.id}`;
    }
    if (item.status === 'locked' && item.tasks.total === 0) return `breakdown ${item.id}`;
    if (item.status === 'locked') return `做 ${item.id}-T1`;
    return `review ${item.id}`;
  }

  if (item.blockers.includes('missing-primary-artifact')) return `refinement ${item.id}`;
  if (item.tasks.total === 0) return `breakdown ${item.id}`;
  return `做 ${item.id}`;
}

export function primaryLink(item, base = '/docs-manager') {
  if (!item.artifact) return null;
  const route = item.artifact.path.replace(/\.md$/, '').toLowerCase();
  return `${trimBase(base)}/specs/${route}/`;
}

export function taskSummary(item) {
  const tasks = item.tasks;
  if (tasks.total === 0) return '0';
  return [
    `${tasks.total} total`,
    `${tasks.byStatus.implemented} done`,
    `${tasks.byStatus.in_progress} active`,
    `${tasks.byStatus.blocked} blocked`,
    `${tasks.byStatus.unknown} unknown`,
  ].join(' / ');
}

export function blockerSummary(item) {
  return item.blockers.length > 0 ? item.blockers.join(', ') : '-';
}

function trimBase(base) {
  return base.endsWith('/') ? base.slice(0, -1) : base;
}
