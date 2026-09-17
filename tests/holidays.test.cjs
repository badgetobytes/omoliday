const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const H = require("../Holidays.js");
const C = require("../Countries.js");
const Model = require("../Model.js");

const fixture = fs.readFileSync(path.join(__dirname, "fixture-za-2026.json"), "utf8");
const supported = C.isSupported;
const MIDDLE_DOT = String.fromCharCode(183);

test("territoryOf reads the territory out of a locale name", () => {
  assert.equal(H.territoryOf("en_ZA"), "ZA");
  assert.equal(H.territoryOf("de_DE.UTF-8"), "DE");
  assert.equal(H.territoryOf("pt-BR"), "BR");
  assert.equal(H.territoryOf("sr_RS@latin"), "RS");
  assert.equal(H.territoryOf("C"), "");
  assert.equal(H.territoryOf("POSIX"), "");
  assert.equal(H.territoryOf("en"), "");
  assert.equal(H.territoryOf(""), "");
  assert.equal(H.territoryOf(null), "");
});

test("resolveCountry: the setting wins, the locale fills in, off disables, junk resolves to nothing", () => {
  assert.equal(H.resolveCountry("ZA", "en_US", supported), "ZA");
  assert.equal(H.resolveCountry(" za ", "en_US", supported), "ZA");
  assert.equal(H.resolveCountry("", "en_ZA", supported), "ZA");
  assert.equal(H.resolveCountry(undefined, "en_US", supported), "US");
  assert.equal(H.resolveCountry(null, "de_DE.UTF-8", supported), "DE");
  assert.equal(H.resolveCountry("off", "en_ZA", supported), "");
  assert.equal(H.resolveCountry("None", "en_ZA", supported), "");
  assert.equal(H.resolveCountry("", "C", supported), "");
  assert.equal(H.resolveCountry("XX", "en_ZA", supported), "");
  assert.equal(H.resolveCountry("ZAF", "en_ZA", supported), "");
  assert.equal(H.resolveCountry("Z A", "en_ZA", supported), "");
  assert.equal(H.resolveCountry({}, "en_ZA", supported), "");
  assert.equal(H.resolveCountry("../", "en_ZA", supported), "");
  assert.equal(H.resolveCountry("XX", "en_ZA"), "XX");
});

test("isOff recognises the switch-off values only", () => {
  assert.equal(H.isOff("off"), true);
  assert.equal(H.isOff(" NONE "), true);
  assert.equal(H.isOff(""), false);
  assert.equal(H.isOff("ZA"), false);
  assert.equal(H.isOff(null), false);
});

test("matchCountry resolves a code, a name prefix, a name fragment, off, or nothing", () => {
  const table = C.COUNTRIES;
  assert.deepEqual(H.matchCountry("", table), { empty: true, off: false, code: "", name: "" });
  assert.deepEqual(H.matchCountry("   ", table), { empty: true, off: false, code: "", name: "" });
  assert.deepEqual(H.matchCountry("off", table), { empty: false, off: true, code: "", name: "" });
  assert.deepEqual(H.matchCountry("za", table), { empty: false, off: false, code: "ZA", name: "South Africa" });
  assert.deepEqual(H.matchCountry("South Africa", table), { empty: false, off: false, code: "ZA", name: "South Africa" });
  assert.deepEqual(H.matchCountry("south a", table), { empty: false, off: false, code: "ZA", name: "South Africa" });
  assert.equal(H.matchCountry("germ", table).code, "DE");
  assert.equal(H.matchCountry("kingdom", table).code, "GB");
  assert.equal(H.matchCountry("de", table).code, "DE");
  assert.equal(H.matchCountry("xx", table).code, "");
  assert.deepEqual(H.matchCountry("nowhere land", table), { empty: false, off: false, code: "", name: "" });
  assert.deepEqual(H.matchCountry("za", null), { empty: false, off: false, code: "", name: "" });
  // Two letters are read as a code first, then a name prefix beats a fragment.
  assert.equal(H.matchCountry("ma", table).code, "MA");
  const prefix = H.matchCountry("mal", table);
  assert.ok(prefix.name.toLowerCase().startsWith("mal"), prefix.name);
  assert.equal(H.matchCountry("donia", table).code, "MK");
});

