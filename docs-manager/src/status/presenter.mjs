import { translate } from './i18n.mjs';

export function groupDashboardItems(items) {
  return {
    designPlans: items.filter((item) => item.sourceType === 'design-plan'),
    companySpecs: items.filter((item) => item.sourceType === 'company-spec'),
  };
}

export function statusLabel(status, locale = 'en') {
  return translate(locale, `status.${status}`, {}, 'status.unknown');
}

export function stageLabel(item, locale = 'en') {
  if (item.blockers.length > 0) return translate(locale, 'stage.needsAttention');
  if (item.status === 'implemented') return translate(locale, 'stage.done');
  if (item.status === 'locked') return translate(locale, 'stage.ready');
  if (item.tasks.total > 0) return translate(locale, 'stage.execution');
  if (item.status === 'discussion' || item.status === 'seeded') return translate(locale, 'stage.refinement');
  return translate(locale, 'stage.unknown');
}

export function nextCommand(item, locale = 'en') {
  if (item.sourceType === 'design-plan') {
    if (item.status === 'seeded' || item.status === 'discussion' || item.status === 'unknown') {
      return `refinement ${item.id}`;
    }
    if (item.status === 'locked' && item.tasks.total === 0) return `breakdown ${item.id}`;
    if (item.status === 'locked') return translate(locale, 'command.workOn', { id: `${item.id}-T1` });
    return `review ${item.id}`;
  }

  if (item.blockers.includes('missing-primary-artifact')) return `refinement ${item.id}`;
  if (item.tasks.total === 0) return `breakdown ${item.id}`;
  if (item.blockers.length > 0) return translate(locale, 'command.inspectBlocker', { id: item.id });
  return translate(locale, 'command.workOn', { id: item.id });
}

export function primaryLink(item, base = '/docs-manager') {
  if (!item.artifact) return null;
  const route = docRoute(item.artifact.path);
  return `${trimBase(base)}/specs/${route}/`;
}

export function verifyReportLink(item, base = '/docs-manager') {
  if (!item.verifyReport) return null;
  return `${trimBase(base)}/specs/${docRoute(item.verifyReport.path)}/`;
}

export function taskSummary(item, locale = 'en') {
  const tasks = item.tasks;
  if (tasks.total === 0) return '0';
  return [
    translate(locale, 'tasks.total', { count: tasks.total }),
    translate(locale, 'tasks.done', { count: tasks.byStatus.implemented }),
    translate(locale, 'tasks.active', { count: tasks.byStatus.in_progress }),
    translate(locale, 'tasks.blocked', { count: tasks.byStatus.blocked }),
    translate(locale, 'tasks.unknown', { count: tasks.byStatus.unknown }),
  ].join(' / ');
}

export function blockerSummary(item) {
  return item.blockers.length > 0 ? item.blockers.join(', ') : '-';
}

export function verificationSummary(item, locale = 'en') {
  const behavior = item.verification?.behaviorContract;
  const visual = item.verification?.visualRegression;
  const parts = [];

  if (behavior) {
    if (behavior.applies === false) {
      parts.push(translate(locale, 'verification.behavior.false'));
    } else if (behavior.applies === true) {
      parts.push(
        [
          translate(locale, `verification.behavior.mode.${behavior.mode}`),
          translate(locale, `verification.source.${behavior.source_of_truth}`),
          translate(locale, `verification.fixture.${behavior.fixture_policy}`),
        ].join(' / ')
      );
    }
  }

  if (visual) {
    parts.push(translate(locale, `verification.visual.${visual.expected}`));
  }

  return parts.length > 0 ? parts.join(' / ') : translate(locale, 'verification.none');
}

export function reportSummary(item, locale = 'en') {
  return item.verifyReport ? translate(locale, 'report.latest') : translate(locale, 'report.none');
}

export function publicationSummary(item, locale = 'en') {
  return translate(locale, `publication.${item.publication?.status ?? 'not_available'}`);
}

function docRoute(markdownPath) {
  const route = markdownPath.replace(/\.md$/, '').toLowerCase();
  return route.endsWith('/index') ? route.slice(0, -'/index'.length) : route;
}

function trimBase(base) {
  return base.endsWith('/') ? base.slice(0, -1) : base;
}
