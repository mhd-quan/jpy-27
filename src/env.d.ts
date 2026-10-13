/// <reference types="astro/client" />
import type { TripMap } from './lib/map';

declare global {
  interface Window {
    __maps?: Record<string, TripMap>;
  }
}

export {};
