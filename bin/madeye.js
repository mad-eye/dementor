#!/usr/bin/env node

if (process.env.MADEYE_BASE_HOST) {
  //console.log("Using base host", process.env.MADEYE_BASE_HOST);

  process.env.MADEYE_APOGEE_URL = "https://" + process.env.MADEYE_BASE_HOST
  process.env.MADEYE_AZKABAN_URL = "https://api." + process.env.MADEYE_BASE_HOST
  process.env.MADEYE_SOCKET_URL = "https://api." + process.env.MADEYE_BASE_HOST
}

require("coffee-script");
require("../app").run();
