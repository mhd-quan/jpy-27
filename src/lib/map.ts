// Client-side map: basemap + trip route + pins, with focus/highlight helpers.
import * as maplibregl from 'maplibre-gl';
import type { LngLatBoundsLike, Map as MLMap } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url';
import { baseStyle, type Theme } from './mapStyle';
import { decodePolyline } from './geo';

export interface RouteLeg {
  id: string;
  p: string; // encoded polyline [lat, lng]
  color: string;
  mode: string;
  day?: number;
}

export interface Pin {
  id: string;
  lat: number;
  lng: number;
  kind: 'stay' | 'food' | 'sight' | 'shop' | 'station' | 'along' | 'fuji';
  label: string;
  n?: number;
  day?: number;
}

export interface TripMapOptions {
  legs: RouteLeg[];
  pins: Pin[];
  bounds?: [[number, number], [number, number]]; // [[w,s],[e,n]]
  cooperative?: boolean;
  terrain?: boolean;
  pitch?: number;
  bearing?: number;
  labels?: 'all' | 'main' | 'none';
  onPin?: (id: string) => void;
  padding?: maplibregl.PaddingOptions | number;
}

const prefersDark = () => {
  const forced = document.documentElement.dataset.theme;
  if (forced === 'dark' || forced === 'light') return forced === 'dark';
  return matchMedia('(prefers-color-scheme: dark)').matches;
};
const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

const KIND_COLOR: Record<string, [string, string]> = {
  stay: ['#8a5cd0', '#b18cff'],
  food: ['#e9792b', '#ff9f45'],
  sight: ['#2f7de1', '#5aa2ff'],
  shop: ['#d9487a', '#ff6f9c'],
  fuji: ['#1d1d1f', '#f5f5f7'],
};

export function legsToGeoJSON(legs: RouteLeg[]): GeoJSON.FeatureCollection<GeoJSON.LineString> {
  return {
    type: 'FeatureCollection',
    features: legs.map((l) => ({
      type: 'Feature',
      id: l.id,
      properties: { id: l.id, color: l.color, mode: l.mode, day: l.day ?? 0 },
      geometry: { type: 'LineString', coordinates: decodePolyline(l.p).map(([lat, lng]) => [lng, lat]) },
    })),
  };
}

function pinsToGeoJSON(pins: Pin[]): GeoJSON.FeatureCollection<GeoJSON.Point> {
  return {
    type: 'FeatureCollection',
    features: pins.map((p) => ({
      type: 'Feature',
      id: p.id,
      properties: { id: p.id, kind: p.kind, label: p.label, n: p.n ?? '', day: p.day ?? 0 },
      geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
    })),
  };
}

maplibregl.setWorkerUrl(workerUrl);

