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

maps = {
  { name="open field", data=map1 },
  { name="zigzag",     data=map2 },
}
