#!/usr/bin/env node

if (process.env.MADEYE_BASE_URL) {
  //console.log("Using base host", process.env.MADEYE_BASE_HOST);

  process.env.MADEYE_APOGEE_URL = process.env.MADEYE_BASE_URL
  process.env.MADEYE_AZKABAN_URL = process.env.MADEYE_BASE_URL + "/api";
  process.env.MADEYE_SOCKET_URL = process.env.MADEYE_BASE_URL
}

require("coffee-script");
require("../app").run();
