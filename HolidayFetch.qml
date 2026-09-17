import QtQuick

// One bounded HTTPS GET at a time, for one year of public holidays. QtQuick
// only: no host imports, no processes, no files.
//
// What bounds the request, because a reviewer will ask:
//   - fetch() accepts only a URL that Holidays.holidayUrl built — the one
//     allowed origin, one path, a four-digit year, a two-letter country —
//     and the pattern below rejects anything else before a request exists;
//   - the response is capped at byteLimit twice over: against Content-Length
//     the moment the headers arrive, then against the bytes received on every
//     progress callback, because the source serves gzip without a
//     Content-Length and the body arrives in chunks;
//   - a response that arrives from any URL other than the one requested is
//     refused: Qt follows redirects by itself, and reports the final URL
//     only once the body starts arriving, so the check runs on every
//     progress callback and again before the body is handed over;
//   - a Timer enforces the deadline; Qt's XMLHttpRequest has no timeout
//     property (assigning one is silently ignored — checked on Qt 6.11);
//   - abort() is always deferred with Qt.callLater. Calling it from inside a
//     readystatechange callback while the body was still arriving crashed the
//     engine in testing; deferred, it is clean and the DONE callback reports
//     the outcome set beforehand.
// tests/fetch-harness.qml drives every one of these paths against a local
// server, offline.
Item {
  id: fetcher

  property int byteLimit: 65536
  property int deadlineMs: 15000
  readonly property bool busy: request !== null
  readonly property string busyKey: request !== null ? requestKey : ""

  property var request: null
  property string requestKey: ""
  property string requestUrl: ""
  property string outcome: ""
  property int requestsStarted: 0

  // finished carries the raw text; the caller validates and parses it.
  signal finished(string key, string text)
  signal failed(string key, string reason)

  // The only origin ever requested. tests/fetch-harness.qml points this at
  // a local server; nothing in the plugin sets it.
  property string allowedOrigin: "https://date.nager.at"
  readonly property var allowedUrl: new RegExp("^" + allowedOrigin.replace(/[.\/]/g, "\\$&") + "/api/v3/PublicHolidays/\\d{4}/[A-Z]{2}$")

  function fetch(key, url) {
    if (request !== null) return false
    if (!allowedUrl.test(String(url))) return false

    var xhr = new XMLHttpRequest()
    request = xhr
    requestKey = String(key)
    requestUrl = String(url)
    outcome = ""
    requestsStarted += 1

    xhr.onreadystatechange = function() {
      // A reply can land after the shell has reloaded the plugin and torn
      // this item down; the closure outlives it, the item's methods do not.
      if (typeof fetcher.settle !== "function" || fetcher.request !== xhr) return
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        if (fetcher.redirected(xhr)) fetcher.cancel(xhr, "redirect")
        var declared = Number(xhr.getResponseHeader("Content-Length"))
        if (declared > fetcher.byteLimit) fetcher.cancel(xhr, "oversize")
      } else if (xhr.readyState === XMLHttpRequest.LOADING) {
        if (fetcher.redirected(xhr)) fetcher.cancel(xhr, "redirect")
        else if (xhr.responseText.length > fetcher.byteLimit) fetcher.cancel(xhr, "oversize")
      } else if (xhr.readyState === XMLHttpRequest.DONE) {
        fetcher.settle(xhr)
      }
    }

    xhr.open("GET", String(url))
    xhr.send()
    deadline.restart()
    return true
  }

  // Qt follows redirects on its own and only reports where the response
  // came from, in responseURL, once the body starts arriving (empty while
  // the headers are being reported, on Qt 6.11). Anything that landed
  // somewhere other than the URL asked for is refused rather than read.
  function redirected(xhr) {
    var landed = String(xhr.responseURL || "")
    return landed !== "" && landed !== requestUrl
  }

  function cancel(xhr, reason) {
    if (outcome === "") outcome = reason
    Qt.callLater(function() {
      if (fetcher.request === xhr) xhr.abort()
    })
  }

  function settle(xhr) {
    var key = requestKey
    var reason = outcome
    deadline.stop()
    request = null
    requestKey = ""
    outcome = ""

    if (reason !== "") {
      failed(key, reason)
      return
    }
    if (redirected(xhr)) {
      failed(key, "redirect")
      return
    }
    if (xhr.status !== 200) {
      failed(key, "http-" + xhr.status)
      return
    }
    var text = xhr.responseText
    if (text.length > byteLimit) {
      failed(key, "oversize")
      return
    }
    finished(key, text)
  }

  Timer {
    id: deadline
    interval: fetcher.deadlineMs
    onTriggered: if (fetcher.request !== null) fetcher.cancel(fetcher.request, "timeout")
  }
}
