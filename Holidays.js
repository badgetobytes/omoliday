// Public-holiday model for Omoliday: which country to ask about, how a
// year's answer from Nager.Date is validated and trimmed, how the answers
// are cached on the widget's own shell.json entry, and how the calendar
// grid looks a day up. Plain ES5 with no Qt or host dependency, so the same
// file runs under node for the tests and in the shell's QML engine.
//
// Everything that comes from outside — the API response and the records
// read back from shell.json — is treated as untrusted: shapes are checked,
// strings are cleaned and clamped, counts are capped.

// One fixed origin, one path, HTTPS only. holidayUrl() is the only place a
// request URL is built, from a validated country code and year.
var SOURCE_ORIGIN = "https://date.nager.at"
var SOURCE_PATH = "/api/v3/PublicHolidays/"
var SOURCE_NAME = "Nager.Date"

// Response cap enforced progressively by HolidayFetch.qml; a year of
// holidays is two to four kilobytes.
var BYTE_LIMIT = 65536
// Cap on the records object persisted to shell.json.
var RECORD_LIMIT = 16384
var MAX_ENTRIES_PER_YEAR = 40
var MAX_NAME_LENGTH = 80
var MAX_CACHED_YEARS = 3
// A cached year is used as-is for this long, then refetched; national
// holiday lists change rarely, and once-off additions appear months ahead.
var FRESH_DAYS = 30
var MIN_YEAR = 1900
var MAX_YEAR = 2100
// Retry schedule after a failed fetch: a quarter hour, an hour, then six
// hours between attempts, so an offline machine asks a few times a day.
var BACKOFF_MS = [900000, 3600000, 21600000]
var MS_PER_DAY = 86400000

var COUNTRY_PATTERN = /^[A-Z]{2}$/
var REGION_PATTERN = /^[A-Z]{2}-[A-Z0-9]{1,3}$/
var DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/

// A real calendar date in yyyy-MM-dd: the pattern, then a round trip through
// Date.UTC so 2026-13-01 and 2026-02-30 are refused.
function validDateKey(text) {
  if (typeof text !== "string" || !DATE_PATTERN.test(text)) return false
  var year = Number(text.substr(0, 4))
  var month = Number(text.substr(5, 2))
  var day = Number(text.substr(8, 2))
  var date = new Date(Date.UTC(year, month - 1, day))
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
}
var CACHE_KEY_PATTERN = /^[A-Z]{2}(-[A-Z0-9]{1,3})?:\d{4}$/
// C0 and C1 control characters, built without escape sequences so the
// source stays plain printable text.
var CONTROL_CHARS = new RegExp("[" + String.fromCharCode(0) + "-" + String.fromCharCode(31)
  + String.fromCharCode(127) + "-" + String.fromCharCode(159) + "]", "g")
var ELLIPSIS = String.fromCharCode(8230)
var JOINER = " " + String.fromCharCode(183) + " "

