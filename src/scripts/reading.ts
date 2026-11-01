// Which item is being read. A horizontal line sits a share of the way down the part of the
// screen where the text is actually visible: below the nav, any sticky strip and, on phones, a
// map stacked above the text. The item under that line is the one being read.
//
// Measuring the covers each time (instead of a fixed share of the viewport) is what keeps the
// map in step on phones: there the map hides the top half of the screen, and a viewport-based
// band sits behind it, on the item that has already scrolled out of sight.

export interface ReadingOptions {
  /** the column the items live in; covers only count where they overlap it */
  column: HTMLElement;
  /** elements that may sit over the top of the column while scrolling */
  covers: () => (Element | null | undefined)[];
  /** how far down the visible part of the column the line sits, 0–1 */
  share: (stacked: boolean) => number;
  /** the item under the line; null when the line is still above the first item */
  onChange: (el: HTMLElement | null) => void;
}

export function watchReading(items: HTMLElement[], o: ReadingOptions) {
  let current: HTMLElement | null | undefined;
  let queued = false;

  const lineY = () => {
    const col = o.column.getBoundingClientRect();
    let top = 0;
    let stacked = false;
    for (const el of o.covers()) {
      if (!el) continue;
      const r = el.getBoundingClientRect();
      if (r.height <= 0 || r.top > innerHeight / 2 || r.left >= col.right || r.right <= col.left) continue;
      if (r.bottom > top) top = r.bottom;
      // something taller than a strip (a map) is stacked over the text
      if (r.height > 120) stacked = true;
    }
    return top + (innerHeight - top) * o.share(stacked);
  };

  const check = () => {
    queued = false;
    const y = lineY();
    let next: HTMLElement | null | undefined;
    const first = items.find((i) => i.offsetParent !== null);
    if (first && first.getBoundingClientRect().top > y) next = null;
    else
      next = items.find((i) => {
        const r = i.getBoundingClientRect();
        return r.height > 0 && r.top <= y && r.bottom > y;
      });
    // between two lists (or past the last item): keep what is shown
    if (next === undefined || next === current) return;
    current = next;
    o.onChange(next);
  };

  const queue = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(check);
  };
  addEventListener('scroll', queue, { passive: true });
  addEventListener('resize', queue);
  queue();

  return {
    /** look again, e.g. after the map above the text was opened or closed */
    refresh: queue,
    /** forget the current item and apply whatever is under the line now */
    reset() {
      current = undefined;
      queue();
    },
  };
}
