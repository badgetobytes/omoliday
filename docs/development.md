# Development

## The gate

```sh
bash scripts/check.sh
```

Runs the node test suites (`tests/holidays.test.cjs` for the model,
`tests/package.test.cjs` for the packaging and the runtime surface), lints
`HolidayFetch.qml`, then starts `tests/fetch-server.py` on a local port and
drives `tests/fetch-harness.qml` against it with the `qml` tool, which
exercises every guard in the fetcher offline. On an Omarchy desktop it also
runs `omarchy plugin validate` and lints `Panel.qml` and `BarWidget.qml`
with the shell's `qs` module mapped in. CI runs the same script in an
`archlinux:base` container.

The country table is generated; `tests/package.test.cjs` checks that
`Countries.js` equals the generator's output from the committed snapshot:

```sh
node scripts/generate-countries.mjs tests/fixture-countries.json > Countries.js
```

## Installing from a checkout

Only committed work is installed: `omarchy plugin add` clones the repository.

```sh
omarchy plugin add ~/Projects/omoliday --enable --yes   # first time
omarchy plugin update fstander.omoliday --yes            # after each commit
omarchy restart shell                                      # QML is cached in memory
```

Enabling replaces the stock clock's bar entry in place; removing the plugin
restores it.

## Inspecting the state

```sh
omarchy-shell fstander.omoliday holidays          # country, cache, last outcome, as JSON
omarchy-shell fstander.omoliday refetchHolidays   # drop the cache and ask again
omarchy-shell fstander.omoliday toggle            # open or close the calendar
omarchy bar set fstander.omoliday country ZA
omarchy bar set fstander.omoliday region DE-BY
journalctl --user -o short-precise --since "10 minutes ago" | grep -i omoliday
```

The shell keeps `shell.json` in memory; a hand edit is only seen after
`omarchy restart shell`, and the next save from the shell overwrites it.

## The preview

`preview.png` is the open panel captured with `grim` on the monitor that
shows it, cropped to the popup's own border and centred on a 16:9 canvas of
the popup's background colour, so nothing of the desktop is in it:

```sh
grim -g "<monitor x>,<y> <w>x<h>" full.png
magick full.png -crop <w>x<h>+<x>+<y> +repage inner.png
bg=$(magick inner.png -format '%[pixel:p{80,300}]' info:)
magick inner.png -background "$bg" -gravity center -extent 1188x668 -strip preview.png
```
