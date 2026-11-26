.pragma library

// Pure helpers shared by the service, bar widget, and popup.

var PLUGIN_ID = "io.mcmurray.freenet-explorer";
var SETUP_PATH = "~/.config/omarchy/plugins/io.mcmurray.freenet-explorer/bin/setup";
var UI_URL = "http://127.0.0.1:8787/";
var SUMMARY_URL = "http://127.0.0.1:8787/api/summary";
var PEER_UI_URL = "http://127.0.0.1:7509/";
// Contract ids are whatever this node lists. Nothing else may be opened.
var CONTRACT_PATH = /^\/v1\/contract\/web\/[1-9A-HJ-NP-Za-km-z]{8,128}\/$/;

// hosted: integer >= 0 when known, -1 when unknown
function statusLine(nodeUp, explorerUp, hosted) {
  var count = (explorerUp && hosted >= 0) ? String(hosted) : "unknown";
  return "node=" + (nodeUp ? "up" : "down")
    + " explorer=" + (explorerUp ? "running" : "stopped")
    + " hosted=" + count;
}

function tooltipText(nodeUp, explorerUp, hosted) {
  if (!nodeUp)
    return "Freenet · node down";
  if (!explorerUp)
    return "Freenet · node up, explorer stopped";
  if (hosted >= 0)
    return "Freenet · " + hosted + " hosted";
  return "Freenet · explorer running";
}

function glyphState(nodeUp, explorerUp) {
  if (!nodeUp)
    return "down";
  return explorerUp ? "running" : "nodeOnly";
}

function parseHosted(text) {
  var data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return -1;
  }
  if (data === null || typeof data !== "object" || Array.isArray(data))
    return -1;
  var node = data.node;
  if (node === null || typeof node !== "object" || Array.isArray(node))
    return -1;
  var hosted = node.hosted;
  if (typeof hosted !== "number" || !isFinite(hosted) || hosted < 0 || Math.floor(hosted) !== hosted)
    return -1;
  return hosted;
}

function oneLine(s) {
  var line = String(s === undefined || s === null ? "" : s).replace(/[\r\n]+/g, " ").trim();
  return line.length > 200 ? line.slice(0, 197) + "..." : line;
}

function clip(text) {
  var body = String(text === undefined || text === null ? "" : text);
  return body.length > 262144 ? body.slice(0, 262144) : body;
}

// -1 when the dashboard did not say. 0 means up but not connected.
function parsePeerCount(text) {
  var match = /Connected to (\d+) peers?\b/.exec(clip(text));
  if (!match)
    return -1;
  var n = parseInt(match[1], 10);
  if (!isFinite(n) || n < 0 || String(n) !== match[1])
    return -1;
  return n;
}

function cleanLabel(raw) {
  var label = String(raw)
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .trim();
  if (!label || label.length > 80 || /[<>&\x00-\x1f]/.test(label))
    return "";
  return label;
}

// Names and paths from the dashboard's Freenet Links list. Other hrefs,
// including ones later on the page, are ignored.
function parsePlaces(text) {
  var body = clip(text);
  var start = body.indexOf("<h2>Freenet Links</h2>");
  if (start < 0)
    return [];
  var ul = body.indexOf("<ul", start);
  if (ul < 0)
    return [];
  var end = body.indexOf("</ul>", ul);
  if (end < 0)
    return [];
  var block = body.slice(ul, end);
  var re = /<a\s+href="(\/v1\/contract\/web\/[1-9A-HJ-NP-Za-km-z]{8,128}\/)"[^>]*>([^<]{1,80})<\/a>/g;
  var out = [];
  var seen = {};
  var match;
  while ((match = re.exec(block)) !== null) {
    if (out.length >= 12)
      break;
    var path = match[1];
    if (seen[path] || !CONTRACT_PATH.test(path))
      continue;
    var label = cleanLabel(match[2]);
    if (!label)
      continue;
    var after = block.slice(match.index + match[0].length, match.index + match[0].length + 360);
    var note = /<p class="note">([\s\S]{0,240}?)<\/p>/.exec(after);
    var detail = note ? plainFact(note[1], 90) : "";
    seen[path] = true;
    out.push({ label: label, path: path, detail: detail });
  }
  return out;
}

function placeUrl(path) {
  if (typeof path !== "string" || !CONTRACT_PATH.test(path))
    return "";
  return "http://127.0.0.1:7509" + path;
}

