// Phrase sheet: scenario picker → phrases (Japanese, romaji, Vietnamese) → full-screen card.
// Opened by any [data-say] button: data-say lists context tags (food, stay, station, …),
// data-say-place names the place whose Japanese name and menu fill the templates.
import { makeSheet } from './sheet';

interface Phrase {
  id: string;
  ja: string;
  romaji: string;
  vi: string;
  note?: string | null;
  slot?: string | null;
  example?: { ja: string; romaji: string } | null;
}
interface Hear {
  ja: string;
  romaji: string;
  vi: string;
  reply?: { ja: string; romaji: string } | null;
}
interface Scenario {
  id: string;
  vi: string;
  hint?: string;
  for: string[];
  phrases: Phrase[];
  hear?: Hear[];
}
interface PlaceInfo {
  name: string;
  ja: string;
  kind: string;
  menu: { ja: string; romaji: string; vi: string; yen: number | null }[];
}
interface Data {
  scenarios: Scenario[];
  places: Record<string, PlaceInfo>;
}

const KIND_VI: Record<string, string> = {
  food: 'Quán ăn',
  stay: 'Nơi ở',
  sight: 'Tham quan',
  shop: 'Cửa hàng',
  station: 'Ga, tàu',
  ferry: 'Bến, phà',
  any: 'Chung',
};

const h = <K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Record<string, string> = {}, ...kids: (Node | string | null | undefined | false)[]) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') el.className = v;
    else el.setAttribute(k, v);
  }
  for (const k of kids) if (k) el.append(k);
  return el;
};

const SPEAKER =
  '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z" fill="currentColor"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>';

const NAME_KEY = 'nb27-say-name';
const readName = () => {
  try {
    return localStorage.getItem(NAME_KEY) || '';
  } catch {
    return '';
  }
};
const saveName = (v: string) => {
  try {
    localStorage.setItem(NAME_KEY, v);
  } catch {
    /* private mode: the name just isn't remembered */
  }
};

let voice: SpeechSynthesisVoice | null | undefined;
function speak(text: string, btn?: HTMLElement) {
  if (!('speechSynthesis' in window)) return;
  const synth = window.speechSynthesis;
  voice ??= synth.getVoices().find((v) => v.lang.replace('_', '-').toLowerCase().startsWith('ja')) ?? null;
  synth.cancel();
  const u = new SpeechSynthesisUtterance(text);
  u.lang = 'ja-JP';
  u.rate = 0.9;
  if (voice) u.voice = voice;
  btn?.classList.add('is-playing');
  u.onend = u.onerror = () => btn?.classList.remove('is-playing');
  synth.speak(u);
}

