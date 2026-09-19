# Design notes

## What it is

Omoliday is the stock Omarchy clock plugin (`omarchy.clock`, MIT) with
public holidays marked on its calendar grid. It is packaged as a clone of the
stock clock: `manifest.json` carries `omarchy.clonedFrom: "omarchy.clock"`,
which the shell uses to swap the clock's bar entry for this plugin in place
when it is enabled (keeping the position and the clock's own settings such
as `format` and `weekStartDay`) and to restore the stock clock when it is
removed. `BarWidget.qml`, `Panel.qml` and `Model.js` start from the stock
files; the diffs against them are the holiday work and the identity.

## The mark

A public holiday's number takes the theme's selected-state colour
(`Style.selectedStateColor`, the same colour the year bar fills with) and
gets a four-pixel dot under it. Days of the neighbouring months keep their
dimmed number and get the dot at 40% opacity. Hovering a marked day fills
the cell like any hovered control and shows the name in a `PanelToolTip`
after the shell's usual 400 ms delay. Unmarked days have no hover: the
mouse area over each cell accepts no buttons and only enables hover when the
day is a holiday, so clicks and the scroll wheel keep reaching the grid's
own handlers.

Two holidays on one day are joined on one line with a middle dot.

## The data

[Nager.Date](https://date.nager.at) (MIT, `nager/Nager.Date` on GitHub)
serves `GET /api/v3/PublicHolidays/{year}/{countryCode}` as a JSON list.
Each entry carries `date`, `localName`, `name` (English), `global`,
`counties` (subdivision codes when not nationwide) and `types` (Public, Bank,
School, Authorities, Optional, Observance). The API needs no key, sets a
public seven-day cache header, and covers about two hundred countries; the
list is snapshotted in `tests/fixture-countries.json` and compiled into
`Countries.js` by `scripts/generate-countries.mjs`.

`Holidays.parseHolidays` keeps entries whose `types` include `Public`, that
are nationwide (`global: true`) or list the configured `region` in
`counties`, and whose date falls in the requested year. The English name
leads and the local name follows in brackets when it differs, since the
panel's interface is English throughout. Names are cleaned of control
characters and clamped to 80 characters; a year is capped at 40 entries.

The newer v4 endpoint on nagerholidays.com has a different shape
(`holidayTypes`, `nationalHoliday`, `subdivisionCodes`, no local name); v3
still answers on date.nager.at and was the one used here.

## Country and region

`Holidays.resolveCountry` decides the country once from the widget's
`country` setting, falling back to the territory of `Qt.locale().name`
(`en_ZA` gives `ZA`). `off` or `none` disables the feature and every
request. A code the snapshot does not list resolves to nothing rather than
to a request that would 404. `region` is validated as `<country>-<code>`.

## The picker

The rail under the month navigation reads `HOLIDAYS · <country>` and is laid
out like the year rail above it. Clicking it, or pressing `c`, swaps the
name for a text field, the way the year rail's double-tap opens the
birth-year fields: no popup, no list, nothing the panel did not already do.
`Holidays.matchCountry` resolves the draft on every keystroke against the
bundled table — a two-letter code first, then the first country whose name
starts with the text, then the first whose name contains it — and the match
is shown beside the field so the user sees what Enter will keep. An empty
draft clears the setting (back to the locale), `off` switches holidays off,
and an unmatched draft stays up to be corrected. The panel's key catcher is
blocked while the field is up, as it is for the birth-year editor.

While the country is still the locale's guess — a blank setting, which every
fresh install has — the rail reads `<country> · from locale` and its tooltip
says where the guess came from. A machine installed with an `en_US` locale
gets the United States whatever the country, so the guess is worth a glance.
The note goes away the moment a country is saved, the guess itself confirmed
with Enter included; no extra state is kept for it.

A region has no picker; it is a setting because it needs the source's own
subdivision codes, which the README documents.

## Cache and refresh

The cache lives as a `records` object on the widget's own entry in
`shell.json`, written through the shell's `updateEntryInline`, the same way
the stock panel writes `weekStartDay`:

```json
"records": {
  "version": 1,
  "years": {
    "ZA:2026": { "at": "2026-09-17", "days": [["2026-01-01", "New Year's Day"], ...] }
  }
}
```

- Keys are `<country or region>:<year>`; at most three years are kept.
  When one arrives past the cap, years the grid is not showing are evicted
  first (oldest fetch first), so two years fetched on the same day for one
  December grid cannot evict each other in turn.
- A year is fresh for 30 days after its fetch date, then fetched again. A
  fetch date in the future counts as stale.
- The payload is capped at 16 KiB (a worst-case three years of 40
  eighty-character names is under 12 KiB; a South African year is about
  450 bytes) and is never written past the cap.
- Everything read back is validated by `Holidays.readCache` as untrusted
  input: a hand-edited `shell.json` can drop entries but not crash the
  panel or smuggle text past the cleaner.

The panel asks for the years on the visible six-week grid (`gridYears`),
so December fetches the next year and January the previous one. One request
is in flight at a time; the next pending year starts when it settles. A
failed year backs off for 15 minutes, then an hour, then six hours between
attempts, driven by a single-shot timer, while the cached years keep
showing. Fetches are triggered when the panel loads, when its settings
arrive, when the grid's years change, when the country or region changes,
and on the IPC `refresh`; a fresh cache makes all of them no-ops.

## Bounding the network path

`HolidayFetch.qml` is the only file that talks to the network, with
`XMLHttpRequest` from QtQuick and nothing from the host:

- It accepts only URLs matching its `allowedUrl` rule — the one origin,
  the one path, a four-digit year, a two-letter uppercase country — so the
  worst a bad setting can do is be refused. `tests/package.test.cjs`
  evaluates that rule as written against every country's URL.
- The response is capped at 64 KiB in two places: `Content-Length` when the
  headers arrive, and the bytes received on every progress callback, since
  the source serves gzip without a `Content-Length` and Qt delivers the
  decompressed body in chunks. Either check aborts the request.
- A `Timer` enforces a 15-second deadline. Qt's `XMLHttpRequest` has no
  `timeout` property; assigning one is silently ignored (checked on Qt
  6.11), which is why the deadline is a timer.
- `abort()` is always deferred with `Qt.callLater`. Calling it from inside
  a `readystatechange` callback while the body was still arriving crashed
  the engine in testing; deferred, it is clean, and the DONE callback
  reports the outcome recorded before the abort.
- A redirect is refused. Qt follows redirects on its own and reports the
  final URL in `responseURL` only once the body starts arriving (it is
  empty while the headers are reported, on Qt 6.11), so the URL is compared
  with the one requested on every progress callback and again before the
  body is handed over; a mismatch is a failure, never a parse. The request
  carries no credentials, so nothing could leak on the way, but a body
  from anywhere else is not holiday data either.
- Only a 200 is parsed; a 404 (unknown country) or a transport failure
  (status 0) is a failure that enters the backoff schedule.

`tests/fetch-harness.qml`, run by `scripts/check.sh` against
`tests/fetch-server.py`, drives every one of those paths offline: a good
year, an oversized `Content-Length`, an oversized chunked body, a stalled
connection, a redirect, a 404, refused URLs, and a second request while one
is busy.

## One fetcher per shell

The bar mounts a widget once per monitor, so a two-monitor desktop runs two
copies of this panel, each with its own fetcher. Only the instance the host
lists first for this widget (`bar.moduleWidgets`) makes requests. The
decision is taken at each request rather than bound, so a monitor coming or
going is seen the next time a year is needed.

The others are given the year directly rather than left to find it in
`shell.json`. Saving the records does not reliably reach them: the shell
pushes a widget's settings to every instance only when it decides the
layout entry changed (`updateEntryInline` compares the old and new entry and
returns early when they are identical), so an instance that re-saves the
same holiday list tells the other screens nothing, and they mark no days at
all. So the instances talk to each other as well, through two functions on
the bar widget:

- `adoptHolidays(key, payload)` — the instance that fetched hands each of
  the others the year it just read, as JSON.
- `holidayDays(key)` — an instance that came up later (a monitor plugged in
  after the fetch, when no one has any reason to fetch again) asks its peers
  for the years it is missing, before anyone reaches for the network.

Nothing arriving that way is trusted: `Holidays.adoptedDays` parses and
revalidates the payload exactly as `readCache` does the persisted records,
the key has to name the country, region and year this panel is showing, and
only a year still fresh is offered back — so asking a peer can never keep a
refetch from happening. An adopted year is not saved again; the instance
that fetched has already written it, and two writers would only fight.

## What was deliberately left out

- No manual holidays, no agenda, no notifications: the ask was a mark and a
  name.
- No dropdown for the country. The shell's searchable dropdown opens a
  popup below its trigger, and the rail sits at the bottom of a panel whose
  window is fitted to its content, so the list would be clipped; the inline
  field needs no popup and matches the panel's other editor.
- No centre-anchor fix. The bar centres on the entry named by
  `centerAnchor`, which does not follow a clone; the README says how to
  point it at the plugin. The stock `omarchy plugin clone` has the same
  effect.
- No `Process`, `FileView` or files of its own: state goes through the
  shell's settings API like the stock clock's own preferences. The one
  command the plugin asks for is the stock clock's middle-click timezone
  picker, `omarchy-menu-timezone`, handed as a fixed literal to the bar's
  `run` facade, which the shell executes for every stock widget (the weather,
  microphone and update widgets do the same). Nothing in the plugin builds a
  command string, and no other command is ever requested.
