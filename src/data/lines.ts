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
    net: [['京浜急行電鉄', '空港線'], ['京浜急行電鉄', '本線']],
  },
  keihinTohoku: {
    name: 'JR Keihin-Tōhoku',
    color: '#00A0DE',
    mode: 'train',
    net: [[JRE, '東海道線'], [JRE, '東北線']],
  },
  yamanote: {
    name: 'JR Yamanote',
    color: '#80BC33',
    mode: 'train',
    net: [[JRE, '山手線'], [JRE, '東北線'], [JRE, '東海道線']],
  },
  chuoSobu: {
    name: 'JR Chūō-Sōbu',
    color: '#E5AC00',
    mode: 'train',
    net: [[JRE, '総武線'], [JRE, '中央線']],
  },
  ginza: {
    name: 'Ginza Line',
    color: '#F39700',
    mode: 'subway',
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
    net: [['箱根登山鉄道', '鉄道線']],
  },
  hakoneCable: {
    name: 'Cáp treo kéo Sōunzan',
    color: '#E9792B',
    mode: 'cable',
    net: [['箱根登山鉄道', '鋼索線']],
  },
  hakoneRopeway: { name: 'Hakone Ropeway', color: '#8A5CD0', mode: 'ropeway' },
  ashiCruise: { name: 'Thuyền hồ Ashi', color: '#0E9FB0', mode: 'cruise' },
  tozanBus: { name: 'Hakone Tozan Bus (H)', color: '#2F9E62', mode: 'bus' },
  tokaido: {
    name: 'JR Tōkaidō',
    color: '#F08A24',
    mode: 'train',
    net: [[JRE, '東海道線'], [JRC, '東海道線']],
  },
  shinkansen: {
    name: 'Tōkaidō Shinkansen',
    color: '#1B5FB4',
    mode: 'shinkansen',
    net: [[JRC, '東海道新幹線']],
  },
  kintetsu: { name: 'Kintetsu', color: '#C8323F', mode: 'train', net: kintetsuNet },
  shimakaze: { name: 'Kintetsu Shimakaze', color: '#3A6FD9', mode: 'train', net: kintetsuNet },
  mieBus: { name: 'Mie Kotsu bus 51/55', color: '#2F9E62', mode: 'bus' },
  tobaFerry: { name: 'Phà thị chính Toba', color: '#0E9FB0', mode: 'ferry' },
  karasuma: {
    name: 'Karasuma Line',
    color: '#2E9C5A',
    mode: 'subway',
    net: [['京都市', '烏丸線']],
  },
  tozai: {
    name: 'Tōzai Line',
    color: '#E0572C',
    mode: 'subway',
    net: [['京都市', '東西線']],
  },
  keihan: {
    name: 'Keihan',
    color: '#1E8A55',
    mode: 'train',
    net: [['京阪電気鉄道', '京阪本線'], ['京阪電気鉄道', '鴨東線']],
  },
  hankyu: {
    name: 'Hankyu',
    color: '#8C1D2E',
    mode: 'train',
    net: [['阪急電鉄', '京都線'], ['阪急電鉄', '嵐山線']],
  },
  kyotoBus: { name: 'Kyoto Bus 94', color: '#2F9E62', mode: 'bus' },
  midosuji: {
    name: 'Midōsuji Line',
    color: '#E5171F',
    mode: 'subway',
    net: [['大阪市高速電気軌道', '1号線(御堂筋線)']],
  },
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