export function initSay() {
  const dialog = document.getElementById('say-sheet') as HTMLDialogElement | null;
  const raw = document.getElementById('say-data');
  if (!dialog || !raw || dialog.dataset.ready) return;
  dialog.dataset.ready = '1';
  const data: Data = JSON.parse(raw.textContent || '{}');
  if (!data.scenarios?.length) return;
  const sheet = makeSheet(dialog);
  const canSpeak = 'speechSynthesis' in window;
  if (canSpeak) window.speechSynthesis.getVoices();

  let tags: string[] = [];
  let pl: PlaceInfo | null = null;
  let stationName: { ja: string; romaji: string } | null = null;

  /** Fill {place}, {station}, {name}, {n}, {time}, {dish}: the place on screen when it fits, else the example. */
  const fill = (p: Phrase) => {
    let ja = p.ja;
    let ro = p.romaji;
    const sub = (key: string, vja: string, vro: string) => {
      ja = ja.split(`{${key}}`).join(vja);
      ro = ro.split(`{${key}}`).join(vro);
    };
    if (pl) sub('place', pl.ja, pl.name);
    if (stationName) sub('station', stationName.ja, stationName.romaji);
    const name = readName();
    if (name) sub('name', name, name);
    sub('n', '2', 'ni');
    if (/\{\w+\}/.test(ja) && p.example) return { ja: p.example.ja, romaji: p.example.romaji };
    return { ja, romaji: ro };
  };

  const show = (ja: string, romaji: string, vi: string) => {
    const card = h(
      'div',
      { class: 'say-show', role: 'dialog', 'aria-label': 'Câu cho nhân viên' },
      h('p', { class: 'ja', lang: 'ja' }, ja),
      h('p', { class: 'say-ro' }, romaji),
      h('p', { class: 'say-vi' }, vi),
    );
    const actions = h('div', { class: 'say-show-actions' });
    if (canSpeak) {
      const play = h('button', { type: 'button', class: 'btn' });
      play.innerHTML = `${SPEAKER}<span>Phát âm</span>`;
      play.addEventListener('click', () => speak(ja, play));
      actions.append(play);
    }
    const back = h('button', { type: 'button', class: 'btn btn-quiet' }, 'Quay lại');
    back.addEventListener('click', () => card.remove());
    actions.append(back);
    card.append(actions);
    card.addEventListener('click', (e) => {
      if (e.target === card) card.remove();
    });
    dialog.append(card);
    back.focus();
  };

  const phraseRow = (ja: string, romaji: string, vi: string, note?: string | null, extra?: string) => {
    const li = h('li', { class: 'say-row' });
    const btn = h(
      'button',
      { type: 'button', class: 'say-ph' },
      h('span', { class: 'ja', lang: 'ja' }, ja),
      h('span', { class: 'say-ro' }, romaji),
      h('span', { class: 'say-vi' }, vi),
      note ? h('span', { class: 'say-note' }, note) : null,
      extra ? h('span', { class: 'say-price tnum' }, extra) : null,
    );
    btn.addEventListener('click', () => show(ja, romaji, vi));
    li.append(btn);
    if (canSpeak) {
      const play = h('button', { type: 'button', class: 'say-play', 'aria-label': 'Phát âm' });
      play.innerHTML = SPEAKER;
      play.addEventListener('click', (e) => {
        e.stopPropagation();
        speak(ja, play);
      });
      li.append(play);
    }
    return li;
  };

  const header = (kicker: string) =>
    h(
      'header',
      { class: 'say-head' },
      h('p', { class: 'say-kicker t-small' }, kicker),
      h('h2', { class: 't-2' }, pl?.name ?? 'Tiếng Nhật'),
      pl && pl.ja !== pl.name ? h('p', { class: 'ja', lang: 'ja' }, pl.ja) : null,
    );

  function scenarioView(s: Scenario) {
    const frag = document.createDocumentFragment();
    const back = h('button', { type: 'button', class: 'say-back' }, '‹ Tình huống');
    back.addEventListener('click', () => render());
    frag.append(back, header(s.vi));
    if (s.hint) frag.append(h('p', { class: 't-small muted' }, s.hint));
    if (s.phrases.some((p) => p.slot === 'name')) {
      const input = h('input', { type: 'text', value: readName(), placeholder: 'NGUYEN', autocomplete: 'family-name', 'aria-label': 'Tên đặt chỗ' }) as HTMLInputElement;
      input.addEventListener('change', () => {
        saveName(input.value.trim().toUpperCase());
        render(s);
      });
      frag.append(h('label', { class: 'say-name' }, 'Tên đặt chỗ', input));
    }

    // Order: the restaurant's own dishes first
    if (s.id === 'order' && pl?.menu.length) {
      let count = 1;
      const list = h('ul', { class: 'say-list' });
      const draw = () => {
        const [cja, cro, cvi] = count === 1 ? ['一つ', 'hitotsu', 'một phần'] : ['二つ', 'futatsu', 'hai phần'];
        list.replaceChildren(
          ...pl!.menu.map((m) =>
            phraseRow(`${m.ja}を${cja}お願いします。`, `${m.romaji ? m.romaji.charAt(0).toUpperCase() + m.romaji.slice(1) : m.ja} o ${cro} onegaishimasu.`, `Cho tôi ${cvi} ${m.vi.charAt(0).toLowerCase()}${m.vi.slice(1)}.`, null, m.yen ? `¥${m.yen.toLocaleString('vi-VN')}` : undefined),
          ),
        );
      };
      const seg = h('div', { class: 'say-seg', role: 'group', 'aria-label': 'Số phần' });
      for (const c of [1, 2]) {
        const b = h('button', { type: 'button', 'aria-pressed': String(c === count) }, c === 1 ? '1 phần' : '2 phần');
        b.addEventListener('click', () => {
          count = c;
          seg.querySelectorAll('button').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
          draw();
        });
        seg.append(b);
      }
      draw();
      frag.append(h('div', { class: 'say-menu-head' }, h('h3', { class: 'say-sub' }, 'Món của quán'), seg), list);
      frag.append(h('h3', { class: 'say-sub' }, 'Câu chung'));
    }

    const list = h('ul', { class: 'say-list' });
    for (const p of s.phrases) {
      const f = fill(p);
      list.append(phraseRow(f.ja, f.romaji, p.vi, p.note));
    }
    frag.append(list);

    if (s.hear?.length) {
      frag.append(h('h3', { class: 'say-sub' }, 'Có thể bạn sẽ nghe'));
      const ul = h('ul', { class: 'say-hear' });
      for (const x of s.hear) {
        ul.append(
          h(
            'li',
            {},
            h('span', { class: 'ja', lang: 'ja' }, x.ja),
            h('span', { class: 'say-ro' }, x.romaji),
            h('span', { class: 'say-vi' }, x.vi),
            x.reply ? h('p', { class: 'say-reply' }, 'Đáp: ', h('span', { lang: 'ja', class: 'ja' }, x.reply.ja), ` — ${x.reply.romaji}`) : null,
          ),
        );
      }
      frag.append(ul);
    }
    sheet.body.replaceChildren(frag);
    sheet.body.scrollTop = 0;
  }

  function render(s?: Scenario) {
    if (s) return scenarioView(s);
    // scenarios named by a tag (ryokan, kimono, order…) first, then those for this kind of place,
    // then the general ones (greetings, directions, health)
    const rank = (x: Scenario) => (tags.includes(x.id) ? 0 : x.for.some((t) => t !== 'any' && tags.includes(t)) ? 1 : x.for.includes('any') ? 2 : 3);
    const fits = (x: Scenario) => rank(x) < 3;
    const first = data.scenarios.filter(fits).sort((a, b) => rank(a) - rank(b));
    const rest = data.scenarios.filter((x) => !fits(x));
    const frag = document.createDocumentFragment();
    frag.append(header(`Nói với nhân viên · ${KIND_VI[tags[0]] ?? 'Chung'}`));
    const grid = (list: Scenario[]) => {
      const g = h('div', { class: 'say-grid' });
      for (const x of list) {
        const b = h('button', { type: 'button', class: 'say-scn' }, h('strong', {}, x.vi), x.hint ? h('span', {}, x.hint) : null);
        b.addEventListener('click', () => render(x));
        g.append(b);
      }
      return g;
    };
    frag.append(grid(first.length ? first : data.scenarios));
    if (first.length && rest.length) {
      frag.append(h('details', { class: 'say-more' }, h('summary', {}, `Tình huống khác (${rest.length})`), grid(rest)));
    }
    sheet.body.replaceChildren(frag);
    sheet.body.scrollTop = 0;
  }

  document.addEventListener('click', (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>('[data-say]');
    if (!el || el.closest('dialog')) return;
    e.preventDefault();
    e.stopPropagation();
    tags = [...el.dataset.say!.split(/\s+/).filter(Boolean), 'any'];
    pl = el.dataset.sayPlace ? (data.places[el.dataset.sayPlace] ?? null) : null;
    stationName = el.dataset.sayStation ? { ja: el.dataset.sayStation, romaji: el.dataset.sayStationRo ?? el.dataset.sayStation } : null;
    sheet.open(document.createDocumentFragment(), el);
    const direct = el.dataset.sayScenario ? data.scenarios.find((x) => x.id === el.dataset.sayScenario) : undefined;
    render(direct);
  });
  dialog.addEventListener('close', () => {
    dialog.querySelector('.say-show')?.remove();
    if (canSpeak) window.speechSynthesis.cancel();
  });
}
