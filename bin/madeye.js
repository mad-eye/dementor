var Settings = {};
Settings.tunnelHost = process.env.MADEYE_TUNNEL_HOST;

if (process.env.MADEYE_BASE_URL) {
  var madeyeUrl = process.env.MADEYE_BASE_URL;
  madeyeUrl = madeyeUrl.replace(/\/$/, "");

  Settings.apogeeUrl = madeyeUrl;
  Settings.azkabanUrl = madeyeUrl + "/api";

  parsedUrl = require('url').parse(madeyeUrl);
  Settings.ddpHost = parsedUrl.hostname
  if (parsedUrl.protocol === 'http:') {
    Settings.ddpPort = 80;
  } else if (parsedUrl.protocol === 'https:') {
    Settings.ddpPort = 443;
  } else {
    console.error("ERROR: Can't figure out port for url " + madeyeUrl);
    process.exit(1);
  }
} else if (process.env.MADEYE_DEV_HOST) {
  var madeyeUrl = 'http://' + process.env.MADEYE_DEV_HOST;
  madeyeUrl = madeyeUrl.replace(/\/$/, "");
  Settings.apogeeUrl = madeyeUrl + ':' + process.env.MADEYE_NGINX_PORT;
  Settings.azkabanUrl = madeyeUrl + ':' + process.env.MADEYE_AZKABAN_PORT;
  Settings.ddpHost = process.env.MADEYE_DEV_HOST;
  Settings.ddpPort = process.env.MADEYE_DDP_PORT;
}

require("coffee-script");
require("../app").run(Settings);
