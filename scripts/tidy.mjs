// Research notes carry the researcher's working: references to the project's own files ("DEM",
// "research/fuji.json"), where each fact came from ("(Wikipedia ja)", "mẫu Yahoo 2/11/2026",
// "theo review Tabelog") and hedges about what was not confirmed ("chưa kiểm chứng", "cần kiểm tra
// lại"). The page shows the facts; sources live in the links. Applied as research is read
// (merge-research, build-stays) and to generated data the page reads directly.

const RULES = [
  [/\s*\((?:ghi chú trong )?research\/fuji\.json\)/g, ''],
  [/theo research\/fuji\.json,\s*/g, 'theo số liệu quan trắc, '],
  [/(?:là điểm dự phòng )?trong research\/fuji\.json/g, (m) => (m.startsWith('là') ? 'là điểm dự phòng trên trang Fuji' : 'trên trang Fuji')],
  [/ghi chú trong research\/fuji\.json/g, 'trang Fuji'],
  [/\s*\(fuji\.json ghi ([^)]*)\)/g, ' ($1)'],
  [/ trong fuji\.json/g, ''],
  [/Số liệu ngày ([\d/]+) trong fuji\.json:/g, 'Ngày $1:'],
  [/\bfuji\.json\b/g, 'trang Fuji'],
  [/(^|[.!?]\s+)DEM\b/g, '$1Dữ liệu địa hình'],
  [/\bDEM\b/g, 'dữ liệu địa hình'],
  [/\s*theo ghi chú trong dự án/g, ''],
];

// Where a fact came from
const SOURCE = String.raw`(?:Wikipedia(?: ja)?|Wikidata|Magical Trip|Tokyo Cheapo|Japan Guide|japan-guide(?:\.com)?|một blog|blog|Yahoo(?: Chiebukuro)?|Ekitan|Hakone Navi|Kyoto Bus Navi|NAVITIME|Jorudan|OSM|OpenStreetMap|Google(?: Maps)?|Tabelog|iko-yo(?:\.net)?|Bestcar|busmap)`;
const SOURCE_RE = new RegExp(String.raw`\b${SOURCE}\b|^(?:theo |suy từ |nguồn:? )|^trang |^mẫu |cập nhật \d|không ghi ngày|xác nhận qua|^\d{1,2}/\d{4}$|^\d{1,2}/\d{1,2}/\d{4}$`, 'i');
// "according to X" fragments inside a sentence; \u0001 marks the cut so a sentence that now starts
// in lower case gets its capital back
const LEAD = String.raw`(^|[;,.:]\s+|\(\s*|\svà\s+)`;
const FRAGMENTS = [
  [new RegExp(String.raw`(?:^|,\s*|\s+)(?:theo|từ|suy từ) (?:review |bài |trang )?${SOURCE}(?: \d[\d/]*)?(?=[\s,.;)]|$)`, 'g'), ' \u0001'],
  [/(?:^|,\s*|\s+)theo trang [^,;.()]*/g, ' \u0001'],
  [/\s+theo (?:ghi chú của kế hoạch|dữ liệu có sẵn của dự án|nguồn ngoài)/g, ' \u0001'],
  [new RegExp(String.raw`${LEAD}(?:bài )?${SOURCE} (?:ghi|nói|cho biết|mô tả)(?: là| rằng)?\s+(?!không|\d|đến)`, 'g'), '$1\u0001'],
  [new RegExp(String.raw`${LEAD}[Tt]rang [^,;.:()]{0,30}? (?:nói|ghi|cho biết)\s+(?!không|\d)`, 'g'), '$1\u0001'],
  [new RegExp(String.raw`${LEAD}bài [A-Z][\w-]*(?: năm \d{4})? ghi\s+`, 'g'), '$1\u0001'],
  [new RegExp(String.raw`${LEAD}(?:mẫu|theo) Yahoo(?: [\d/]+)?:\s*`, 'g'), '$1\u0001'],
  [new RegExp(String.raw`${LEAD}Theo mô tả chung[^:]*:\s*`, 'g'), '$1\u0001'],
];
// A clause that only says what is not known, or how a fact was found
const HEDGE =
  /chưa (?:được )?(?:xác nhận|xác minh|kiểm\b|kiểm chứng|công bố|tìm được|tìm thấy|thấy (?:trên|trang|ngoại lệ|tên)|rõ|có nguồn|nghe thực tế|mở được)|cần (?:kiểm tra|xác nhận)(?! điện)|chỉ (?:để tham khảo|suy ra)|không nguồn nào|Wikipedia(?: ja)? (?:không|chỉ) (?:nói|nhắc|ghi|mô tả)|Wikipedia có ảnh|trang chính thức không (?:mở được|nêu)|ảnh khách Tabelog|tổng hợp từ kết quả tìm kiếm|lấy từ (?:chiều ngược|trang)|Phần này dựa trên|Mẫu thông báo chung|Nêu ra để loại trừ|nên kiểm tra lại|một trang khác|(?:chú thích )?ảnh(?: khách)?(?: trên)? Tabelog|(?:^|[;,(]\s*)(?:bài )?(?:Tabelog|Wikipedia(?: ja)?|Hakone Navi|OSM) ghi (?:\d|đến)/i;

/** Split on a separator (a sticky regex, tried at each position) only outside brackets and quotes. */
function splitTop(s, sep) {
  const out = [];
  let depth = 0;
  let from = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if ('(「“'.includes(c)) depth++;
    else if (')」”'.includes(c)) depth = Math.max(0, depth - 1);
    else if (depth === 0) {
      sep.lastIndex = i;
      const m = sep.exec(s);
      if (m && m[0].length) {
        out.push(s.slice(from, i));
        from = i + m[0].length;
        i = from - 1;
      }
    }
  }
  out.push(s.slice(from));
  return out;
}