export function createTripMap(container: HTMLElement, opts: TripMapOptions) {
  let theme: Theme = prefersDark() ? 'dark' : 'light';
  const routes = legsToGeoJSON(opts.legs);
  const pins = pinsToGeoJSON(opts.pins);

  const map: MLMap = new maplibregl.Map({
    container,
    style: baseStyle(theme),
    bounds: opts.bounds as LngLatBoundsLike | undefined,
    fitBoundsOptions: { padding: opts.padding ?? 48 },
    pitch: opts.pitch ?? 0,
    bearing: opts.bearing ?? 0,
    maxPitch: 70,
    attributionControl: { compact: true },
    cooperativeGestures: opts.cooperative ?? false,
    localIdeographFontFamily: "'Hiragino Sans', 'Noto Sans JP', sans-serif",
    fadeDuration: 150,
    dragRotate: Boolean(opts.terrain),
    touchPitch: Boolean(opts.terrain),
  });
  map.addControl(new maplibregl.NavigationControl({ showCompass: Boolean(opts.terrain), visualizePitch: true }), 'top-right');

  let activeLeg: string | null = null;
  let activePin: string | null = null;

  const addOverlay = () => {
    const dark = theme === 'dark';
    const casing = dark ? '#000000' : '#ffffff';
    if (opts.terrain) map.setTerrain({ source: 'dem', exaggeration: 1.35 });

    map.addSource('route', { type: 'geojson', data: routes, promoteId: 'id' });
    map.addSource('pins', { type: 'geojson', data: pins, promoteId: 'id' });

    const dim: maplibregl.ExpressionSpecification = ['case', ['boolean', ['feature-state', 'dim'], false], 0.28, 1];
    const width = (base: number): maplibregl.ExpressionSpecification => [
      'interpolate',
      ['linear'],
      ['zoom'],
      6,
      ['+', base * 0.55, ['case', ['boolean', ['feature-state', 'active'], false], 2, 0]],
      12,
      ['+', base, ['case', ['boolean', ['feature-state', 'active'], false], 2.5, 0]],
      16,
      ['+', base * 1.5, ['case', ['boolean', ['feature-state', 'active'], false], 3, 0]],
    ];
    const isMode = (modes: string[]): maplibregl.ExpressionSpecification => ['match', ['get', 'mode'], modes, true, false];

    map.addLayer({
      id: 'route-case',
      type: 'line',
      source: 'route',
      filter: isMode(['train', 'subway', 'shinkansen', 'bus', 'shuttle', 'cable']),
      layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': casing, 'line-width': width(6.5), 'line-opacity': dim },
    });
    map.addLayer({
      id: 'route-solid',
      type: 'line',
      source: 'route',
      filter: isMode(['train', 'subway', 'shinkansen', 'bus', 'shuttle', 'cable']),
      layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': ['get', 'color'], 'line-width': width(4), 'line-opacity': dim },
    });
    map.addLayer({
      id: 'route-water',
      type: 'line',
      source: 'route',
      filter: isMode(['ferry', 'cruise']),
      layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': ['get', 'color'], 'line-width': width(3.5), 'line-dasharray': [1.6, 1.4], 'line-opacity': dim },
    });
    map.addLayer({
      id: 'route-air',
      type: 'line',
      source: 'route',
      filter: isMode(['ropeway']),
      layout: { 'line-cap': 'butt' },
      paint: { 'line-color': ['get', 'color'], 'line-width': width(3.5), 'line-dasharray': [0.6, 0.9], 'line-opacity': dim },
    });
    map.addLayer({
      id: 'route-walk',
      type: 'line',
      source: 'route',
      filter: isMode(['walk']),
      layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: {
        'line-color': dark ? '#c7c7cc' : '#636366',
        'line-width': width(3.2),
        'line-dasharray': [0, 1.9],
        'line-opacity': dim,
      },
    });

    // Lines of sight to Fuji: solid when clear, dashed when terrain is in the way
    map.addLayer({
      id: 'route-sight',
      type: 'line',
      source: 'route',
      filter: isMode(['sight']),
      paint: { 'line-color': dark ? '#f5f5f7' : '#1d1d1f', 'line-width': width(1.6), 'line-opacity': ['case', ['boolean', ['feature-state', 'dim'], false], 0.25, 0.75] },
    });
    map.addLayer({
      id: 'route-sightx',
      type: 'line',
      source: 'route',
      filter: isMode(['sightx']),
      paint: { 'line-color': '#8e8e93', 'line-width': width(1.4), 'line-dasharray': [2, 2], 'line-opacity': ['case', ['boolean', ['feature-state', 'dim'], false], 0.25, 0.8] },
    });

    // Suggestions along the way: hollow rings
    map.addLayer({
      id: 'pin-along',
      type: 'circle',
      source: 'pins',
      filter: ['==', ['get', 'kind'], 'along'],
      paint: {
        'circle-radius': ['interpolate', ['linear'], ['zoom'], 9, 3.5, 14, 6.5],
        'circle-color': dark ? '#1c1c1e' : '#ffffff',
        'circle-stroke-color': dark ? '#5aa2ff' : '#2f7de1',
        'circle-stroke-width': ['case', ['boolean', ['feature-state', 'active'], false], 4, 2.2],
      },
    });
    map.addLayer({
      id: 'pin-station',
      type: 'circle',
      source: 'pins',
      minzoom: 11,
      filter: ['==', ['get', 'kind'], 'station'],
      paint: {
        'circle-radius': ['interpolate', ['linear'], ['zoom'], 11, 2.5, 15, 4.5],
        'circle-color': dark ? '#1c1c1e' : '#ffffff',
        'circle-stroke-color': dark ? '#d1d1d6' : '#3a3a3c',
        'circle-stroke-width': 1.6,
      },
    });
    map.addLayer({
      id: 'pin-main',
      type: 'circle',
      source: 'pins',
      filter: ['match', ['get', 'kind'], ['stay', 'food', 'sight', 'shop', 'fuji'], true, false],
      paint: {
        'circle-radius': [
          'interpolate',
          ['linear'],
          ['zoom'],
          6,
          ['case', ['==', ['get', 'n'], ''], 4, 6],
          12,
          ['+', ['case', ['==', ['get', 'n'], ''], 6.5, 10], ['case', ['boolean', ['feature-state', 'active'], false], 3, 0]],
        ],
        'circle-color': [
          'match',
          ['get', 'kind'],
          ...Object.entries(KIND_COLOR).flatMap(([k, [l, d]]) => [k, dark ? d : l]),
          '#8e8e93',
        ] as unknown as maplibregl.ExpressionSpecification,
        'circle-stroke-color': casing,
        'circle-stroke-width': 2,
      },
    });
    map.addLayer({
      id: 'pin-number',
      type: 'symbol',
      source: 'pins',
      minzoom: 9,
      filter: ['all', ['match', ['get', 'kind'], ['stay', 'food', 'sight', 'shop', 'fuji'], true, false], ['!=', ['get', 'n'], '']],
      layout: {
        'text-field': ['to-string', ['get', 'n']],
        'text-font': ['Noto Sans Bold'],
        'text-size': 11,
        'text-allow-overlap': true,
        'text-ignore-placement': true,
      },
      paint: { 'text-color': dark ? '#000000' : '#ffffff' },
    });
    if (opts.labels !== 'none') {
      map.addLayer({
        id: 'pin-label',
        type: 'symbol',
        source: 'pins',
        minzoom: opts.labels === 'main' ? 5 : 11,
        filter:
          opts.labels === 'main'
            ? ['==', ['get', 'kind'], 'stay']
            : ['match', ['get', 'kind'], ['stay', 'food', 'sight', 'shop', 'along', 'fuji'], true, false],
        layout: {
          'text-field': ['get', 'label'],
          'text-font': ['Noto Sans Bold'],
          'text-size': ['interpolate', ['linear'], ['zoom'], 10, 11, 15, 13],
          'text-anchor': 'left',
          'text-offset': [1.1, 0],
          'text-max-width': 10,
          'text-optional': true,
        },
        paint: {
          'text-color': dark ? '#f5f5f7' : '#1d1d1f',
          'text-halo-color': dark ? 'rgba(0,0,0,0.85)' : 'rgba(255,255,255,0.95)',
          'text-halo-width': 1.6,
        },
      });
    }

    if (activeLeg) setLeg(activeLeg);
    if (activePin) map.setFeatureState({ source: 'pins', id: activePin }, { active: true });
  };

  map.on('style.load', addOverlay);

  for (const layer of ['pin-main', 'pin-along', 'pin-label']) {
    map.on('click', layer, (e) => {
      const id = e.features?.[0]?.properties?.id;
      if (id && opts.onPin) opts.onPin(String(id));
    });
    map.on('mouseenter', layer, () => (map.getCanvas().style.cursor = 'pointer'));
    map.on('mouseleave', layer, () => (map.getCanvas().style.cursor = ''));
  }

  const media = matchMedia('(prefers-color-scheme: dark)');
  media.addEventListener('change', () => {
    const next: Theme = prefersDark() ? 'dark' : 'light';
    if (next !== theme) {
      theme = next;
      map.setStyle(baseStyle(theme));
    }
  });

  const setLeg = (id: string | null) => {
    if (!map.getSource('route')) return;
    for (const f of routes.features) {
      const fid = f.properties!.id as string;
      map.setFeatureState({ source: 'route', id: fid }, { active: id === fid, dim: id !== null && id !== fid });
    }
  };

  const duration = (ms: number) => (reduced() ? 0 : ms);

  const api = {
    map,
    highlightLeg(id: string | null, fit = true) {
      activeLeg = id;
      setLeg(id);
      if (!id || !fit) return;
      const f = routes.features.find((x) => x.properties!.id === id);
      if (!f) return;
      const b = new maplibregl.LngLatBounds();
      for (const c of f.geometry.coordinates) b.extend(c as [number, number]);
      map.fitBounds(b, { padding: opts.padding ?? 64, maxZoom: 15.5, duration: duration(900) });
    },
    focusPin(id: string | null, zoom = 15.5) {
      if (activePin && map.getSource('pins')) map.setFeatureState({ source: 'pins', id: activePin }, { active: false });
      activePin = id;
      if (!id) return;
      if (map.getSource('pins')) map.setFeatureState({ source: 'pins', id }, { active: true });
      const p = opts.pins.find((x) => x.id === id);
      if (p) map.flyTo({ center: [p.lng, p.lat], zoom: Math.max(map.getZoom(), zoom), duration: duration(900), essential: false });
    },
    fit(bounds = opts.bounds, padding: maplibregl.PaddingOptions | number = opts.padding ?? 48) {
      if (bounds) map.fitBounds(bounds as LngLatBoundsLike, { padding, duration: duration(900) });
    },
    clear() {
      activeLeg = null;
      setLeg(null);
    },
  };
  return api;
}

export type TripMap = ReturnType<typeof createTripMap>;