// The app page itself, still on this contract. The shell wrapper's icon is
// the generic Freenet mark, so the icon is read from the sandboxed page.
function sandboxPageUrl(path) {
  if (typeof path !== "string" || !CONTRACT_PATH.test(path))
    return "";
  return "http://127.0.0.1:7509" + path + "?__sandbox=1";
}

// An image published by this contract. No other host, query, or parent path.
function contractIconUrl(pagePath, href) {
  if (typeof pagePath !== "string" || !CONTRACT_PATH.test(pagePath))
    return "";
  if (typeof href !== "string")
    return "";
  var raw = href.trim();
  if (!raw || /[\s?#\\]/.test(raw) || /^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.indexOf("//") === 0 || raw.charAt(0) === ".")
    return "";
  var path = raw.charAt(0) === "/" ? raw : pagePath + raw;
  if (path.indexOf(pagePath) !== 0 || path.indexOf("..") >= 0 || path.indexOf("//") >= 0)
    return "";
  if (path.length > 200 || !/\.(svg|png|webp|ico)$/i.test(path))
    return "";
  if (!/^\/v1\/contract\/web\/[1-9A-HJ-NP-Za-km-z]{8,128}\/[A-Za-z0-9._/-]+$/.test(path))
    return "";
  return "http://127.0.0.1:7509" + path;
}

function localIconUrl(url) {
  if (typeof url !== "string" || url.indexOf("http://127.0.0.1:7509/") !== 0)
    return "";
  var path = url.slice("http://127.0.0.1:7509".length);
  var match = /^(\/v1\/contract\/web\/[1-9A-HJ-NP-Za-km-z]{8,128}\/)/.exec(path);
  if (!match)
    return "";
  return contractIconUrl(match[1], path) === url ? url : "";
}

// First same-contract icon link on the app page. Anything else is ignored.
function iconUrlFromPage(html, pagePath) {
  if (typeof html !== "string" || typeof pagePath !== "string" || !CONTRACT_PATH.test(pagePath))
    return "";
  var re = /<link\b[^>]*>/gi;
  var match;
  while ((match = re.exec(html)) !== null) {
    var tag = match[0];
    var rel = /\brel\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i.exec(tag);
    var relVal = rel ? (rel[1] || rel[2] || rel[3] || "") : "";
    if (relVal.toLowerCase().indexOf("icon") < 0)
      continue;
    var href = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i.exec(tag);
    if (!href)
      continue;
    var url = contractIconUrl(pagePath, href[1] || href[2] || href[3] || "");
    if (url)
      return url;
  }
  return "";
}

// Aegis runs in Freenet mode only when this peer serves the page. A public
// https host is refused by the peer (403) and the app then stays a browser vault.
// `text` is one local path, or the same path as a 127.0.0.1:7509 URL.
function aegisContractPath(text) {
  var line = String(text || "").replace(/^\uFEFF/, "").trim();
  var nl = line.indexOf("\n");
  if (nl >= 0)
    line = line.slice(0, nl).trim();
  var prefix = "http://127.0.0.1:7509";
  if (line.indexOf(prefix) === 0)
    line = line.slice(prefix.length);
  if (line.indexOf("?") >= 0 || line.indexOf("#") >= 0 || line.indexOf(" ") >= 0 || line.indexOf("@") >= 0)
    return "";
  if (line.length > 1 && line.charAt(line.length - 1) !== "/")
    line += "/";
  if (!CONTRACT_PATH.test(line))
    return "";
  return line;
}

function aegisLaunchUrl(path) {
  var clean = aegisContractPath(path);
  return clean ? ("http://127.0.0.1:7509" + clean) : "";
}

function appMark(label) {
  var name = String(label || "").toLowerCase();
  if (name.indexOf("aegis") >= 0)
    return "aegis";
  if (name.indexOf("atlas") >= 0)
    return "atlas";
  if (name.indexOf("river") >= 0)
    return "river";
  if (name.indexOf("mail") >= 0)
    return "mail";
  if (name.indexOf("delta") >= 0)
    return "delta";
  if (name.indexOf("ghost") >= 0)
    return "ghost";
  if (name.indexOf("freenet.org") >= 0)
    return "freenet";
  return "";
}

function monogram(label) {
  var name = String(label || "").trim();
  if (!name)
    return "";
  var ch = name.charAt(0).toUpperCase();
  return /^[A-Z0-9]$/.test(ch) ? ch : "";
}

function parseSummary(text) {
  var hosted = parseHosted(text);
  var kept = -1;
  var total = -1;
  try {
    var data = JSON.parse(text);
    if (data && typeof data === "object" && !Array.isArray(data)) {
      if (data.kept && typeof data.kept === "object") kept = countOf(data.kept.n);
      if (data.total && typeof data.total === "object") total = countOf(data.total.n);
    }
  } catch (e) {
    kept = -1;
    total = -1;
  }
  return { hosted: hosted, kept: kept, total: total };
}

function countOf(value) {
  if (typeof value !== "number" || !isFinite(value) || value < 0 || Math.floor(value) !== value)
    return -1;
  return value;
}

// The dashboard's own count when it parses. The parsed list is capped, so a
// label must not pretend the cap is the total. Junk falls back to the list.
function listedCount(metric, parsed) {
  var shown = (typeof parsed === "number" && isFinite(parsed) && parsed >= 0) ? Math.floor(parsed) : 0;
  var text = String(metric === undefined || metric === null ? "" : metric).trim();
  if (!/^[0-9]{1,6}$/.test(text))
    return shown;
  var n = parseInt(text, 10);
  return n > shown ? n : shown;
}

// A fact drawn from the dashboard. Rejects markup. Truncates instead of dropping.
function plainFact(raw, max) {
  var label = String(raw === undefined || raw === null ? "" : raw)
    .replace(/<[^>]*>/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ")
    .replace(/\s+([.,;:])/g, "$1")
    .trim();
  if (!label || /[<>&\x00-\x1f]/.test(label))
    return "";
  var limit = max > 0 ? max : 80;
  if (label.length > limit)
    label = label.slice(0, limit - 3) + "...";
  return label;
}

function peerAddrOk(addr) {
  var match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}):(\d{1,5})$/.exec(addr);
  if (!match)
    return false;
  var i;
  for (i = 1; i <= 4; i++) {
    var octet = parseInt(match[i], 10);
    if (String(octet) !== match[i] || octet > 255)
      return false;
  }
  var port = parseInt(match[5], 10);
  return String(port) === match[5] && port >= 1 && port <= 65535;
}

function contractKeyOk(key) {
  return typeof key === "string" && /^[1-9A-HJ-NP-Za-km-z]{20,128}$/.test(key);
}

function peerPageUrl(addr) {
  if (!peerAddrOk(addr))
    return "";
  return "http://127.0.0.1:7509/peer/" + addr;
}

function contractPageUrl(key) {
  if (!contractKeyOk(key))
    return "";
  return "http://127.0.0.1:7509/contract/" + key;
}

// Clipboard text we are willing to place there: one token, no markup, no spaces.
function copyable(value) {
  var line = String(value === undefined || value === null ? "" : value);
  if (line.length < 1 || line.length > 180)
    return "";
  if (!/^[A-Za-z0-9:./_-]+$/.test(line))
    return "";
  return line;
}

function matchFact(body, re, max) {
  var match = re.exec(body);
  return match ? plainFact(match[1], max || 40) : "";
}

function sliceTable(body, id) {
  var at = body.indexOf('data-table-id="' + id + '"');
  if (at < 0)
    return "";
  var start = body.indexOf("<tbody>", at);
  if (start < 0)
    return "";
  var end = body.indexOf("</tbody>", start);
  if (end < 0)
    return "";
  return body.slice(start, end);
}

function parsePeers(text) {
  var block = sliceTable(clip(text), "peers");
  if (!block)
    return [];
  var re = /data-sort="(\d{1,3}(?:\.\d{1,3}){3}:\d{1,5})"[\s\S]{0,160}?<\/td>\s*<td[^>]*>\s*([^<]{1,16})\s*<\/td>\s*<td[^>]*>\s*([^<]{1,24})\s*<\/td>\s*<td[^>]*>\s*([^<]{1,24})\s*<\/td>\s*<td[^>]*>\s*([^<]{1,24})\s*<\/td>\s*<td[^>]*>\s*([^<]{1,24})\s*<\/td>/g;
  var out = [];
  var seen = {};
  var match;
  while ((match = re.exec(block)) !== null) {
    if (out.length >= 48)
      break;
    var addr = match[1];
    if (seen[addr] || !peerAddrOk(addr))
      continue;
    seen[addr] = true;
    out.push({
      addr: addr,
      loc: plainFact(match[2], 12),
      sent: plainFact(match[4], 16),
      recv: plainFact(match[5], 16),
      age: plainFact(match[6], 16)
    });
  }
  return out;
}

function parseContracts(text) {
  var block = sliceTable(clip(text), "hosting");
  if (!block)
    return [];
  // Badge tooltips on a row run past 600 characters. Stay inside one row.
  var re = /<td title="([1-9A-HJ-NP-Za-km-z]{20,128})"[\s\S]{0,1600}?<\/tr>/g;
  var out = [];
  var seen = {};
  var match;
  while ((match = re.exec(block)) !== null) {
    if (out.length >= 12)
      break;
    var key = match[1];
    if (seen[key] || !contractKeyOk(key))
      continue;
    var row = match[0];
    var sizeMatch = /(\d+(?:\.\d+)? (?:B|KB|MB|GB))/.exec(row);
    var state = [];
    if (row.indexOf(">in use<") >= 0)
      state.push("in use");
    if (row.indexOf(">fresh<") >= 0)
      state.push("fresh");
    if (row.indexOf(">next to evict<") >= 0)
      state.push("next to evict");
    seen[key] = true;
    out.push({
      key: key,
      short: key.slice(0, 8) + "...",
      size: sizeMatch ? plainFact(sizeMatch[1], 16) : "",
      state: state.join(", ")
    });
  }
  return out;
}

function parseDashboard(text) {
  var body = clip(text);
  var stateRaw = matchFact(body, /Closest limit: <strong>[^<]{1,40}<\/strong>\s*(?:\u2014|&mdash;|-)\s*([^<]{1,80})/, 80);
  var pct = -1;
  var pctMatch = /\((\d{1,3})%\)/.exec(stateRaw);
  if (pctMatch) {
    var n = parseInt(pctMatch[1], 10);
    if (String(n) === pctMatch[1] && n <= 100)
      pct = n;
  }
  var external = "";
  var addr = matchFact(body, /External address: <code>(\d{1,3}(?:\.\d{1,3}){3})<\/code>/, 20);
  var udp = matchFact(body, /UDP port: <code>(\d{1,5})<\/code>/, 6);
  if (peerAddrOk(addr + ":" + (udp || "1"))) {
    var port = parseInt(udp, 10);
    external = addr + (port >= 1 && port <= 65535 && String(port) === udp ? ":" + udp : "");
  }
  return {
    peerCount: parsePeerCount(body),
    version: matchFact(body, /data-version="(\d+\.\d+\.\d+)"/, 16),
    uptime: matchFact(body, /<span class="uptime">([^<]{1,24})<\/span>/, 24),
    peerId: matchFact(body, /id="peer-id"[^>]{0,80}>([1-9A-HJ-NP-Za-km-z]{6,64})</, 64),
    location: matchFact(body, /Your location: ([0-9]+\.[0-9]{1,6})/, 12),
    upload: matchFact(body, /Upload <b>([^<]{1,16})<\/b>/, 16),
    download: matchFact(body, /Download <b>([^<]{1,16})<\/b>/, 16),
    uploaded: matchFact(body, /<span class="transfer-label">Uploaded<\/span>\s*<span class="transfer-value">([^<]{1,24})/, 24),
    downloaded: matchFact(body, /<span class="transfer-label">Downloaded<\/span>\s*<span class="transfer-value">([^<]{1,24})/, 24),
    nat: matchFact(body, /NAT hole punching: (\d+\/\d+) successful/, 16),
    external: external,
    ringPeers: matchFact(body, /<span class="metric-value">([^<]{1,24})<\/span>\s*<span class="metric-label">Ring peers<\/span>/, 24),
    hosted: matchFact(body, /<span class="metric-value">([^<]{1,24})<\/span>\s*<span class="metric-label">Hosted contracts<\/span>/, 24),
    attempts: matchFact(body, /<span class="metric-value">([^<]{1,24})<\/span>\s*<span class="metric-label">Conn attempts<\/span>/, 24),
    state: stateRaw,
    statePct: pct,
    places: parsePlaces(body),
    peers: parsePeers(body),
    contracts: parseContracts(body)
  };
}