const cap = (s) => s.replace(/^(\s*["“(]?)(\p{Ll})/u, (_, a, b) => a + b.toUpperCase());

/**
 * Brackets: "(Wikipedia ja, không ghi ngày)" goes; "(mẫu Yahoo 2/11/2026, từ 天空橋 mất 15 phút)"
 * keeps the last part; "(khoảng 30 vị; chưa xác minh được giá)" keeps the first.
 */
function parens(s) {
  return s.replace(/\s*\(([^()]*)\)/g, (m, inner) => {
    const hedged = HEDGE.test(inner);
    if (!hedged && !new RegExp(String.raw`\b${SOURCE}\b|^(?:theo|trang|mẫu|suy từ) `, 'i').test(inner)) return m;
    let parts = inner.split(/[,;]\s+/);
    if (hedged) parts = parts.slice(0, parts.findIndex((p) => HEDGE.test(p)));
    const keep = parts
      .map((p) => p.trim().replace(new RegExp(String.raw`^(?:theo )?(?:trang [^:\d]{0,30}|${SOURCE}[^:\d]{0,20}):\s+`, 'i'), ''))
      .filter((p) => p && !SOURCE_RE.test(p));
    return keep.length ? ` (${keep.join(', ')})` : '';
  });
}

/**
 * Drop the hedging part of a clause and what follows it, which leans on it: "Giá ¥520, chưa kiểm
 * chứng" keeps "Giá ¥520". A consequence survives: "chưa rõ X, nên Y" keeps "nên Y", and
 * "…, nhưng Y" keeps "Y".
 */
function clause(c) {
  if (!HEDGE.test(c)) return c;
  const parts = splitTop(c, /,\s+/y);
  const h = parts.map((p) => HEDGE.test(p));
  const first = h.indexOf(true);
  const last = h.lastIndexOf(true);
  const before = parts.slice(0, first);
  const tail = parts[last + 1];
  if (tail && /^(?:nên|nhưng) /.test(tail)) return [...before, before.length ? tail : tail.replace(/^nhưng /, ''), ...parts.slice(last + 2)].join(', ');
  return before.join(', ');
}

function dropHedges(s) {
  let t = parens(s);
  for (const [re, to] of FRAGMENTS) t = t.replace(re, to);
  t = t.replace(/(^|[.!?]\s+|\(\s*)\s*\u0001\s*(\p{Ll})/gu, (_, a, b) => a + b.toUpperCase()).replace(/\s*\u0001\s*/g, ' ');
  if (!HEDGE.test(t)) return t;
  const sentences = splitTop(t, /(?<=[.!?])\s+(?=[\p{Lu}\d"“(])/uy);
  const kept = [];
  for (const sen of sentences) {
    const end = /[.!?]$/.test(sen) ? sen.at(-1) : '';
    const body = end ? sen.slice(0, -1) : sen;
    const clauses = splitTop(body, /;\s+/y);
    const out = clauses.map(clause).filter((c) => c.trim().length > 2);
    if (!out.length) continue;
    let joined = out.join('; ');
    if (!body.startsWith(out[0])) joined = cap(joined);
    kept.push(joined + (end || ''));
  }
  return kept.join(' ');
}

const finish = (s) =>
  s
    .replace(/\s+([,.;)])/g, '$1')
    .replace(/^[\s,;]+/, '')
    .replace(/^"([^"]+)"/, (_, a) => cap(a))
    .replace(/\(\s*\)/g, '')
    .replace(/(^|[.!?]\s+)dữ liệu địa hình/g, (_, a) => `${a}Dữ liệu địa hình`)
    .replace(/\s{2,}/g, ' ')
    .trim();

export const tidy = (s) => {
  if (typeof s !== 'string' || /^https?:/.test(s) || !/\s/.test(s)) return s;
  const t = RULES.reduce((x, [re, to]) => x.replace(re, to), s);
  const d = dropHedges(t);
  return d === t ? t : finish(d);
};

const RAW_KEYS = new Set(['src', 'url', 'page', 'source', 'sources', 'credit', 'license', 'p', 'id']);
export function deepTidy(v) {
  if (Array.isArray(v)) return v.map(deepTidy);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, RAW_KEYS.has(k) ? x : deepTidy(x)]));
  return tidy(v);
}
