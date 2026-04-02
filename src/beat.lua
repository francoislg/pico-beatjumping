sounds = {
  -- kicks: tonal instrument + drop = percussive
  boom  = { pitch=12, wave=0, vol=6, eff=3 },  -- sine kick, deep
  thud  = { pitch=12, wave=1, vol=6, eff=3 },  -- triangle kick, warm
  punch = { pitch=12, wave=3, vol=4, eff=3 },  -- long-sq kick, hollow
  knock = { pitch=12, wave=3, vol=6, eff=3 },  -- long-sq kick, loud
  -- hats: noise(6) only — other instruments sound like beeps
  tick  = { pitch=48, wave=6, vol=2, eff=5 },  -- closed hat (noise+fade)
  shh   = { pitch=48, wave=6, vol=2, eff=5, filters={buzz=true} },  -- brown noise hat
  soft  = { pitch=48, wave=6, vol=2, eff=5, filters={dampen=2} },  -- dampened hat, rim-like
  -- snares: noise at mid pitch
  snap  = { pitch=24, wave=6, vol=5, eff=5 },  -- tight snare
  crack = { pitch=30, wave=6, vol=4, eff=3 },  -- snare with drop
}

-- pattern: note positions (0-indexed). each beat = 4 notes.
-- e.g. note 0=beat1, 2=beat1-&, 4=beat2, 6=beat2-&, etc.
music_configs = {
  [0]  = { name="straight",    kick="boom",  hat="tick",  beats=4, notes=16,
           pattern={kick={0,8},       hat={4,12}} },
  [1]  = { name="driving",     kick="boom",  hat="tick",  beats=4, notes=16,
           pattern={kick={0,8},       hat={0,4,8,12}} },
  [2]  = { name="halftime",    kick="boom",  hat="soft",  beats=4, notes=16,
           pattern={kick={0},         hat={4,8,12}} },
  [3]  = { name="offbeat",     kick="boom",  hat="tick",  beats=4, notes=16,
           pattern={kick={0,8},       hat={2,6,10,14}} },
  [4]  = { name="bossa nova",  kick="boom",  hat="tick",  beats=4, notes=16,
           pattern={kick={0,6,10},    hat={2,4,8,12,14}} },
  [5]  = { name="shuffle",     kick="thud",  hat="soft",  beats=4, notes=16,
           pattern={kick={0,8},       hat={3,7,11,15}} },
  [6]  = { name="syncopated",  kick="knock", hat="tick",  beats=4, notes=16,
           pattern={kick={0,10},      hat={4,14}} },
  [7]  = { name="reggae",      kick="thud",  hat="soft",  beats=4, notes=16,
           pattern={kick={8},         hat={2,6,10,14}} },
  [8]  = { name="waltz",       kick="thud",  hat="tick",  beats=3, notes=12,
           pattern={kick={0},         hat={4,8}} },
  [9]  = { name="waltz swing", kick="boom",  hat="soft",  beats=3, notes=12,
           pattern={kick={0,6},       hat={4,8,10}} },
  [10] = { name="6/8",         kick="boom",  hat="soft",  beats=2, notes=12,
           pattern={kick={0,6},       hat={2,4,8,10}} },
  [11] = { name="5/4",         kick="thud",  hat="tick",  beats=5, notes=20,
           pattern={kick={0,12},      hat={4,8,16}} },
  [12] = { name="7/8",         kick="boom",  hat="soft",  beats=3, notes=14,
           pattern={kick={0,4,8},     hat={2,6,10,12}} },
  [13] = { name="7/4",         kick="knock", hat="tick",  beats=7, notes=28,
           pattern={kick={0,16},      hat={4,8,12,20,24}} },
  [14] = { name="9/8",         kick="thud",  hat="soft",  beats=4, notes=18,
           pattern={kick={0,4,8,12},  hat={2,6,10,14,16}} },
}

