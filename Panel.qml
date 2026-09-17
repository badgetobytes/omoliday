import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Holidays.js" as Holidays
import "Countries.js" as Countries

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today and the public
// holidays are the only marked days, and the only thing that moves is
// which month is on screen — chevrons, the scroll wheel, and the arrow
// keys all step it.
//
// This is the stock Omarchy clock panel with one addition: public holidays
// for one country, fetched from Nager.Date a year at a time, cached on the
// widget's own shell.json entry, and drawn as a dot under the day with the
// holiday's name on hover. The stock code is left as it was wherever the
// holidays did not need it changed.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "fstander.omoliday"
  ipcTarget: "fstander.omoliday"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // ---- Public holidays. One country, from the widget's `country` setting
  //      or else the system locale ("off" switches the whole feature off);
  //      an optional `region` such as DE-BY adds that subdivision's days.
  //      The years on the visible grid are fetched one request at a time
  //      through HolidayFetch, kept as a `records` object on this widget's
  //      own shell.json entry, and looked up by date key when the grid
  //      paints. The cache object is replaced, never mutated, so the grid's
  //      bindings re-evaluate.
  readonly property string country: Holidays.resolveCountry(setting("country", ""), Qt.locale().name, Countries.isSupported)
  readonly property string region: Holidays.normalizeRegion(setting("region", ""), country)
  readonly property string countryName: Countries.name(country)
  readonly property bool holidaysOff: Holidays.isOff(setting("country", ""))

  // The rail under the grid names the country and is the way to change it:
  // clicking it (or pressing C) swaps the name for a field that takes a
  // country code or the start of a name and shows the match beside it.
  // Enter keeps the match, Escape drops the edit.
  property bool editingCountry: false
  property string countryDraft: ""
  readonly property var countryMatch: Holidays.matchCountry(countryDraft, Countries.COUNTRIES)
  readonly property string countryLabel: holidaysOff ? "Off"
    : country === "" ? "Not set"
    : holidayStatus === "error" ? countryName + " · unavailable"
    : countryName
  readonly property string countryTooltip: holidaysOff
    ? "Holidays are off · click to choose a country"
    : country === "" ? "No country yet · click to choose one"
    : "Public holidays for " + countryName + (region !== "" ? " (" + region + ")" : "") + " from " + Holidays.SOURCE_NAME + " · click to change"
  readonly property string countryMatchLabel: countryMatch.empty ? "locale default"
    : countryMatch.off ? "no holidays"
    : countryMatch.code !== "" ? countryMatch.name + " (" + countryMatch.code + ")"
    : "no match"

  function startEditingCountry() {
    if (root.editingLife) root.cancelEditingLife()
    root.editingCountry = true
    Qt.callLater(function() {
      countryField.text = root.holidaysOff ? "off" : root.country
      countryField.selectAll()
      countryField.forceActiveFocus()
    })
  }

  function cancelEditingCountry() {
    root.editingCountry = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Only a resolved match is kept; an unmatched draft stays up to be fixed.
  function commitCountry() {
    var match = root.countryMatch
    var value = match.empty ? "" : match.off ? "off" : match.code
    if (value === "" && !match.empty) return
    if (value !== String(setting("country", ""))) persistSettings({ country: value })
    cancelEditingCountry()
  }

  function handleCountryKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingCountry()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitCountry()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      event.accepted = true
    }
  }
  property var holidayCache: Holidays.emptyCache()
  property var holidayFailures: ({})
  property string holidayStatus: "idle"
  property string holidayError: ""
  readonly property var gridYears: Holidays.yearsInGrid(weeks)
  readonly property var holidays: Holidays.holidayMap(holidayCache, country, region, gridYears)
  readonly property color holidayColor: Style.selectedStateColor(contentForeground, Color.accent)

  function holidayName(map, key) {
    var value = map ? map[key] : undefined
    return typeof value === "string" ? value : ""
  }

  function loadHolidayCache() {
    root.holidayCache = Holidays.readCache(setting("records", null))
  }

  // Ask for the first year on screen that is missing, stale, and not in a
  // failure's backoff window. One request at a time; the next one starts
  // when this one settles. Nothing is asked before the host widget has
  // handed over its settings: until then the country would be the locale's
  // guess rather than the configured one.
  function ensureHolidays() {
    if (root.hostWidget === null) return
    if (root.country === "") {
      root.holidayStatus = "off"
      return
    }
    var pending = Holidays.pendingKeys(root.holidayCache, root.country, root.region, root.gridYears, root.todayKey,
                                       fetcher.busyKey, root.holidayFailures, Date.now())
    scheduleHolidayRetry()
    if (pending.length === 0) {
      if (!fetcher.busy) root.holidayStatus = "ready"
      return
    }
    if (!leadsFetching()) {
      root.holidayStatus = "waiting"
      return
    }
    if (fetcher.busy) return
    var key = pending[0]
    var url = Holidays.holidayUrl(Holidays.countryOfKey(key), Holidays.keyYear(key))
    if (url === "" || !fetcher.fetch(key, url)) return
    root.holidayStatus = "fetching"
    console.info("Omoliday: fetching holidays for " + key)
  }

  // One fetcher per shell. The bar mounts this widget once per monitor, and
  // every instance reads the same records back from shell.json, so only the
  // instance the host lists first asks the source; the others show what it
  // saves. Decided at each request rather than bound, so a monitor coming or
  // going is seen the next time a year is needed.
  function leadsFetching() {
    if (root.hostWidget === null || !root.bar || typeof root.bar.moduleWidgets !== "function") return true
    var peers = root.bar.moduleWidgets(root.moduleName)
    if (!peers || peers.length === 0) return true
    return peers[0] === root.hostWidget
  }

  function noteHolidayFailure(key, reason) {
    var failures = {}
    for (var existing in root.holidayFailures) failures[existing] = root.holidayFailures[existing]
    var count = failures[key] ? Number(failures[key].count) + 1 : 1
    failures[key] = { count: count, until: Date.now() + Holidays.backoffMs(count) }
    root.holidayFailures = failures
    root.holidayError = key + ": " + reason
    root.holidayStatus = "error"
    console.warn("Omoliday: holidays for " + key + " not fetched (" + reason + ")")
    ensureHolidays()
  }

  function scheduleHolidayRetry() {
    var at = Holidays.nextRetryAt(root.holidayFailures, Date.now())
    if (at === 0) {
      holidayRetry.stop()
      return
    }
    holidayRetry.interval = Math.max(1000, at - Date.now())
    holidayRetry.restart()
  }

  function persistHolidayCache() {
    var payload = Holidays.recordsPayload(root.holidayCache)
    if (!Holidays.fitsRecordLimit(payload)) {
      console.warn("Omoliday: holiday cache too large to save")
      return
    }
    persistSettings({ records: payload })
  }

  function refetchHolidays() {
    root.holidayCache = Holidays.emptyCache()
    root.holidayFailures = {}
    root.holidayError = ""
    ensureHolidays()
  }

  function holidayDiagnostics() {
    var years = {}
    for (var key in root.holidayCache.years)
      years[key] = { at: root.holidayCache.years[key].at, count: root.holidayCache.years[key].days.length }
    var mapped = 0
    for (var date in root.holidays) mapped += 1
    return JSON.stringify({
      country: root.country,
      countryName: root.countryName,
      region: root.region,
      countrySetting: String(setting("country", "")),
      locale: Qt.locale().name,
      status: root.holidayStatus,
      error: root.holidayError,
      leader: leadsFetching(),
      busy: fetcher.busy,
      busyKey: fetcher.busyKey,
      requestsStarted: fetcher.requestsStarted,
      viewing: Qt.formatDate(root.viewDate, "yyyy-MM"),
      gridYears: root.gridYears,
      mapped: mapped,
      years: years,
      failures: root.holidayFailures,
      recordsBytes: Holidays.recordsSize(Holidays.recordsPayload(root.holidayCache)),
      recordsPersistent: Object.keys(root.settings || {}).length > 0
    })
  }

  // Deferred, not immediate: the bar hands a freshly loaded widget its bar,
  // settings and identity in more than one pass, and this panel is already
  // alive for the first of them. A short settle timer, restarted on every
  // change, means the first request is for the configured country rather
  // than the locale's guess made from an empty settings object.
  function scheduleEnsureHolidays() {
    ensureSettle.restart()
  }

  Timer {
    id: ensureSettle
    interval: 400
    repeat: false
    onTriggered: root.ensureHolidays()
  }

  onSettingsChanged: {
    loadHolidayCache()
    scheduleEnsureHolidays()
  }
  onHostWidgetChanged: scheduleEnsureHolidays()
  onGridYearsChanged: scheduleEnsureHolidays()
  onCountryChanged: scheduleEnsureHolidays()
  onRegionChanged: scheduleEnsureHolidays()

  HolidayFetch {
    id: fetcher
    byteLimit: Holidays.BYTE_LIMIT
    onFinished: function(key, text) {
      var parsed = Holidays.parseHolidays(text, Holidays.keyYear(key), root.region)
      if (!parsed.ok) {
        root.noteHolidayFailure(key, parsed.reason)
        return
      }
      var failures = {}
      for (var existing in root.holidayFailures) if (existing !== key) failures[existing] = root.holidayFailures[existing]
      root.holidayFailures = failures
      root.holidayError = ""
      root.holidayCache = Holidays.withYear(root.holidayCache, key, parsed.days, root.todayKey,
                                            Holidays.gridKeys(root.country, root.region, root.gridYears))
      root.persistHolidayCache()
      root.ensureHolidays()
    }
    onFailed: function(key, reason) { root.noteHolidayFailure(key, reason) }
  }

  Timer {
    id: holidayRetry
    repeat: false
    onTriggered: root.ensureHolidays()
  }


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    if (root.editingCountry) root.cancelEditingCountry()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
    ensureHolidays()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife || root.editingCountry
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "c" || t === "C") root.startEditingCountry()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData

                      // The holiday on this day, or "" — looked up through
                      // the published map so a new fetch repaints the grid.
                      readonly property string holiday: root.holidayName(root.holidays, modelData.key)
                      readonly property bool marked: holiday !== ""

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. A holiday under the pointer
                      // gets the same quiet fill every hovered control has.
                      color: holidayHover.containsMouse
                        ? Style.hoverFillFor(root.contentForeground, Color.accent)
                        : "transparent"
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: dayCell.modelData.day
                        // A holiday takes the selected colour, a weekend's
                        // dimming included: it is a day off either way.
                        color: dayCell.marked && dayCell.modelData.inMonth
                          ? root.holidayColor
                          : dayCell.modelData.inMonth
                            ? (dayCell.modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                            : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: dayCell.modelData.today
                      }

                      // The mark itself: a dot under the number, dimmed on
                      // the neighbouring months' days like the numbers are.
                      Rectangle {
                        visible: dayCell.marked
                        width: Style.space(4)
                        height: width
                        radius: Style.cornerRadius > 0 ? width / 2 : 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(3)
                        color: root.holidayColor
                        opacity: dayCell.modelData.inMonth ? 1 : 0.4
                      }

                      // Hover for the name. No buttons accepted, so clicks
                      // and the wheel keep reaching the grid's handlers.
                      MouseArea {
                        id: holidayHover
                        anchors.fill: parent
                        hoverEnabled: dayCell.marked
                        acceptedButtons: Qt.NoButton

                        PanelToolTip {
                          visible: holidayHover.containsMouse && dayCell.marked
                          text: dayCell.holiday
                          fontFamily: root.contentFontFamily
                        }
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Holidays rail: whose public holidays the grid marks, laid
          //      out like the year rail above — a small-caps label at the
          //      grid's left edge, the value at its right. The value is the
          //      country picker: click it or press C, type a code or the
          //      start of a name, and the match shows beside the field.
          Item {
            width: parent.width
            height: holidayRail.height

            Item {
              id: holidayRail
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(holidayLabel.implicitHeight, countryField.implicitHeight, Style.space(10))

              Text {
                id: holidayLabel
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.editingCountry ? "COUNTRY" : "HOLIDAYS"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                textFormat: Text.PlainText
                visible: !root.editingCountry
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.countryLabel
                color: countryMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: countryMouse
                anchors.fill: parent
                enabled: !root.editingCountry
                hoverEnabled: enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startEditingCountry()

                PanelToolTip {
                  visible: countryMouse.containsMouse
                  text: root.countryTooltip
                  fontFamily: root.contentFontFamily
                }
              }

              Row {
                visible: root.editingCountry
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.countryMatchLabel
                  color: root.countryMatch.code !== "" || root.countryMatch.off || root.countryMatch.empty
                    ? root.contentForeground
                    : Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                TextField {
                  id: countryField
                  width: Style.space(150)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "code or name"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  onTextChanged: root.countryDraft = text

                  Keys.onPressed: function(event) { root.handleCountryKey(event) }
                }
              }
            }
          }
        }
      }
    }
  }
}
