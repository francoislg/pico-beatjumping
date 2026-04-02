map1 = {
  start = { x=20, y=120 },
  lines = { "15:127,15:80", "120:127,120:80", "15:80,80:80", "120:100,80:100", "15:32,50:32", "8:16,35:16" },
  waves = {
    { "100:90", "30:70" },
    { "70:40", "110:20", "20:100" },
    { "60:20", "100:50", "30:30", "110:90" },
  }
}

map2 = {
  start = { x=30, y=90 },
  lines = {
    -- left wall (short)
    "10:127,10:96",
    -- right wall (short)
    "118:127,118:96",
    -- zigzag platforms: alternate left and right
    "10:96,60:96",      -- bottom-left platform
    "68:80,118:80",     -- right platform
    "10:64,60:64",      -- left platform
    "68:48,118:48",     -- right platform
    "10:32,60:32",      -- left platform
    "80:16,118:16",     -- top-right platform
  },
  waves = {
    { "35:90", "90:74" },
    { "35:58", "90:42", "100:10" },
    { "20:26", "50:90", "90:58", "35:42" },
  }
}

map3 = {
  start = { x=64, y=108 },
  lines = {
    "20:127,20:112",    -- left base wall
    "108:127,108:112",  -- right base wall
    "40:112,88:112",    -- bottom center platform
    "20:96,55:96",      -- left platform
    "73:80,108:80",     -- right platform
    "20:64,55:64",      -- left platform
    "73:48,108:48",     -- right platform
    "40:32,88:32",      -- top center platform
  },
  waves = {
    { "48:90", "90:74" },
    { "35:58", "90:42" },
    { "48:26", "90:74", "35:90", "64:58" },
  }
}

map4 = {
  start = { x=64, y=120 },
  lines = {
    -- left wall narrowing
    "5:127,5:96",
    "15:96,15:64",
    "25:64,25:32",
    -- right wall narrowing
    "123:127,123:96",
    "113:96,113:64",
    "103:64,103:32",
    -- shelves
    "5:96,15:96",
    "113:96,123:96",
    "15:64,25:64",
    "103:64,113:64",
    "25:32,103:32",     -- top cap
    -- platforms inside
    "30:100,98:100",    -- low
    "38:68,90:68",      -- mid
    "45:44,83:44",      -- high
  },
  waves = {
    { "64:94", "20:120" },
    { "64:62", "110:120", "20:90" },
    { "64:38", "50:62", "78:62", "64:94" },
  }
}

map5 = {
  start = { x=15, y=120 },
  lines = {
    "5:127,123:127",    -- floor
    "5:127,5:20",       -- left wall
    "123:127,123:20",   -- right wall
    "5:20,123:20",      -- ceiling
    "5:100,70:100",     -- corridor 1 left
    "90:100,123:100",   -- corridor 1 right (gap 70-90)
    "5:72,40:72",       -- corridor 2 left
    "60:72,123:72",     -- corridor 2 right (gap 40-60)
    "5:44,80:44",       -- corridor 3 left
    "100:44,123:44",    -- corridor 3 right (gap 80-100)
  },
  waves = {
    { "110:90", "30:66" },
    { "80:38", "110:66", "50:90" },
    { "30:38", "110:38", "80:90", "50:66" },
  }
}

map6 = {
  start = { x=25, y=30 },
  lines = {
    "15:110,40:110",    -- small bottom-left
    "85:85,115:85",     -- small mid-right
    "45:60,75:60",      -- small center
    "10:35,40:35",      -- small top-left
    "90:40,120:40",     -- small top-right
  },
  waves = {
    { "28:104", "100:79" },
    { "60:54", "25:29", "105:34" },
    { "100:79", "28:104", "60:54", "25:29", "105:34" },
  }
}

maps = {
  { name="open field", data=map1 },
  { name="zigzag",     data=map2 },
  { name="tower",      data=map3 },
  { name="funnel",     data=map4 },
  { name="corridors",  data=map5 },
  { name="floating",   data=map6 },
}