test("normalizeRegion accepts the resolved country's own subdivisions only", () => {
  assert.equal(H.normalizeRegion("de-by", "DE"), "DE-BY");
  assert.equal(H.normalizeRegion("DE-BY", "ZA"), "");
  assert.equal(H.normalizeRegion("DE-BY", ""), "");
  assert.equal(H.normalizeRegion("GB-ENG", "GB"), "GB-ENG");
  assert.equal(H.normalizeRegion("US-CA", "US"), "US-CA");
  assert.equal(H.normalizeRegion("DE-BAYERN", "DE"), "");
  assert.equal(H.normalizeRegion("", "DE"), "");
  assert.equal(H.normalizeRegion(7, "DE"), "");
});

test("holidayUrl builds the one fixed origin and path from validated parts", () => {
  assert.equal(H.holidayUrl("ZA", 2026), "https://date.nager.at/api/v3/PublicHolidays/2026/ZA");
  assert.equal(H.holidayUrl("za", "2026"), "https://date.nager.at/api/v3/PublicHolidays/2026/ZA");
  assert.equal(H.holidayUrl("ZA", 1800), "");
  assert.equal(H.holidayUrl("ZA", 2101), "");
  assert.equal(H.holidayUrl("ZA", 2026.5), "");
  assert.equal(H.holidayUrl("ZA", "20x6"), "");
  assert.equal(H.holidayUrl("Z/A", 2026), "");
  assert.equal(H.holidayUrl("../ZA", 2026), "");
  assert.equal(H.holidayUrl("ZA?x=1", 2026), "");
  assert.equal(H.holidayUrl("", 2026), "");
  for (const [code] of C.COUNTRIES)
    assert.match(H.holidayUrl(code, 2026), /^https:\/\/date\.nager\.at\/api\/v3\/PublicHolidays\/2026\/[A-Z]{2}$/);
});

test("parseHolidays reduces the South Africa 2026 fixture to twelve dated names", () => {
  const parsed = H.parseHolidays(fixture, 2026, "");
  assert.equal(parsed.ok, true);
  assert.equal(parsed.days.length, 12);
  assert.deepEqual(parsed.days[0], ["2026-01-01", "New Year's Day"]);
  assert.deepEqual(parsed.days.find((d) => d[0] === "2026-12-16"), ["2026-12-16", "Day of Reconciliation"]);
  assert.deepEqual(parsed.days.find((d) => d[0] === "2026-08-10"), ["2026-08-10", "National Women's Day"]);
  // The source lists an English name and a local name; both show when they differ.
  assert.deepEqual(parsed.days.find((d) => d[0] === "2026-12-26"), ["2026-12-26", "Day of Goodwill (St. Stephen's Day)"]);
  const dates = parsed.days.map((d) => d[0]);
  assert.deepEqual(dates, [...dates].sort());
});

test("parseHolidays keeps only public, nationwide-or-regional holidays inside the year", () => {
  const rows = [
    { date: "2026-01-01", localName: "A", name: "A", global: true, types: ["Public"] },
    { date: "2025-12-31", localName: "wrong year", name: "wrong year", global: true, types: ["Public"] },
    { date: "2026-02-02", localName: "bank", name: "bank", global: true, types: ["Bank"] },
    { date: "2026-03-03", localName: "regional", name: "regional", global: false, counties: ["DE-BY", "DE-BW"], types: ["Public"] },
    { date: "2026-04-04", localName: "no types", name: "no types", global: true },
    { date: "2026-05-05", localName: "", name: "", global: true, types: ["Public"] },
    { date: "2026-06-06", localName: "A", name: "A", global: true, types: ["Public"] },
    { date: "2026-06-06", localName: "A", name: "A", global: true, types: ["Public"] },
    { date: "2026/07/07", localName: "bad date", name: "bad date", global: true, types: ["Public"] },
    { date: "2026-07-07", localName: "not global", name: "not global", global: "true", counties: null, types: ["Public"] },
    "not an object",
    null,
    [],
    { date: "2026-08-08", name: 42, localName: ["x"], global: true, types: ["Public"] },
  ];
  const nationwide = H.parseHolidays(JSON.stringify(rows), 2026, "");
  assert.deepEqual(nationwide.days, [["2026-01-01", "A"], ["2026-06-06", "A"]]);
  const bavaria = H.parseHolidays(JSON.stringify(rows), 2026, "DE-BY");
  assert.deepEqual(bavaria.days.map((d) => d[0]), ["2026-01-01", "2026-03-03", "2026-06-06"]);
  const saxony = H.parseHolidays(JSON.stringify(rows), 2026, "DE-SN");
  assert.deepEqual(saxony.days.map((d) => d[0]), ["2026-01-01", "2026-06-06"]);
});

