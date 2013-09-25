#!/usr/bin/env node

if (process.env.MADEYE_BASE_URL) {
  process.env.MADEYE_APOGEE_URL = process.env.MADEYE_BASE_URL
  process.env.MADEYE_AZKABAN_URL = process.env.MADEYE_BASE_URL + "/api";
}

require("coffee-script");
require("../app").run();
