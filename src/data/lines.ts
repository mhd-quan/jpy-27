// Transit lines used on the trip. Colors follow each operator's own line color
// (the way Apple Maps draws transit), slightly tuned to stay legible on the map.
// `net` lists [operator, line] pairs from the MLIT railway dataset (N02) that the
// geometry builder may route over.

export type Mode =
  | 'walk'
  | 'train'
  | 'subway'
  | 'shinkansen'
  | 'bus'
  | 'shuttle'
  | 'ferry'
  | 'cruise'
  | 'ropeway'
  | 'cable';

export interface Line {
  name: string;
  color: string;
  mode: Mode;
  net?: [string, string][];
  /**
   * Minutes between departures in the daytime, for lines that run often enough that missing one
   * only means waiting for the next (metro, city lines, gondolas, local trains every 20 minutes or
   * less). Absent for reserved seats and sparse lines: their departures are fixed points the day
   * is planned around. The app treats a line as frequent up to 20 (TripKit `Line.isFrequent`).
   */
  every?: number;
}

const JRE = '東日本旅客鉄道';
const JRC = '東海旅客鉄道';
const KINTETSU = '近畿日本鉄道';
const kintetsuNet: [string, string][] = [
  [KINTETSU, '名古屋線'],
  [KINTETSU, '山田線'],
  [KINTETSU, '鳥羽線'],
  [KINTETSU, '志摩線'],
  [KINTETSU, '大阪線'],
  [KINTETSU, '橿原線'],
  [KINTETSU, '京都線'],
  [KINTETSU, '奈良線'],
  [KINTETSU, '難波線'],
];