test("parseHolidays rejects non-JSON and non-list bodies", () => {
  assert.deepEqual(H.parseHolidays("<html>", 2026, ""), { ok: false, reason: "invalid-json", days: [] });
  assert.deepEqual(H.parseHolidays('{"date":"2026-01-01"}', 2026, ""), { ok: false, reason: "not-a-list", days: [] });
  assert.equal(H.parseHolidays("", 2026, "").ok, false);
  assert.equal(H.parseHolidays(undefined, 2026, "").ok, false);
  assert.deepEqual(H.parseHolidays("[]", 2026, ""), { ok: true, reason: "", days: [] });
});

test("parseHolidays caps the number of entries and the length of a name", () => {
  const rows = [];
  for (let i = 0; i < 100; i++)
    rows.push({ date: "2026-01-" + String((i % 28) + 1).padStart(2, "0"), localName: "name " + i, name: "name " + i, global: true, types: ["Public"] });
  const parsed = H.parseHolidays(JSON.stringify(rows), 2026, "");
  assert.equal(parsed.days.length, H.MAX_ENTRIES_PER_YEAR);
  const long = H.parseHolidays(
    JSON.stringify([{ date: "2026-01-01", localName: "x".repeat(500), name: "y".repeat(500), global: true, types: ["Public"] }]),
    2026,
    ""
  );
  assert.equal(long.days[0][1].length, H.MAX_NAME_LENGTH);
});

test("cleanName strips control characters and collapses whitespace", () => {
  const dirty = "New" + String.fromCharCode(0) + "Year" + String.fromCharCode(9) + "  Day " + String.fromCharCode(27) + "[31m" + String.fromCharCode(133);
  assert.equal(H.cleanName(dirty), "New Year Day [31m");
  assert.equal(H.cleanName(42), "");
  assert.equal(H.cleanName("  "), "");
  assert.equal(H.cleanName("<b>bold</b>"), "<b>bold</b>");
});

test("displayName leads with the English name and brackets a different local one", () => {
  assert.equal(H.displayName("German Unity Day", "Tag der Deutschen Einheit"), "German Unity Day (Tag der Deutschen Einheit)");
  assert.equal(H.displayName("New Year's Day", "New Year's Day"), "New Year's Day");
  assert.equal(H.displayName("", "Koningsdag"), "Koningsdag");
  assert.equal(H.displayName("King's Day", ""), "King's Day");
  assert.equal(H.displayName(null, undefined), "");
});

