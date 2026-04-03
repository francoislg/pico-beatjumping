// Replay enhancement layer for Beat Jumping
// Progressive enhancement: PICO-8 game works without this.
// This adds: URL→GPIO replay injection + Share/QR after run completion.

(function () {
  "use strict";

  var CURRENT_VERSION = 1;

  // --- URL → GPIO: inject replay data before cart boots ---
  var params = new URLSearchParams(location.search);
  var replayData = params.get("r");
  if (replayData) {
    try {
      var bin = atob(replayData.replace(/-/g, "+").replace(/_/g, "/"));
      var replayVersion = bin.charCodeAt(0);

      // redirect to archived version if replay is from an older build
      if (replayVersion !== CURRENT_VERSION) {
        var vPath = location.pathname.replace(/\/$/, "") + "/v" + replayVersion + "/";
        location.replace(vPath + "?r=" + replayData);
        return;
      }

      pico8_gpio[0] = 0xfe; // signal: replay data present
      pico8_gpio[1] = bin.length;
      for (var i = 0; i < bin.length; i++) {
        pico8_gpio[i + 2] = bin.charCodeAt(i);
      }
    } catch (e) {
      console.warn("Failed to decode replay data:", e);
    }
  }

  // --- GPIO → Share: read chunks after run completion ---
  var collectedBytes = [];
  var shareUI = null;

  function pollGPIO() {
    var signal = pico8_gpio[0];

    if (signal === 0xff) {
      // chunk ready
      var len = pico8_gpio[1];
      for (var i = 0; i < len; i++) {
        collectedBytes.push(pico8_gpio[i + 2]);
      }
      pico8_gpio[0] = 0xfe; // consumed, send next
    } else if (signal === 0xfd) {
      // all chunks received
      pico8_gpio[0] = 0;
      if (collectedBytes.length > 0) {
        showShareUI(collectedBytes);
        collectedBytes = [];
      }
    }
  }

  setInterval(pollGPIO, 200);

  // --- Build share URL from raw bytes ---
  function bytesToBase64url(bytes) {
    var str = "";
    for (var i = 0; i < bytes.length; i++) {
      str += String.fromCharCode(bytes[i]);
    }
    return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  }

  // --- Share UI ---
  function showShareUI(bytes) {
    if (shareUI) shareUI.remove();

    var b64 = bytesToBase64url(bytes);
    var url = location.origin + location.pathname + "?r=" + b64;

    shareUI = document.createElement("div");
    shareUI.id = "replay-share";
    shareUI.innerHTML =
      '<div style="margin-bottom:8px;font-weight:bold">Share your run!</div>' +
      '<button id="replay-copy">Copy Link</button> ' +
      '<a id="replay-open" href="' +
      url +
      '" target="_blank" rel="noopener">Open in new tab</a>' +
      '<div id="replay-qr" style="margin-top:8px"></div>' +
      '<div id="replay-url" style="font-size:10px;word-break:break-all;margin-top:4px;color:#888;max-width:300px">' +
      url +
      "</div>";
    shareUI.style.cssText =
      "position:fixed;top:10px;right:10px;z-index:9999;" +
      "background:#222;color:#fff;padding:12px;border-radius:8px;" +
      "font-family:monospace;font-size:13px;max-width:320px";

    document.body.appendChild(shareUI);

    document.getElementById("replay-copy").onclick = function () {
      navigator.clipboard.writeText(url).then(function () {
        document.getElementById("replay-copy").textContent = "Copied!";
      });
    };

    // QR code generation (if library is loaded)
    if (typeof QRCode !== "undefined") {
      new QRCode(document.getElementById("replay-qr"), {
        text: url,
        width: 128,
        height: 128,
      });
    }
  }
})();
