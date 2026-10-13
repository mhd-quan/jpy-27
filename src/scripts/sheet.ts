// Place detail sheet. On phones it is a bottom sheet driven by a critically damped
// spring: it follows the finger 1:1, keeps the release velocity, and projects the
// throw to decide between closing and settling back. On wider screens it is a card.

const DECEL = 0.998;
const project = (v: number) => ((v / 1000) * DECEL) / (1 - DECEL);
const rubber = (x: number, dim: number, c = 0.55) => (x * dim * c) / (dim + c * Math.abs(x));

function spring(
  from: number,
  to: number,
  v0: number,
  onFrame: (x: number) => void,
  { response = 0.38, damping = 1 } = {},
) {
  const k = (2 * Math.PI / response) ** 2;
  const c = (4 * Math.PI * damping) / response;
  let x = from;
  let v = v0;
  let last = performance.now();
  let raf = 0;
  let done: () => void = () => {};
  const finished = new Promise<void>((r) => (done = r));
  const step = (now: number) => {
    const dt = Math.min(0.032, (now - last) / 1000);
    last = now;
    const a = -k * (x - to) - c * v;
    v += a * dt;
    x += v * dt;
    if (Math.abs(x - to) < 0.4 && Math.abs(v) < 8) {
      onFrame(to);
      done();
      return;
    }
    onFrame(x);
    raf = requestAnimationFrame(step);
  };
  raf = requestAnimationFrame(step);
  return { stop: () => cancelAnimationFrame(raf), finished, velocity: () => v, value: () => x };
}

export function initSheet() {
  const dialog = document.getElementById('place-sheet') as HTMLDialogElement | null;
  if (!dialog || dialog.dataset.ready) return;
  dialog.dataset.ready = '1';
  const panel = dialog.querySelector<HTMLElement>('[data-panel]')!;
  const body = dialog.querySelector<HTMLElement>('[data-body]')!;
  const grab = dialog.querySelector<HTMLElement>('[data-grab]')!;
  const wide = () => matchMedia('(min-width: 760px)').matches;
  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

  let y = 0;
  let anim: ReturnType<typeof spring> | null = null;
  let opener: HTMLElement | null = null;
  const setY = (v: number) => {
    y = v;
    panel.style.transform = `translateY(${v}px)`;
  };
  const height = () => panel.getBoundingClientRect().height || window.innerHeight;

  const settle = (to: number, v = 0) => {
    anim?.stop();
    if (reduced()) {
      setY(to);
      return Promise.resolve();
    }
    anim = spring(y, to, v, setY, { response: 0.36, damping: 1 });
    return anim.finished;
  };

  function open(id: string, from?: HTMLElement | null) {
    const tpl = document.getElementById(`tpl-${id}`) as HTMLTemplateElement | null;
    if (!tpl) return false;
    opener = from ?? (document.activeElement as HTMLElement | null);
    body.replaceChildren(tpl.content.cloneNode(true));
    body.scrollTop = 0;
    if (!dialog!.open) dialog!.showModal();
    dialog!.classList.add('is-open');
    if (wide()) {
      panel.style.transform = '';
      panel.animate(
        [
          { opacity: 0, transform: 'translate(-50%, -46%) scale(0.97)' },
          { opacity: 1, transform: 'translate(-50%, -50%) scale(1)' },
        ],
        { duration: reduced() ? 1 : 320, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', fill: 'forwards' },
      );
    } else {
      if (!anim) setY(height());
      settle(0);
    }
    return true;
  }

  async function close(v = 0) {
    if (!dialog!.open) return;
    dialog!.classList.remove('is-open');
    if (wide()) {
      const a = panel.animate(
        [
          { opacity: 1, transform: 'translate(-50%, -50%) scale(1)' },
          { opacity: 0, transform: 'translate(-50%, -48%) scale(0.98)' },
        ],
        { duration: reduced() ? 1 : 200, easing: 'cubic-bezier(0.65, 0, 0.35, 1)', fill: 'forwards' },
      );
      await a.finished;
    } else {
      await settle(height(), v);
      anim = null;
    }
    dialog!.close();
    body.replaceChildren();
    opener?.focus?.({ preventScroll: true });
  }

  dialog.addEventListener('cancel', (e) => {
    e.preventDefault();
    close();
  });
  dialog.addEventListener('click', (e) => {
    if (e.target === dialog) close();
    if ((e.target as HTMLElement).closest('[data-close]')) close();
  });

  // Drag to dismiss: from the grab bar, or from the content when it is scrolled to the top.
  let startY = 0;
  let startSheetY = 0;
  let dragging = false;
  let samples: { t: number; y: number }[] = [];
  const onDown = (e: PointerEvent) => {
    if (wide() || e.button !== 0) return;
    const fromBody = body.contains(e.target as Node);
    if (fromBody && body.scrollTop > 0) return;
    if ((e.target as HTMLElement).closest('a, button, .track')) return;
    startY = e.clientY;
    startSheetY = y;
    dragging = false;
    samples = [{ t: e.timeStamp, y: e.clientY }];
    const move = (ev: PointerEvent) => {
      const dy = ev.clientY - startY;
      if (!dragging) {
        if (Math.abs(dy) < 8) return;
        if (fromBody && dy < 0) return cleanup();
        dragging = true;
        anim?.stop();
        panel.setPointerCapture(ev.pointerId);
      }
      ev.preventDefault();
      const raw = startSheetY + dy;
      setY(raw < 0 ? -rubber(-raw, height()) : raw);
      samples.push({ t: ev.timeStamp, y: ev.clientY });
      if (samples.length > 6) samples.shift();
    };
    const up = () => {
      cleanup();
      if (!dragging) return;
      const a = samples[0];
      const b = samples[samples.length - 1];
      const v = b.t > a.t ? ((b.y - a.y) / (b.t - a.t)) * 1000 : 0;
      const h = height();
      const projected = y + project(v);
      if (projected > h * 0.45 || v > 1100) close(v);
      else settle(0, v);
    };
    const cleanup = () => {
      panel.removeEventListener('pointermove', move);
      panel.removeEventListener('pointerup', up);
      panel.removeEventListener('pointercancel', up);
    };
    panel.addEventListener('pointermove', move, { passive: false });
    panel.addEventListener('pointerup', up);
    panel.addEventListener('pointercancel', up);
  };
  grab.addEventListener('pointerdown', onDown);
  body.addEventListener('pointerdown', onDown);

  // Anything marked data-place opens its sheet.
  document.addEventListener('click', (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>('[data-place]');
    if (!el || el.closest('dialog')) return;
    if (e.metaKey || e.ctrlKey) return;
    if (open(el.dataset.place!, el)) e.preventDefault();
  });
  window.addEventListener('open-place', (e) => open((e as CustomEvent<string>).detail));
}