test("readCache accepts only the shape recordsPayload writes, newest years first", () => {
  assert.deepEqual(H.readCache(null), { years: {} });
  assert.deepEqual(H.readCache("x"), { years: {} });
  assert.deepEqual(H.readCache([]), { years: {} });
  assert.deepEqual(H.readCache({ version: 2, years: {} }), { years: {} });
  assert.deepEqual(H.readCache({ version: 1 }), { years: {} });
  const records = {
    version: 1,
    years: {
      "ZA:2026": { at: "2026-09-17", days: [["2026-01-01", "New Year's Day"], ["2026-13-01", "bad"], ["2026-02-30", "bad"], ["2025-01-01", "wrong year"], "junk", ["2026-01-01", "New Year's Day"], ["2026-02-02"]] },
      "ZA:2020": { at: "2026-02-30", days: [["2020-01-01", "bad fetch date"]] },
      "ZA:2025": { at: "2025-09-17", days: [["2025-01-01", "New Year's Day"]] },
      "ZA:2024": { at: "2024-09-17", days: [["2024-01-01", "New Year's Day"]] },
      "ZA:2023": { at: "2023-09-17", days: [["2023-01-01", "New Year's Day"]] },
      "ZA:2022": { at: "not a date", days: [] },
      "bad key": { at: "2026-01-01", days: [] },
      "DE-BY:2026": { at: "2026-09-01", days: "nope" },
      "ZA:2021": null,
    },
  };
  const cache = H.readCache(records);
  assert.deepEqual(Object.keys(cache.years).sort(), ["ZA:2024", "ZA:2025", "ZA:2026"]);
  assert.deepEqual(cache.years["ZA:2026"].days, [["2026-01-01", "New Year's Day"]]);
  assert.equal(cache.years["ZA:2026"].at, "2026-09-17");
});

test("isFresh honours the freshness window and treats future fetch dates as stale", () => {
  assert.equal(H.isFresh({ at: "2026-09-17", days: [] }, "2026-09-17"), true);
  assert.equal(H.isFresh({ at: "2026-08-18", days: [] }, "2026-09-17"), true);
  assert.equal(H.isFresh({ at: "2026-08-17", days: [] }, "2026-09-17"), false);
  assert.equal(H.isFresh({ at: "2026-09-18", days: [] }, "2026-09-17"), false);
  assert.equal(H.isFresh(null, "2026-09-17"), false);
  assert.equal(H.isFresh({ days: [] }, "2026-09-17"), false);
});

test("withYear returns a new cache and evicts the oldest fetch past the cap", () => {
  const cache = H.emptyCache();
  const c1 = H.withYear(cache, "ZA:2024", [], "2026-01-01");
  assert.notEqual(c1, cache);
  assert.deepEqual(cache, { years: {} });
  const c2 = H.withYear(c1, "ZA:2025", [], "2026-02-01");
  const c3 = H.withYear(c2, "ZA:2026", [], "2026-03-01");
  const c4 = H.withYear(c3, "ZA:2027", [], "2026-04-01");
  assert.deepEqual(Object.keys(c4.years).sort(), ["ZA:2025", "ZA:2026", "ZA:2027"]);
  const days = [["2025-01-01", "x"]];
  const again = H.withYear(c4, "ZA:2025", days, "2026-05-01");
  assert.deepEqual(Object.keys(again.years).sort(), ["ZA:2025", "ZA:2026", "ZA:2027"]);
  assert.equal(again.years["ZA:2025"].at, "2026-05-01");
  assert.notEqual(again.years["ZA:2025"].days, days);
  assert.deepEqual(again.years["ZA:2025"].days, days);
});

test("withYear evicts unprotected years before the ones the grid is showing", () => {
  let cache = H.emptyCache();
  cache = H.withYear(cache, "US:2026", [], "2026-09-17");
  cache = H.withYear(cache, "DE:2026", [], "2026-09-17");
  cache = H.withYear(cache, "DE:2027", [], "2026-09-17");
  // Back to South Africa on a December grid: both ZA years must survive
  // each other's arrival even though every entry was fetched today.
  const shown = H.gridKeys("ZA", "", [2026, 2027]);
  assert.deepEqual(shown, ["ZA:2026", "ZA:2027"]);
  cache = H.withYear(cache, "ZA:2026", [["2026-12-25", "Christmas Day"]], "2026-09-17", shown);
  cache = H.withYear(cache, "ZA:2027", [["2027-01-01", "New Year's Day"]], "2026-09-17", shown);
  assert.ok(cache.years["ZA:2026"] && cache.years["ZA:2027"], Object.keys(cache.years).join(","));
  assert.equal(Object.keys(cache.years).length, H.MAX_CACHED_YEARS);
  assert.deepEqual(H.pendingKeys(cache, "ZA", "", [2026, 2027], "2026-09-17", "", {}, 0), []);
  assert.deepEqual(H.gridKeys("", "", [2026]), []);
  assert.deepEqual(H.gridKeys("DE", "DE-BY", [2026]), ["DE-BY:2026"]);
});