SCALES = {
  { name="major",      notes={ 0, 2, 4, 5, 7, 9, 11, 12 } },
  { name="minor",      notes={ 0, 2, 3, 5, 7, 8, 10, 12 } },
  { name="phrygian",   notes={ 0, 1, 3, 5, 7, 8, 10, 12 } },
  { name="pentatonic", notes={ 0, 2, 4, 7, 9, 12, 14, 16 } },
  { name="blues",      notes={ 0, 3, 5, 6, 7, 10, 12, 15 } },
  { name="diminished", notes={ 0, 2, 3, 5, 6, 8, 9, 11 } },
  { name="whole tone", notes={ 0, 2, 4, 6, 8, 10, 12, 14 } },
}
current_scale = SCALES[1].notes
octave_offset = 0

-- play a scale run on SFX slot 5, channel 2
-- scale: notes table, oct: octave offset, spd: speed, count: how many notes
function play_scale_run(scale, oct, spd, count)
  local si = 5
  local n = count or #scale
  memset(saddr(si), 0, 68)
  for i = 1, n do
    local val = nval(24 + scale[((i-1) % #scale) + 1] + oct, 1, 4)
    poke(saddr(si) + (i - 1) * 2, val % 256, flr(val / 256))
  end
  poke(saddr(si) + 64, 0, spd or 8, n, 0)
  sfx(si, 2)
end

beat = {
  speed = 18,
  beats_per_bar = 4,
  flash = 0,
  is_downbeat = false,
  on_kick = false,
  on_hat = false,
  march = 0,
  last_note = -1,
  kick_set = {},
  hat_set = {},
  total_notes = 16,
  DYN_KICK = 8,
  DYN_HAT = 9,

  write_note = function(self, sfx_i, note_i, snd_name)
    local s = sounds[snd_name]
    local val = nval(s.pitch, s.wave, s.vol, s.eff)
    poke(saddr(sfx_i) + note_i * 2, val % 256, flr(val / 256))
  end,

  write_header = function(self, sfx_i, note_count, filters)
    local f = filters or {}
    local byte0 = 0
    if (f.noiz) byte0 += 2
    if (f.buzz) byte0 += 4
    byte0 += (f.detune or 0) * 8
    byte0 += (f.reverb or 0) * 24
    byte0 += (f.dampen or 0) * 72
    poke(saddr(sfx_i) + 64, byte0, self.speed, note_count, 0)
  end,

  build_sfx = function(self, sfx_i, snd_name, note_positions, note_count)
    memset(saddr(sfx_i), 0, 68)
    self:write_header(sfx_i, note_count, sounds[snd_name].filters)
    for n in all(note_positions) do
      self:write_note(sfx_i, n, snd_name)
    end
  end,

  init = function(self, cfg)
    self.beats_per_bar = cfg.beats
    self.total_notes = cfg.notes
    self.last_note = -1
    self.on_kick = false
    self.on_hat = false
    self.march = 0
    self.flash = 0
    -- build lookups for visual sync
    self.kick_set = {}
    for n in all(cfg.pattern.kick) do
      self.kick_set[n] = true
    end
    self.hat_set = {}
    for n in all(cfg.pattern.hat) do
      self.hat_set[n] = true
    end

    self:build_sfx(self.DYN_KICK, cfg.kick, cfg.pattern.kick, cfg.notes)
    self:build_sfx(self.DYN_HAT,  cfg.hat,  cfg.pattern.hat,  cfg.notes)

    -- write music pattern to RAM
    local addr = 0x3100 + music_pattern * 4
    poke(addr, self.DYN_KICK + 0x80, self.DYN_HAT + 0x80, 0x42, 0x43)
    music(music_pattern, 0, 3)
  end,

  update = function(self)
    self.on_kick = false
    self.on_hat = false

    local ticks = stat(56)
    local current_note = flr(ticks / self.speed) % self.total_notes
    if current_note ~= self.last_note then
      self.last_note = current_note
      self.on_kick = self.kick_set[current_note] or false
      self.on_hat = self.hat_set[current_note] or false

      if (self.on_kick) self.march = 1 - self.march
      if self.on_hat then
        self.flash = 4
        self.is_downbeat = false
      end
      if self.on_kick then
        self.flash = 4
        self.is_downbeat = true
      end
    end

    if self.flash > 0 then
      self.flash -= 1
    end
  end
}
