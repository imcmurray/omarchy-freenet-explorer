.pragma library

// Pure helpers shared by the service, bar widget, and popup.

var PLUGIN_ID = "io.mcmurray.freenet-explorer";
var SETUP_PATH = "~/.config/omarchy/plugins/io.mcmurray.freenet-explorer/bin/setup";
var UI_URL = "http://127.0.0.1:8787/";
var SUMMARY_URL = "http://127.0.0.1:8787/api/summary";

// hosted: integer >= 0 when known, -1 when unknown
function statusLine(nodeUp, explorerUp, hosted) {
  var count = (explorerUp && hosted >= 0) ? String(hosted) : "unknown";
  return "node=" + (nodeUp ? "up" : "down")
    + " explorer=" + (explorerUp ? "running" : "stopped")
    + " hosted=" + count;
}

function tooltipText(nodeUp, explorerUp, hosted) {
  if (!nodeUp)
    return "Freenet Explorer · node down";
  if (!explorerUp)
    return "Freenet Explorer · node up, explorer stopped";
  if (hosted >= 0)
    return "Freenet Explorer · " + hosted + " hosted";
  return "Freenet Explorer · explorer running";
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
