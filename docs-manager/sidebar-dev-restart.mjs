import path from 'node:path';

const hiddenDirectoryNames = new Set(['assets', 'artifacts', 'escalations', 'refinement-inbox', 'tests']);
const watchedEvents = ['add', 'addDir', 'change', 'unlink', 'unlinkDir'];

export function affectsSpecsSidebar(file, event, specsRoot) {
  if (!file || !event || !specsRoot) return false;
  if (!watchedEvents.includes(event)) return false;

  const root = path.resolve(specsRoot);
  const absolute = path.resolve(file);
  const relative = path.relative(root, absolute);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) return false;

  const segments = relative.split(path.sep);
  if (segments.some((segment) => hiddenDirectoryNames.has(segment))) return false;
  if (path.basename(absolute) === '.DS_Store') return false;

  if (event === 'addDir' || event === 'unlinkDir') return true;
  return absolute.endsWith('.md');
}

export function specsSidebarDevRestartPlugin(specsRoot, { debounceMs = 250 } = {}) {
  return {
    name: 'polaris-specs-sidebar-dev-restart',
    apply: 'serve',
    configureServer(server) {
      server.watcher.add(specsRoot);

      let timer;
      let latestReason;
      let restarting = false;

      const scheduleRestart = (file, event) => {
        if (!affectsSpecsSidebar(file, event, specsRoot)) return;

        latestReason = { file, event };
        clearTimeout(timer);
        timer = setTimeout(async () => {
          if (restarting) return;
          restarting = true;
          const displayPath = path.relative(process.cwd(), latestReason.file);
          server.config.logger.info(
            `[polaris] specs sidebar source ${latestReason.event}: ${displayPath}; restarting dev server`
          );
          try {
            await server.restart();
          } finally {
            restarting = false;
          }
        }, debounceMs);
      };

      server.watcher.on('all', (event, file) => scheduleRestart(file, event));
    },
  };
}