function trimmed(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

// The territory of a locale name such as "en_ZA" or "de_DE.UTF-8"; empty
// for "C" and anything else without one.
function territoryOf(localeName) {
  var match = /^[a-z]{2,3}[_-]([A-Z]{2})(?:[._@]|$)/.exec(trimmed(localeName))
  return match ? match[1] : ""
}

// The country to show holidays for. An explicit setting wins; "off" or
// "none" switches holidays (and every request) off; anything blank follows
// the system locale. Unknown or unsupported codes resolve to "" rather than
// to a guess, so nothing is ever requested for a code the source does not
// have.
function resolveCountry(settingValue, localeName, isSupported) {
  var text = trimmed(settingValue).toUpperCase()
  if (text === "OFF" || text === "NONE") return ""
  if (text === "") text = territoryOf(localeName)
  if (!COUNTRY_PATTERN.test(text)) return ""
  if (typeof isSupported === "function" && !isSupported(text)) return ""
  return text
}

// Whether the setting switches the feature off outright.
function isOff(settingValue) {
  var text = trimmed(settingValue).toUpperCase()
  return text === "OFF" || text === "NONE"
}

// Whether the country is still the locale's guess: a blank setting, as a
// fresh install has, rather than a code or "off" the user chose. The panel
// says so on its rail until a choice is saved.
function followsLocale(settingValue) {
  return trimmed(settingValue) === ""
}

// What a draft typed into the country picker resolves to, against the
// [code, name] table: nothing (follow the locale), "off", a code, or the
// first country whose name starts with the text — failing that, contains
// it. The panel shows the match as the user types and keeps it on Enter.
function matchCountry(draft, countries) {
  var text = trimmed(draft)
  var none = { empty: false, off: false, code: "", name: "" }
  if (text === "") return { empty: true, off: false, code: "", name: "" }
  if (isOff(text)) return { empty: false, off: true, code: "", name: "" }
  var list = Array.isArray(countries) ? countries : []
  var upper = text.toUpperCase()
  var i
  if (COUNTRY_PATTERN.test(upper))
    for (i = 0; i < list.length; i++) if (list[i][0] === upper) return { empty: false, off: false, code: list[i][0], name: list[i][1] }
  var lower = text.toLowerCase()
  for (i = 0; i < list.length; i++)
    if (String(list[i][1]).toLowerCase().indexOf(lower) === 0) return { empty: false, off: false, code: list[i][0], name: list[i][1] }
  for (i = 0; i < list.length; i++)
    if (String(list[i][1]).toLowerCase().indexOf(lower) !== -1) return { empty: false, off: false, code: list[i][0], name: list[i][1] }
  return none
}

// A subdivision such as "DE-BY", only meaningful for the resolved country.
function normalizeRegion(value, country) {
  var text = trimmed(value).toUpperCase()
  if (!REGION_PATTERN.test(text)) return ""
  if (!country || text.substr(0, 3) !== country + "-") return ""
  return text
}

function validYear(year) {
  var n = Number(year)
  return Number.isInteger(n) && n >= MIN_YEAR && n <= MAX_YEAR ? n : 0
}

function holidayUrl(country, year) {
  var code = trimmed(country).toUpperCase()
  var n = validYear(year)
  if (!COUNTRY_PATTERN.test(code) || n === 0) return ""
  return SOURCE_ORIGIN + SOURCE_PATH + n + "/" + code
}

// Names are shown in a PlainText sink, so markup is inert; control
// characters and runaway lengths are still removed here so the persisted
// records stay small and the tooltip stays one line.
function cleanName(value) {
  if (typeof value !== "string") return ""
  var text = trimmed(value.replace(CONTROL_CHARS, " ").replace(/\s+/g, " "))
  if (text.length > MAX_NAME_LENGTH) text = trimmed(text.substr(0, MAX_NAME_LENGTH - 1)) + ELLIPSIS
  return text
}

// The interface is English throughout, so the English name leads and the
// local one follows in brackets when it differs: "German Unity Day (Tag der
// Deutschen Einheit)". Either alone when the other is missing.
function displayName(englishName, localName) {
  var english = cleanName(englishName)
  var local = cleanName(localName)
  if (english !== "" && local !== "" && english !== local) return cleanName(english + " (" + local + ")")
  return english || local
}

function isPublicType(types) {
  if (!Array.isArray(types)) return false
  for (var i = 0; i < types.length; i++) if (types[i] === "Public") return true
  return false
}

function appliesToRegion(counties, region) {
  if (!region || !Array.isArray(counties)) return false
  for (var i = 0; i < counties.length; i++) if (counties[i] === region) return true
  return false
}

function compareDays(a, b) {
  if (a[0] !== b[0]) return a[0] < b[0] ? -1 : 1
  if (a[1] !== b[1]) return a[1] < b[1] ? -1 : 1
  return 0
}

// One year's response, reduced to [date, name] pairs: public holidays only,
// nationwide ones plus those of the configured region, dated inside the
// requested year, deduplicated, sorted, capped.
function parseHolidays(text, year, region) {
  var data
  try {
    data = JSON.parse(String(text))
  } catch (error) {
    return { ok: false, reason: "invalid-json", days: [] }
  }
  if (!Array.isArray(data)) return { ok: false, reason: "not-a-list", days: [] }

  var wanted = String(validYear(year))
  var out = []
  var seen = {}
  for (var i = 0; i < data.length && out.length < MAX_ENTRIES_PER_YEAR; i++) {
    var item = data[i]
    if (!item || typeof item !== "object" || Array.isArray(item)) continue
    var date = typeof item.date === "string" ? item.date : ""
    if (!validDateKey(date) || date.substr(0, 4) !== wanted) continue
    if (!isPublicType(item.types)) continue
    if (item.global !== true && !appliesToRegion(item.counties, region)) continue
    var name = displayName(item.name, item.localName)
    if (name === "") continue
    var id = date + "\n" + name
    if (seen[id]) continue
    seen[id] = true
    out.push([date, name])
  }
  out.sort(compareDays)
  return { ok: true, reason: "", days: out }
}

function cacheKey(country, region, year) {
  return (region || country) + ":" + validYear(year)
}

function keyYear(key) {
  return parseInt(String(key).split(":")[1], 10)
}

function countryOfKey(key) {
  return String(key).split(":")[0].substr(0, 2)
}

function emptyCache() {
  return { years: {} }
}

function daysBetween(fromKey, toKey) {
  var from = Date.UTC(Number(fromKey.substr(0, 4)), Number(fromKey.substr(5, 2)) - 1, Number(fromKey.substr(8, 2)))
  var to = Date.UTC(Number(toKey.substr(0, 4)), Number(toKey.substr(5, 2)) - 1, Number(toKey.substr(8, 2)))
  return Math.round((to - from) / MS_PER_DAY)
}

function validDays(value, year) {
  if (!Array.isArray(value)) return null
  var wanted = String(year)
  var out = []
  var seen = {}
  for (var i = 0; i < value.length && out.length < MAX_ENTRIES_PER_YEAR; i++) {
    var pair = value[i]
    if (!Array.isArray(pair) || pair.length !== 2) continue
    var date = typeof pair[0] === "string" ? pair[0] : ""
    if (!validDateKey(date) || date.substr(0, 4) !== wanted) continue
    var name = cleanName(pair[1])
    if (name === "") continue
    var id = date + "\n" + name
    if (seen[id]) continue
    seen[id] = true
    out.push([date, name])
  }
  out.sort(compareDays)
  return out
}

// The persisted records, read back as untrusted input: anything that is not
// exactly the shape written by recordsPayload() is dropped, and the newest
// MAX_CACHED_YEARS entries are kept.
function readCache(records) {
  var cache = emptyCache()
  if (!records || typeof records !== "object" || Array.isArray(records)) return cache
  if (records.version !== 1 || !records.years || typeof records.years !== "object") return cache
  var kept = []
  for (var key in records.years) {
    if (!CACHE_KEY_PATTERN.test(key)) continue
    var entry = records.years[key]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    var at = validDateKey(entry.at) ? entry.at : ""
    var days = validDays(entry.days, keyYear(key))
    if (at === "" || days === null) continue
    kept.push({ key: key, at: at, days: days })
  }
  kept.sort(function(a, b) { return a.at < b.at ? 1 : a.at > b.at ? -1 : a.key < b.key ? -1 : 1 })
  for (var i = 0; i < kept.length && i < MAX_CACHED_YEARS; i++)
    cache.years[kept[i].key] = { at: kept[i].at, days: kept[i].days }
  return cache
}

function cachedEntry(cache, key) {
  return cache && cache.years && Object.prototype.hasOwnProperty.call(cache.years, key) ? cache.years[key] : null
}

// Fresh means fetched within FRESH_DAYS of today. A fetch date in the future
// (a clock that has since been corrected) counts as stale.
function isFresh(entry, todayKey) {
  if (!entry || typeof entry.at !== "string") return false
  var age = daysBetween(entry.at, todayKey)
  return age >= 0 && age <= FRESH_DAYS
}

// A new cache object — never a mutation, so QML bindings on it re-evaluate
// — with the year added and the cap kept by evicting, first, years the grid
// is not showing (oldest fetch first), and only then the ones it is. Without
// that protection two years fetched on the same day for one grid could
// evict each other in turn.
function withYear(cache, key, days, todayKey, protectedKeys) {
  var next = emptyCache()
  var keep = {}
  for (var p = 0; Array.isArray(protectedKeys) && p < protectedKeys.length; p++) keep[protectedKeys[p]] = true
  var entries = []
  for (var existing in cache.years) if (existing !== key) entries.push({ key: existing, entry: cache.years[existing], kept: keep[existing] === true })
  entries.sort(function(a, b) {
    if (a.kept !== b.kept) return a.kept ? -1 : 1
    return a.entry.at < b.entry.at ? 1 : a.entry.at > b.entry.at ? -1 : 0
  })
  next.years[key] = { at: todayKey, days: days.slice() }
  for (var i = 0; i < entries.length && i < MAX_CACHED_YEARS - 1; i++) next.years[entries[i].key] = entries[i].entry
  return next
}

// The cache keys the grid on screen needs for a country and region.
function gridKeys(country, region, years) {
  var out = []
  if (!country || !Array.isArray(years)) return out
  for (var i = 0; i < years.length; i++) out.push(cacheKey(country, region, years[i]))
  return out
}

function recordsPayload(cache) {
  return { version: 1, years: cache && cache.years ? cache.years : {} }
}

function recordsSize(payload) {
  return JSON.stringify(payload).length
}

function fitsRecordLimit(payload) {
  return recordsSize(payload) <= RECORD_LIMIT
}

// Distinct years on a six-week month grid: December's grid ends in January,
// January's starts in December, and both neighbours carry holidays.
function yearsInGrid(weeks) {
  var seen = {}
  var out = []
  if (!Array.isArray(weeks)) return out
  for (var w = 0; w < weeks.length; w++) {
    var days = weeks[w] && Array.isArray(weeks[w].days) ? weeks[w].days : []
    for (var d = 0; d < days.length; d++) {
      var year = validYear(days[d] ? days[d].year : 0)
      if (year === 0 || seen[year]) continue
      seen[year] = true
      out.push(year)
    }
  }
  out.sort(function(a, b) { return a - b })
  return out
}

// The lookup the grid renders from: date key to holiday name, with two
// holidays on one day joined on a single tooltip line.
function holidayMap(cache, country, region, years) {
  var map = {}
  if (!country) return map
  for (var i = 0; i < years.length; i++) {
    var entry = cachedEntry(cache, cacheKey(country, region, years[i]))
    if (!entry) continue
    for (var d = 0; d < entry.days.length; d++) {
      var date = entry.days[d][0]
      var name = entry.days[d][1]
      map[date] = Object.prototype.hasOwnProperty.call(map, date) ? map[date] + JOINER + name : name
    }
  }
  return map
}

function backoffMs(failures) {
  var n = Math.max(1, Math.round(Number(failures) || 0))
  return BACKOFF_MS[Math.min(n, BACKOFF_MS.length) - 1]
}

// Which cache keys need a request right now: not fresh, not being fetched,
// not inside a failure's backoff window.
function pendingKeys(cache, country, region, years, todayKey, busyKey, failures, nowMs) {
  var out = []
  if (!country) return out
  for (var i = 0; i < years.length; i++) {
    var key = cacheKey(country, region, years[i])
    if (key === busyKey) continue
    if (isFresh(cachedEntry(cache, key), todayKey)) continue
    var failure = failures && Object.prototype.hasOwnProperty.call(failures, key) ? failures[key] : null
    if (failure && Number(failure.until) > nowMs) continue
    out.push(key)
  }
  return out
}

// The next moment a backed-off key may be retried, or 0 when none is waiting.
function nextRetryAt(failures, nowMs) {
  var next = 0
  for (var key in failures) {
    var until = Number(failures[key] ? failures[key].until : 0)
    if (until > nowMs && (next === 0 || until < next)) next = until
  }
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    SOURCE_ORIGIN: SOURCE_ORIGIN,
    SOURCE_NAME: SOURCE_NAME,
    BYTE_LIMIT: BYTE_LIMIT,
    RECORD_LIMIT: RECORD_LIMIT,
    MAX_ENTRIES_PER_YEAR: MAX_ENTRIES_PER_YEAR,
    MAX_NAME_LENGTH: MAX_NAME_LENGTH,
    MAX_CACHED_YEARS: MAX_CACHED_YEARS,
    FRESH_DAYS: FRESH_DAYS,
    BACKOFF_MS: BACKOFF_MS,
    territoryOf: territoryOf,
    resolveCountry: resolveCountry,
    isOff: isOff,
    followsLocale: followsLocale,
    matchCountry: matchCountry,
    normalizeRegion: normalizeRegion,
    validYear: validYear,
    validDateKey: validDateKey,
    holidayUrl: holidayUrl,
    cleanName: cleanName,
    displayName: displayName,
    parseHolidays: parseHolidays,
    cacheKey: cacheKey,
    keyYear: keyYear,
    countryOfKey: countryOfKey,
    emptyCache: emptyCache,
    readCache: readCache,
    cachedEntry: cachedEntry,
    isFresh: isFresh,
    withYear: withYear,
    gridKeys: gridKeys,
    recordsPayload: recordsPayload,
    recordsSize: recordsSize,
    fitsRecordLimit: fitsRecordLimit,
    yearsInGrid: yearsInGrid,
    holidayMap: holidayMap,
    backoffMs: backoffMs,
    pendingKeys: pendingKeys,
    nextRetryAt: nextRetryAt
  }
}
