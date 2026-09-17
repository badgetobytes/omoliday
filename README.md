# Omoliday

The Omarchy clock, with the public holidays on the calendar.

![Omoliday calendar](preview.png)

Omoliday is Omarchy's own clock and calendar with one addition: the public
holidays of your country are marked on the month grid. A holiday's number takes
the accent colour and gets a small dot beneath it; hovering the day shows its
name. The dates come from [Nager.Date](https://date.nager.at), an open-source
holiday database covering two hundred countries, one year at a time, and are
kept on the widget's own entry in `shell.json`. Everything else — the label,
the format ring, the week numbers, the year and life bars, the keys — is the
stock clock, unchanged.

## Install

```sh
omarchy plugin add https://github.com/badgetobytes/omoliday.git --enable
```

It takes the stock clock's place in the bar, keeping the clock's position and
settings. If your bar centres on the clock (`"centerAnchor": "omarchy.clock"`
in `~/.config/omarchy/shell.json`), point that at `fstander.omoliday` to keep
the exact centring. Update with `omarchy plugin update fstander.omoliday` and
remove with `omarchy plugin remove fstander.omoliday`, which puts the stock
clock back. No install hooks; the plugin opens no file and asks for no password.
The only command it ever asks the bar to run is the stock clock's middle-click
timezone picker, a fixed name with nothing appended. Its only network use is
one HTTPS request per calendar year to Nager.Date, described below.

## Holidays

Click the clock to open the calendar. Days with a public holiday carry a dot
under the number; hover one for the holiday's name. The years on screen are
looked up as you step through the calendar, so December already shows New
Year's Day and January shows the holidays that closed the old year.

**Country.** The rail under the grid names the country whose holidays are
marked. By default it follows the system locale (`en_ZA` means South Africa)
and says so — `United States · from locale` — until a country is saved. Omarchy
installs with an `en_US` locale whatever the country, so check it once. Click
the rail, or press `c`, to change it: type a two-letter code or the start of a
name — `za`, `south a`, `germ` — and the match shows beside the field; Enter
keeps it (the guess too, if it is right), Escape leaves things as they were. An
empty field goes back to the locale, and `off` shows no holidays and sends no
requests. The same setting
can be written from a terminal:

```sh
omarchy bar set fstander.omoliday country ZA
```

Countries with regional public holidays can add one subdivision, for example
`omarchy bar set fstander.omoliday region DE-BY` for Bavaria; nationwide
holidays are always shown.

**Refresh.** A year is fetched once and reused for thirty days, then fetched
again. A failed fetch — offline, or a country the source does not have — is
retried after a quarter of an hour, then an hour, then every six hours, while
the cached years keep showing. `omarchy-shell fstander.omoliday holidays`
prints the current state as JSON; `omarchy-shell fstander.omoliday refetchHolidays`
drops the cache and asks again.

## Clock

| Action | Effect |
| --- | --- |
| Left click | Open or close the calendar |
| Right click | Cycle the label format (`omarchy bar set fstander.omoliday format "HH:mm"` sets one directly) |
| Middle click | Open the timezone picker, as the stock clock does |
| Scroll wheel on the grid | Previous or next month |
| Left / Right, `[` / `]` | Previous or next month |
| Up / Down, `{` / `}` | Previous or next year |
| `t` or Enter | Back to today |
| `w` or click the W heading | Start weeks on Monday or Sunday |
| `c` or click the holidays rail | Choose the country |
| Double-tap the year bar | Set a birth year for the life bar |
| Escape | Close |

Every stock behaviour is kept: the label, the format ring, the keys, the week
and life bars, and the timezone picker on middle click, which asks the bar to
run Omarchy's own `omarchy-menu-timezone` exactly as the stock clock does.

## Themes

The panel follows the active Omarchy palette and repaints on a theme switch.
The holiday mark uses the theme's selected-state colour, the same one the year
bar fills with. No theme files are installed.

## Your data

The widget's entry in `~/.config/omarchy/shell.json` holds its settings
(`country`, `region`, the clock's formats) and a `records` object with the
cached holidays: at most three years of dates and names, under 16 KiB, written
through the shell's plugin settings API. Removing the plugin restores the stock
clock's entry; the cached years stay on it until the entry is edited.

Each fetch is a single `GET https://date.nager.at/api/v3/PublicHolidays/<year>/<country>`
with no headers, cookies or identifiers beyond what any HTTPS request carries.
The response is capped at 64 KiB and cut off past that, a redirect is refused,
every field is validated before use, and nothing else is ever requested. On a
desktop with several monitors the bar mounts the widget once per monitor; only
one of those copies fetches, and the others show what it saves.

## Read more

- [Design notes](docs/design.md): the data source, the cache and retry policy,
  and how the network path is bounded.
- [Development](docs/development.md): running the gate, installing from a
  checkout, inspecting the state over shell IPC.

## License and credits

MIT, see [LICENSE](LICENSE). The clock, calendar and date model are Omarchy's
own `omarchy.clock` plugin (MIT, © Omarchy), carried here with the holiday
work added. Holiday data is served by [Nager.Date](https://github.com/nager/Nager.Date)
(MIT). Tested on Omarchy 4.0.4 with Qt 6.11.