test("a worst-case cache stays under the records limit and round-trips", () => {
  let cache = H.emptyCache();
  for (let y = 0; y < H.MAX_CACHED_YEARS; y++) {
    const days = [];
    for (let i = 0; i < H.MAX_ENTRIES_PER_YEAR; i++) {
      const name = String(i).padStart(2, "0") + "x".repeat(H.MAX_NAME_LENGTH - 2);
      days.push([`${2026 + y}-${i < 28 ? "01" : "02"}-${String((i % 28) + 1).padStart(2, "0")}`, name]);
    }
    cache = H.withYear(cache, `ZA:${2026 + y}`, days, "2026-09-17");
  }
  const payload = H.recordsPayload(cache);
  assert.ok(H.fitsRecordLimit(payload), `records ${H.recordsSize(payload)} > ${H.RECORD_LIMIT}`);
  assert.deepEqual(H.readCache(JSON.parse(JSON.stringify(payload))), cache);
});

test("the South Africa fixture round-trips through the records in under a kilobyte", () => {
  const parsed = H.parseHolidays(fixture, 2026, "");
  const cache = H.withYear(H.emptyCache(), "ZA:2026", parsed.days, "2026-09-17");
  const payload = H.recordsPayload(cache);
  assert.ok(H.recordsSize(payload) < 1024, `a South African year is ${H.recordsSize(payload)} bytes`);
  assert.deepEqual(H.readCache(JSON.parse(JSON.stringify(payload))), cache);
});

test("yearsInGrid: a December grid reaches into January and a January grid back into December", () => {
  assert.deepEqual(H.yearsInGrid(Model.monthGrid(2026, 11, 1, "2026-12-01")), [2026, 2027]);
  assert.deepEqual(H.yearsInGrid(Model.monthGrid(2026, 0, 1, "2026-01-01")), [2025, 2026]);
  assert.deepEqual(H.yearsInGrid(Model.monthGrid(2026, 5, 1, "2026-06-01")), [2026]);
  assert.deepEqual(H.yearsInGrid(null), []);
  assert.deepEqual(H.yearsInGrid([{ days: [{ year: 1200 }] }]), []);
});

test("holidayMap keys the visible years by date and joins two holidays on one day", () => {
  let cache = H.withYear(H.emptyCache(), "ZA:2026", [["2026-12-25", "Christmas Day"], ["2026-12-26", "Day of Goodwill"], ["2026-12-26", "Boxing Day"]], "2026-09-17");
  cache = H.withYear(cache, "ZA:2027", [["2027-01-01", "New Year's Day"]], "2026-09-17");
  const map = H.holidayMap(cache, "ZA", "", [2026, 2027]);
  assert.equal(map["2026-12-25"], "Christmas Day");
  assert.equal(map["2026-12-26"], "Day of Goodwill " + MIDDLE_DOT + " Boxing Day");
  assert.equal(map["2027-01-01"], "New Year's Day");
  assert.equal(Object.keys(map).length, 3);
  assert.deepEqual(H.holidayMap(cache, "", "", [2026]), {});
  assert.deepEqual(H.holidayMap(cache, "DE", "", [2026]), {});
  assert.deepEqual(H.holidayMap(cache, "ZA", "ZA-WC", [2026]), {});
});

