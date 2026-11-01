// Research notes sometimes refer to the project's own files or tools ("research/fuji.json", "DEM").
// Visible text should not: rewrite those references in plain words when research is merged.
const RULES = [
  [/\s*\((?:ghi chú trong )?research\/fuji\.json\)/g, ''],
  [/theo research\/fuji\.json,\s*/g, 'theo số liệu quan trắc, '],
  [/(?:là điểm dự phòng )?trong research\/fuji\.json/g, (m) => (m.startsWith('là') ? 'là điểm dự phòng trên trang Fuji' : 'trên trang Fuji')],
  [/ghi chú trong research\/fuji\.json/g, 'trang Fuji'],
  [/\s*\(fuji\.json ghi ([^)]*)\)/g, ' ($1)'],
  [/Số liệu ngày ([\d/]+) trong fuji\.json:/g, 'Ngày $1:'],
  [/\bfuji\.json\b/g, 'trang Fuji'],
  [/\bDEM\b/g, 'dữ liệu địa hình'],
  [/\s*theo ghi chú trong dự án/g, ''],
];
export const tidy = (s) => (typeof s === 'string' && !/^https?:/.test(s) ? RULES.reduce((t, [re, to]) => t.replace(re, to), s) : s);
export function deepTidy(v) {
  if (Array.isArray(v)) return v.map(deepTidy);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, k === 'src' || k === 'url' || k === 'page' || k === 'sources' ? x : deepTidy(x)]));
  return tidy(v);
}
