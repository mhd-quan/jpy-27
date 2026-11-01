// Keeps the day map in step with the timeline: whatever is being read is highlighted on the
// map (a leg is fitted, a stop is centred, a suggestion shows the way to it).
import type { TripMap } from '../lib/map';
import { watchReading } from './reading';

export function initDaySync() {
  const items = [...document.querySelectorAll<HTMLElement>('.timeline > li[data-leg], .timeline > li[data-pin], .along-list > li[data-detour]')];
  const column = document.querySelector<HTMLElement>('.day-col');
  const aside = document.querySelector<HTMLElement>('.day-map');
  let map: TripMap | undefined;
  let current: HTMLElement | null = null;
  let userMovedAt = 0;

  const apply = (el: HTMLElement | null) => {
    if (!map || el === current) return;
    current?.classList.remove('is-active');
    current = el;
    if (!el) {
      map.clear();
      map.focusPin(null);
      map.fit();
      return;
    }
    el.classList.add('is-active');
    // Don't fight the person if they just panned the map themselves.
    const fly = performance.now() - userMovedAt > 4000;
    if (el.dataset.detour) {
      map.focusPin(null);
      map.clear();
      map.highlightDetour(el.dataset.detour, fly);
    } else if (el.dataset.leg) {
      map.focusPin(null);
      map.highlightLeg(el.dataset.leg, fly);
    } else if (el.dataset.pin) {
      map.clear();
      if (fly) map.focusPin(el.dataset.pin);
    }
  };

  // On phones the map sits above the text, so the line goes just under it, where the eye is;
  // beside the text it sits a little above the middle of the screen.
  const reading = column
    ? watchReading(items, {
        column,
        covers: () => [document.querySelector('.nav'), document.querySelector('.days-strip'), aside],
        share: (stacked) => (stacked ? 0.2 : 0.4),
        onChange: apply,
      })
    : null;

  const attach = () => {
    map = window.__maps?.day;
    if (!map) return;
    reading?.reset();
    map.map.on('dragstart', () => (userMovedAt = performance.now()));
    map.map.on('zoomstart', (e) => {
      if ((e as { originalEvent?: Event }).originalEvent) userMovedAt = performance.now();
    });
  };
  if (window.__maps?.day) attach();
  window.addEventListener('map-ready', (e) => {
    if ((e as CustomEvent<string>).detail === 'day') attach();
  });

  // Pointing at a suggestion shows the way to it, wherever it sits on screen.
  for (const li of items.filter((i) => i.dataset.detour)) {
    li.addEventListener('pointerenter', (e) => {
      if (e.pointerType !== 'mouse' || !map) return;
      userMovedAt = 0;
      apply(li);
    });
  }

  // Tapping a transit row fits that leg even if it is not centred.
  document.addEventListener('click', (e) => {
    const btn = (e.target as HTMLElement).closest<HTMLElement>('[data-focus-leg]');
    if (btn && map) {
      userMovedAt = 0;
      current?.classList.remove('is-active');
      current = btn.closest('li');
      current?.classList.add('is-active');
      map.highlightLeg(btn.dataset.focusLeg!, true);
      if (aside?.dataset.collapsed === 'true') toggle(false);
    }
  });

  const fitBtn = document.querySelector<HTMLButtonElement>('[data-map-fit]');
  fitBtn?.addEventListener('click', () => {
    userMovedAt = performance.now();
    map?.clear();
    map?.fit();
  });

  const toggleBtn = document.querySelector<HTMLButtonElement>('[data-map-toggle]');
  const toggle = (collapse: boolean) => {
    if (!aside || !toggleBtn) return;
    aside.dataset.collapsed = String(collapse);
    toggleBtn.textContent = collapse ? 'Mở bản đồ' : 'Thu bản đồ';
    toggleBtn.setAttribute('aria-expanded', String(!collapse));
    setTimeout(() => {
      map?.map.resize();
      reading?.refresh();
    }, 340);
  };
  toggleBtn?.addEventListener('click', () => toggle(aside?.dataset.collapsed !== 'true'));
}