test("pendingKeys skips fresh, in-flight and backed-off years", () => {
  const cache = H.withYear(H.emptyCache(), "ZA:2026", [], "2026-09-17");
  const now = Date.UTC(2026, 8, 17, 12);
  assert.deepEqual(H.pendingKeys(cache, "ZA", "", [2026, 2027], "2026-09-17", "", {}, now), ["ZA:2027"]);
  assert.deepEqual(H.pendingKeys(cache, "ZA", "", [2026, 2027], "2026-11-17", "", {}, now), ["ZA:2026", "ZA:2027"]);
  assert.deepEqual(H.pendingKeys(cache, "ZA", "", [2026, 2027], "2026-09-17", "ZA:2027", {}, now), []);
  assert.deepEqual(H.pendingKeys(cache, "ZA", "", [2027], "2026-09-17", "", { "ZA:2027": { count: 1, until: now + 1000 } }, now), []);
  assert.deepEqual(H.pendingKeys(cache, "ZA", "", [2027], "2026-09-17", "", { "ZA:2027": { count: 1, until: now - 1 } }, now), ["ZA:2027"]);
  assert.deepEqual(H.pendingKeys(cache, "", "", [2026], "2026-09-17", "", {}, now), []);
  assert.deepEqual(H.pendingKeys(cache, "ZA", "ZA-WC", [2026], "2026-09-17", "", {}, now), ["ZA-WC:2026"]);
});

test("backoff grows to six hours and nextRetryAt finds the earliest window", () => {
  assert.equal(H.backoffMs(1), 15 * 60 * 1000);
  assert.equal(H.backoffMs(2), 60 * 60 * 1000);
  assert.equal(H.backoffMs(3), 6 * 60 * 60 * 1000);
  assert.equal(H.backoffMs(9), 6 * 60 * 60 * 1000);
  assert.equal(H.backoffMs(0), 15 * 60 * 1000);
  assert.equal(H.backoffMs("junk"), 15 * 60 * 1000);
  assert.equal(H.nextRetryAt({}, 100), 0);
  assert.equal(H.nextRetryAt({ a: { until: 500 }, b: { until: 300 }, c: { until: 50 }, d: null }, 100), 300);
});

test("validDateKey refuses shapes that are not real dates", () => {
  assert.equal(H.validDateKey("2026-09-17"), true);
  assert.equal(H.validDateKey("2024-02-29"), true);
  assert.equal(H.validDateKey("2026-02-29"), false);
  assert.equal(H.validDateKey("2026-13-01"), false);
  assert.equal(H.validDateKey("2026-00-10"), false);
  assert.equal(H.validDateKey("2026-04-31"), false);
  assert.equal(H.validDateKey("2026-4-1"), false);
  assert.equal(H.validDateKey("20260401"), false);
  assert.equal(H.validDateKey(20260401), false);
  assert.equal(H.validDateKey(null), false);
});

test("cache key helpers", () => {
  assert.equal(H.cacheKey("ZA", "", 2026), "ZA:2026");
  assert.equal(H.cacheKey("DE", "DE-BY", 2026), "DE-BY:2026");
  assert.equal(H.keyYear("DE-BY:2026"), 2026);
  assert.equal(H.countryOfKey("DE-BY:2026"), "DE");
  assert.equal(H.countryOfKey("ZA:2026"), "ZA");
});

test("Countries: the Nager.Date list, with names and without duplicates", () => {
  assert.ok(C.COUNTRIES.length >= 200);
  assert.equal(new Set(C.COUNTRIES.map((c) => c[0])).size, C.COUNTRIES.length);
  assert.equal(C.name("ZA"), "South Africa");
  assert.equal(C.isSupported("ZA"), true);
  assert.equal(C.isSupported("XX"), false);
  assert.equal(C.name("XX"), "");
  assert.equal(C.isSupported("__proto__"), false);
  assert.equal(C.isSupported("constructor"), false);
  for (const [code, name] of C.COUNTRIES) {
    assert.match(code, /^[A-Z]{2}$/);
    assert.ok(name.length > 0 && name.length < 64);
  }
});

test("followsLocale: only a blank setting is the locale's guess", () => {
  assert.equal(H.followsLocale(""), true);
  assert.equal(H.followsLocale("  "), true);
  assert.equal(H.followsLocale(undefined), true);
  assert.equal(H.followsLocale(null), true);
  assert.equal(H.followsLocale("off"), false);
  assert.equal(H.followsLocale("ZA"), false);
});