export const LINES = {
  walk: { name: 'Đi bộ', color: '#8E8E93', mode: 'walk' },
  shuttle: { name: 'Xe đưa đón', color: '#8E8E93', mode: 'shuttle' },
  keikyu: {
    name: 'Keikyu',
    color: '#E5322D',
    mode: 'train',
    every: 10,
    net: [['京浜急行電鉄', '空港線'], ['京浜急行電鉄', '本線']],
  },
  keihinTohoku: {
    name: 'JR Keihin-Tōhoku',
    color: '#00A0DE',
    mode: 'train',
    every: 4,
    net: [[JRE, '東海道線'], [JRE, '東北線']],
  },
  yamanote: {
    name: 'JR Yamanote',
    color: '#80BC33',
    mode: 'train',
    every: 4,
    net: [[JRE, '山手線'], [JRE, '東北線'], [JRE, '東海道線']],
  },
  chuoSobu: {
    name: 'JR Chūō-Sōbu',
    color: '#E5AC00',
    mode: 'train',
    every: 4,
    net: [[JRE, '総武線'], [JRE, '中央線']],
  },
  ginza: {
    name: 'Ginza Line',
    color: '#F39700',
    mode: 'subway',
    every: 3,
    net: [['東京地下鉄', '3号線銀座線']],
  },
  romancecar: {
    name: 'Odakyu Romancecar',
    color: '#2468B8',
    mode: 'train',
    net: [['小田急電鉄', '小田原線'], ['箱根登山鉄道', '鉄道線']],
  },
  hakoneTozan: {
    name: 'Hakone Tozan',
    color: '#D23A3A',
    mode: 'train',
    every: 15,
    net: [['箱根登山鉄道', '鉄道線']],
  },
  hakoneCable: {
    name: 'Cáp treo kéo Sōunzan',
    color: '#E9792B',
    mode: 'cable',
    every: 15,
    net: [['箱根登山鉄道', '鋼索線']],
  },
  hakoneRopeway: { name: 'Hakone Ropeway', color: '#8A5CD0', mode: 'ropeway', every: 1 },
  ashiCruise: { name: 'Thuyền hồ Ashi', color: '#0E9FB0', mode: 'cruise' },
  tozanBus: { name: 'Hakone Tozan Bus (H)', color: '#2F9E62', mode: 'bus' },
  // local trains, no seats to book: since the March 2024 timetable about three an hour between
  // Atami and Shizuoka in the daytime, more often Odawara–Atami and Shimizu–Shizuoka
  tokaido: {
    name: 'JR Tōkaidō',
    color: '#F08A24',
    mode: 'train',
    every: 20,
    net: [[JRE, '東海道線'], [JRC, '東海道線']],
  },
  // Hikari and Kodama together stop at Shizuoka about three times an hour toward Nagoya; the plan
  // gives no time for this leg, so until a seat is booked the next train is the one taken
  shinkansen: {
    name: 'Tōkaidō Shinkansen',
    color: '#1B5FB4',
    mode: 'shinkansen',
    every: 20,
    net: [[JRC, '東海道新幹線']],
  },
  kintetsu: { name: 'Kintetsu', color: '#C8323F', mode: 'train', net: kintetsuNet },
  shimakaze: { name: 'Kintetsu Shimakaze', color: '#3A6FD9', mode: 'train', net: kintetsuNet },
  mieBus: { name: 'Mie Kotsu bus 51/55', color: '#2F9E62', mode: 'bus', every: 15 },
  tobaFerry: { name: 'Phà thị chính Toba', color: '#0E9FB0', mode: 'ferry' },
  karasuma: {
    name: 'Karasuma Line',
    color: '#2E9C5A',
    mode: 'subway',
    every: 5,
    net: [['京都市', '烏丸線']],
  },
  tozai: {
    name: 'Tōzai Line',
    color: '#E0572C',
    mode: 'subway',
    every: 6,
    net: [['京都市', '東西線']],
  },
  keihan: {
    name: 'Keihan',
    color: '#1E8A55',
    mode: 'train',
    every: 6,
    net: [['京阪電気鉄道', '京阪本線'], ['京阪電気鉄道', '鴨東線']],
  },
  hankyu: {
    name: 'Hankyu',
    color: '#8C1D2E',
    mode: 'train',
    every: 10,
    net: [['阪急電鉄', '京都線'], ['阪急電鉄', '嵐山線']],
  },
  kyotoBus: { name: 'Kyoto Bus 94', color: '#2F9E62', mode: 'bus' },
  midosuji: {
    name: 'Midōsuji Line',
    color: '#E5171F',
    mode: 'subway',
    every: 3,
    net: [['大阪市高速電気軌道', '1号線(御堂筋線)']],
  },
  // Kawaguchiko alternative day: Fuji Excursion runs JR Chūō then Fujikyu without a change
  fujiExcursion: {
    name: 'Fuji Excursion',
    color: '#5B8C3A',
    mode: 'train',
    net: [[JRE, '中央線'], ['富士山麓電気鉄道', '大月線'], ['富士山麓電気鉄道', '河口湖線']],
  },
  fujikyu: {
    name: 'Fujikyu',
    color: '#1F5EA8',
    mode: 'train',
    net: [['富士山麓電気鉄道', '大月線'], ['富士山麓電気鉄道', '河口湖線']],
  },
  kawaguchikoBus: { name: 'Xe buýt quanh hồ Kawaguchi', color: '#2F9E62', mode: 'bus', every: 15 },
  nankai: {
    name: 'Nankai Airport Express',
    color: '#E15A26',
    mode: 'train',
    net: [['南海電気鉄道', '南海本線'], ['南海電気鉄道', '空港線'], ['西日本旅客鉄道', '関西空港線']],
  },
} satisfies Record<string, Line>;

export type LineKey = keyof typeof LINES;

export const MODE_LABEL: Record<Mode, string> = {
  walk: 'Đi bộ',
  train: 'Tàu',
  subway: 'Tàu điện ngầm',
  shinkansen: 'Shinkansen',
  bus: 'Xe buýt',
  shuttle: 'Xe đưa đón',
  ferry: 'Phà',
  cruise: 'Thuyền',
  ropeway: 'Cáp treo',
  cable: 'Tàu cáp kéo',
};
