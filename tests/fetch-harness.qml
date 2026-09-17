import QtQuick
import ".." as Plugin
import "../Holidays.js" as Holidays

// Drives HolidayFetch.qml against tests/fetch-server.py: a good year, two
// oversized responses (declared and chunked), a stalled connection, a
// redirect, an unknown country, and requests the fetcher must refuse
// outright. Run by
// scripts/check.sh with `qml tests/fetch-harness.qml -- --port=<n>`; exits
// non-zero on the first expectation that does not hold.
Item {
    id: harness

    property int port: 18765
    property int index: 0
    property int failures: 0
    property var cases: [
        { key: "ZA:2026", code: "ZA", expect: "finished" },
        { key: "AA:2026", code: "AA", expect: "failed", reason: "oversize" },
        { key: "AB:2026", code: "AB", expect: "failed", reason: "oversize" },
        { key: "AC:2026", code: "AC", expect: "failed", reason: "timeout" },
        { key: "AD:2026", code: "AD", expect: "failed", reason: "redirect" },
        { key: "XX:2026", code: "XX", expect: "failed", reason: "http-404" }
    ]

    function origin() {
        return "http://127.0.0.1:" + harness.port
    }

    function check(ok, label) {
        console.log((ok ? "PASS " : "FAIL ") + label)
        if (!ok) harness.failures += 1
    }

    function next() {
        if (harness.index >= harness.cases.length) {
            finish()
            return
        }
        var item = harness.cases[harness.index]
        var url = origin() + "/api/v3/PublicHolidays/2026/" + item.code
        var started = fetcher.fetch(item.key, url)
        check(started, "fetch starts for " + item.key)
        if (!started) {
            harness.index += 1
            next()
            return
        }
        check(fetcher.busy && fetcher.busyKey === item.key, "fetcher reports busy for " + item.key)
        check(!fetcher.fetch("other", url), "second fetch refused while busy")
    }

    function settle(key, kind, detail) {
        var item = harness.cases[harness.index]
        check(key === item.key, "outcome names the request (" + key + ")")
        check(kind === item.expect, item.key + " outcome " + kind + " (expected " + item.expect + ")")
        if (item.expect === "failed") check(detail === item.reason, item.key + " reason " + detail + " (expected " + item.reason + ")")
        if (item.expect === "finished") {
            var parsed = Holidays.parseHolidays(detail, 2026, "")
            check(parsed.ok && parsed.days.length === 12, "ZA 2026 parses to 12 public holidays (" + parsed.days.length + ")")
            check(parsed.days[0][0] === "2026-01-01" && parsed.days[0][1] === "New Year's Day", "first holiday is New Year's Day")
        }
        check(!fetcher.busy, "fetcher idle after " + key)
        harness.index += 1
        next()
    }

    function finish() {
        check(fetcher.requestsStarted === harness.cases.length, "one request per case (" + fetcher.requestsStarted + ")")
        console.log(harness.failures === 0 ? "HARNESS OK" : "HARNESS FAILED (" + harness.failures + ")")
        Qt.exit(harness.failures === 0 ? 0 : 1)
    }

    Plugin.HolidayFetch {
        id: fetcher
        allowedOrigin: harness.origin()
        byteLimit: 65536
        deadlineMs: 1500
        onFinished: function(key, text) { harness.settle(key, "finished", text) }
        onFailed: function(key, reason) { harness.settle(key, "failed", reason) }
    }

    Timer {
        interval: 60000
        running: true
        onTriggered: {
            console.log("FAIL harness timed out at case " + harness.index)
            Qt.exit(1)
        }
    }

    Component.onCompleted: {
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++) {
            var match = /^--port=(\d+)$/.exec(args[i])
            if (match) harness.port = parseInt(match[1], 10)
        }
        check(!fetcher.fetch("bad", origin() + "/other"), "refuses a path outside the holiday API")
        check(!fetcher.fetch("bad", "https://example.invalid/api/v3/PublicHolidays/2026/ZA"), "refuses another origin")
        check(!fetcher.fetch("bad", origin() + "/api/v3/PublicHolidays/2026/za"), "refuses a lowercase country code")
        check(!fetcher.fetch("bad", origin() + "/api/v3/PublicHolidays/26/ZA"), "refuses a malformed year")
        check(fetcher.requestsStarted === 0, "refused requests never start")
        next()
    }
}
