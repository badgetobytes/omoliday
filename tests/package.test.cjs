const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const H = require("../Holidays.js");
const C = require("../Countries.js");

const root = path.join(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

function trackedFiles() {
  try {
    return execFileSync("git", ["-C", root, "ls-files", "--cached", "--others", "--exclude-standard"], { encoding: "utf8" })
      .split("\n")
      .filter(Boolean);
  } catch (error) {
    const out = [];
    const walk = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === ".git") continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else out.push(path.relative(root, full));
      }
    };
    walk(root);
    return out;
  }
}

const RUNTIME = ["Panel.qml", "BarWidget.qml", "HolidayFetch.qml", "Holidays.js", "Countries.js", "Model.js"];

test("manifest is the shape the shell and the marketplace expect", () => {
  const manifest = JSON.parse(read("manifest.json"));
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.id, "fstander.omoliday");
  assert.equal(manifest.name, "Omoliday");
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/);
  assert.equal(manifest.license, "MIT");
  assert.ok(manifest.author.length > 0);
  assert.ok(manifest.description.length > 0 && manifest.description.length <= 200);
  assert.deepEqual(manifest.kinds, ["bar-widget"]);
  assert.equal(manifest.entryPoints.barWidget, "BarWidget.qml");
  for (const entry of Object.values(manifest.entryPoints)) {
    assert.ok(!entry.startsWith("/") && !entry.includes(".."), entry);
    assert.ok(fs.existsSync(path.join(root, entry)), entry);
  }
  assert.equal(manifest.omarchy.clonedFrom, "omarchy.clock");
  assert.equal(manifest.barWidget.allowMultiple, false);
  assert.equal(manifest.barWidget.defaultSection, "center");
  assert.deepEqual(manifest.barWidget.schema.map((s) => s.key), ["country", "region"]);
});

test("the plugin id in the QML matches the manifest, and the stock id is gone", () => {
  const id = JSON.parse(read("manifest.json")).id;
  assert.ok(read("BarWidget.qml").includes(`moduleName: "${id}"`));
  assert.ok(read("BarWidget.qml").includes(`target: "${id}"`));
  assert.ok(read("Panel.qml").includes(`moduleName: "${id}"`));
  assert.ok(read("Panel.qml").includes(`ipcTarget: "${id}"`));
  for (const file of ["Panel.qml", "BarWidget.qml"]) assert.ok(!read(file).includes('"omarchy.clock"'), file);
});

test("the tree carries nothing the marketplace refuses", () => {
  const files = trackedFiles();
  for (const file of files) {
    assert.doesNotMatch(path.basename(file).toLowerCase(), /install|setup|uninstall/, file);
    assert.doesNotMatch(path.basename(file), /^(AGENTS|CLAUDE|SKILL)\.md$/i, file);
    assert.ok(!fs.lstatSync(path.join(root, file)).isSymbolicLink(), `${file} is a symlink`);
    assert.doesNotMatch(file, /__pycache__|\.pyc$|\.log$|\.bak$/, file);
  }
  for (const required of ["README.md", "LICENSE", "manifest.json", "preview.png"]) assert.ok(files.includes(required), required);
});

