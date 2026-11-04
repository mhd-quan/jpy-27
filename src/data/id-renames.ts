// Release rule (R-86, R-155). Until both trip phones have run a build that converts records (Task 2.1c), no
// item may be added to or removed from days 1 and 8, and no `line`/`from`/`to`/`via`/`path` of a leg may change.
//
// When an item's id changes while it is still the same visit (a key added because the day now comes back
// to the place, or a key reworded), the old id is mapped to the new one here, per day key, so the app
// moves its records onto it. Keep each entry pointing at an id the day has now: the app follows one step,
// so `a → b` then `b → c` is written `a → c`, `b → c`. scripts/check-ids.mjs enforces both.
export const ID_RENAMES: Record<string, Record<string, string>> = {};
