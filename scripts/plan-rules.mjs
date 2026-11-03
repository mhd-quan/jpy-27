// Rules the plan clock runs on, shared by scripts/check-plan.mjs and the iOS app (export-ios.mjs).

// minimum time spent at a stop (minutes)
export const DWELL = {
  kiyomizudera: 45, todaiji: 40, 'ise-naiku': 50, 'ise-geku': 40, 'meiji-jingu': 40, sensoji: 40, 'otagi-nenbutsuji': 40,
  'fushimi-sake': 60, 'onshi-hakone-park': 30, owakudani: 30, 'fs-chureito-pagoda': 30, 'fs-oishi-park': 45, 'wargo-gion': 30,
  doguyasuji: 60, 'takashimaya-osaka': 40, 'loft-umeda': 40, 'toshijima-wagu': 30, 'toshijima-toshi': 30,
  // places you walk through or stop at for a photo
  togetsukyo: 10, 'saga-toriimoto': 20, 'bamboo-grove': 20, hozenji: 20, 'fs-lawson-kawaguchiko-ekimae': 15, 'fs-honcho-dori': 15,
  manseibashi: 20, 'yanaka-ginza': 40, 'sumida-river': 15, nihonbashi: 15, 'gion-shirakawa': 20, okazaki: 20, 'uji-bridge': 10,
  'hakone-sekisho': 15, 'cedar-avenue': 10, 'hakone-shrine': 15,
};

/** Minutes waited for a departure that has no fixed time, by mode. */
export const WAIT = { subway: 4, train: 6, shinkansen: 8, bus: 8, shuttle: 6, ferry: 10, cruise: 10, ropeway: 5, cable: 6 };