test("runtime files start no processes, open no files and ask for one stock command only", () => {
  const forbidden = [/\bProcess\s*\{/, /\bFileView\b/, /openUrlExternally/, /hyprctl/, /execDetached/, /Qt\.include\(/, /\bsudo\b/, /pkexec/];
  for (const file of RUNTIME) {
    const source = read(file);
    for (const pattern of forbidden) assert.doesNotMatch(source, pattern, `${file} matches ${pattern}`);
  }
  assert.ok(!read("Panel.qml").includes("Quickshell.Io"), "the panel needs no IO module");
  // The stock clock's middle-click timezone picker, verbatim, and nothing else.
  const runs = RUNTIME.flatMap((file) => (read(file).match(/\.run\([^)]*\)/g) || []).map((call) => `${file}: ${call}`));
  assert.deepEqual(runs, ['BarWidget.qml: .run("omarchy-menu-timezone")']);
  const stock = fs.existsSync("/usr/share/omarchy/shell/plugins/panels/clock/BarWidget.qml")
    ? fs.readFileSync("/usr/share/omarchy/shell/plugins/panels/clock/BarWidget.qml", "utf8")
    : "";
  if (stock) assert.ok(stock.includes('root.bar.run("omarchy-menu-timezone")'), "the stock clock still makes the same call");
});

test("network is confined to HolidayFetch, with its guards in place", () => {
  const fetch = read("HolidayFetch.qml");
  assert.match(fetch, /property string allowedOrigin: "https:\/\/date\.nager\.at"/);
  assert.match(fetch, /getResponseHeader\("Content-Length"\)/);
  assert.match(fetch, /XMLHttpRequest\.LOADING/);
  assert.match(fetch, /xhr\.responseURL/);
  assert.match(fetch, /Qt\.callLater\(function\(\) \{\s*if \(fetcher\.request === xhr\) xhr\.abort\(\)/);
  assert.match(fetch, /Timer \{\s*id: deadline/);
  assert.match(fetch, /if \(request !== null\) return false/);
  for (const file of RUNTIME.filter((f) => f !== "HolidayFetch.qml")) assert.doesNotMatch(read(file), /XMLHttpRequest|\bxhr\b/, file);
  // The fetcher's rule, evaluated exactly as written, accepts every URL the
  // model builds and nothing else.
  const expression = /readonly property var allowedUrl: (new RegExp\(.*\))\s*$/m.exec(fetch);
  assert.ok(expression, "allowedUrl expression found");
  const rule = new Function("allowedOrigin", "return " + expression[1])("https://date.nager.at");
  for (const [code] of C.COUNTRIES) assert.match(H.holidayUrl(code, 2026), rule);
  for (const bad of [
    "https://date.nager.at/api/v3/PublicHolidays/2026/ZA/",
    "http://date.nager.at/api/v3/PublicHolidays/2026/ZA",
    "https://date.nager.at.example/api/v3/PublicHolidays/2026/ZA",
    "https://date-nager.at/api/v3/PublicHolidays/2026/ZA",
    "https://date.nager.at/api/v3/PublicHolidays/2026/za",
    "https://date.nager.at/api/v3/PublicHolidays/2026/ZA?x=1",
    "https://date.nager.at/api/v3/AvailableCountries",
    "",
  ])
    assert.doesNotMatch(bad, rule, bad);
});

test("holiday names reach the screen only through plain-text sinks", () => {
  const panel = read("Panel.qml");
  assert.doesNotMatch(panel, /Text\.RichText|Text\.AutoText|Text\.StyledText|Text\.MarkdownText/);
  assert.match(panel, /PanelToolTip \{\s*visible: holidayHover\.containsMouse && dayCell\.marked\s*text: dayCell\.holiday/);
  assert.match(panel, /Text \{\s*textFormat: Text\.PlainText\s*anchors\.centerIn: parent\s*text: dayCell\.modelData\.day/);
  // Every Text item in the panel either declares PlainText or shows one of
  // the panel's own literal strings.
  const textBlocks = panel.split(/\n\s*Text \{/).slice(1);
  assert.ok(textBlocks.length >= 10, `found ${textBlocks.length} Text items`);
  for (const block of textBlocks) {
    const head = block.split("\n").slice(0, 12).join("\n");
    assert.match(head, /textFormat: Text\.PlainText|\n\s*text: "/, head);
  }
});

test("the grid reads holidays through the published map, never a mutated object", () => {
  const panel = read("Panel.qml");
  assert.match(panel, /readonly property var holidays: Holidays\.holidayMap\(holidayCache, country, region, gridYears\)/);
  assert.match(panel, /root\.holidayName\(root\.holidays, modelData\.key\)/);
  assert.doesNotMatch(panel, /holidayCache\.years\[[^\]]+\]\s*=/);
  assert.doesNotMatch(panel, /holidays\[[^\]]+\]\s*=/);
});

test("README documents install, removal, the source, the country setting and the records", () => {
  const readme = read("README.md");
  for (const needle of [
    "omarchy plugin add https://github.com/badgetobytes/omoliday.git --enable",
    "omarchy plugin remove fstander.omoliday",
    "Nager.Date",
    "records",
    "country",
    "MIT",
  ])
    assert.ok(readme.includes(needle), needle);
  for (const line of readme.split("\n")) assert.doesNotMatch(line, /sudo|pkexec|curl \||bash -c|systemctl|yay |pacman /, line);
});

test("Countries.js reproduces from the committed snapshot", () => {
  const generated = execFileSync("node", [path.join(root, "scripts/generate-countries.mjs"), path.join(root, "tests/fixture-countries.json")], { encoding: "utf8" });
  assert.equal(generated, read("Countries.js"));
});
