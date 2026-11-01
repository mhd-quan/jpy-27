// Where a link goes, as a one-word tag (Tabelog, Instagram, Wikipedia…). Tags replace the
// "Nguồn: host, host" lines: tap one to open the page behind a claim.

const HOSTS: [RegExp, string][] = [
  [/(^|\.)tabelog\.com$/, 'Tabelog'],
  [/(^|\.)instagram\.com$/, 'Instagram'],
  [/(^|\.)tiktok\.com$/, 'TikTok'],
  [/(^|\.)(youtube\.com|youtu\.be)$/, 'YouTube'],
  [/(^|\.)wikipedia\.org$/, 'Wikipedia'],
  [/(^|\.)wikimedia\.org$/, 'Commons'],
  [/(^|\.)(x\.com|twitter\.com)$/, 'X'],
  [/(^|\.)reddit\.com$/, 'Reddit'],
  [/(^|\.)4travel\.jp$/, '4travel'],
  [/(^|\.)yahoo\.co\.jp$/, 'Yahoo'],
  [/(^|\.)hakonenavi\.jp$/, 'Hakone Navi'],
  [/(^|\.)jalan\.net$/, 'Jalan'],
  [/(^|\.)gnavi\.co\.jp$/, 'Gurunavi'],
  [/(^|\.)openstreetmap\.org$/, 'OSM'],
  [/(^|\.)google\.[a-z.]+$|^maps\.app\.goo\.gl$/, 'Google Maps'],
];

export function sourceLabel(url: string): string {
  try {
    const host = new URL(url).hostname.replace(/^www\./, '');
    return HOSTS.find(([re]) => re.test(host))?.[1] ?? 'Web';
  } catch {
    return 'Web';
  }
}

/** One tag per kind of source, at most `max`; the first link of each kind wins. */
export function sourceTags(urls: (string | null | undefined)[], max = 4): { href: string; label: string }[] {
  const seen = new Set<string>();
  const out: { href: string; label: string }[] = [];
  for (const href of urls) {
    if (!href || !/^https?:/.test(href)) continue;
    const label = sourceLabel(href);
    if (seen.has(label)) continue;
    seen.add(label);
    out.push({ href, label });
    if (out.length >= max) break;
  }
  return out;
}
