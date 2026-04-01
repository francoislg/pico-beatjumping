pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
local debug_mode = 0
local game_state = 0  -- 0=menu, 1=play
local menu_sel = 0    -- 0=beat, 1=speed
local sel_beat = 0
local sel_speed = 18
local prev_beat, prev_speed = -1, -1
local music_pattern = 0

function saddr(i) return 0x3200+i*68 end
function nval(p,w,v,e) return p+(w%8)*64+v*512+(e or 0)*4096 end

local sounds = {
  -- kicks: tonal instrument + drop = percussive
  boom  = { pitch=12, wave=0, vol=6, eff=3 },  -- sine kick, deep
  thud  = { pitch=12, wave=1, vol=6, eff=3 },  -- triangle kick, warm
  punch = { pitch=12, wave=3, vol=4, eff=3 },  -- long-sq kick, hollow
  knock = { pitch=12, wave=3, vol=6, eff=3 },  -- long-sq kick, loud
  -- hats: noise(6) only ヌ█⬆️ other instruments sound like beeps
  tick  = { pitch=48, wave=6, vol=2, eff=5 },  -- closed hat (noise+fade)
  shh   = { pitch=48, wave=6, vol=2, eff=5, filters={buzz=true} },  -- brown noise hat
  soft  = { pitch=48, wave=6, vol=2, eff=5, filters={dampen=2} },  -- dampened hat, rim-like
  -- snares: noise at mid pitch
  snap  = { pitch=24, wave=6, vol=5, eff=5 },  -- tight snare
  crack = { pitch=30, wave=6, vol=4, eff=3 },  -- snare with drop
}

-- pattern: note positions (0-indexed). each beat = 4 notes.
-- e.g. note 0=beat1, 2=beat1-&, 4=beat2, 6=beat2-&, etc.
local music_configs = {
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

local map1 = {
  lines = { "15:127,15:80", "120:127,120:80", "15:80,80:80", "120:100,80:100", "15:32,50:32", "8:16,35:16" },
  notes = { "100:90", "30:70", "70:40", "110:20" }
}

local SCALES = {
  major = { 0, 2, 4, 5, 7, 9, 11, 12 }
}

-- Inspired by: https://www.lexaloffle.com/bbs/?tid=42124
function make_sfx_note(sfx_i)
  local notes = {}
  for i = 0, 31 do
    notes[i] = peek(saddr(sfx_i) + 2 * i)
  end

  return {
    sfx_i = sfx_i,
    notes = notes,
    change_pitch = function(self, change)
      for i = 0, 31 do
        poke(saddr(self.sfx_i) + 2 * i, self.notes[i] + change)
      end
    end,
    play_at_pitch = function(self, change, channel)
      self:change_pitch(change)
      sfx(self.sfx_i, channel or -1)
    end
  }
end

local jump_note = make_sfx_note(0)
local spike_note = make_sfx_note(1)
local flourish_note = make_sfx_note(4)

local beat = {
  speed = 18,
  beats_per_bar = 4,
  flash = 0,
  is_downbeat = false,
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
    local ticks = stat(56)

    -- sync visuals to note positions
    local current_note = flr(ticks / self.speed) % self.total_notes
    if current_note ~= self.last_note then
      self.last_note = current_note
      if (self.kick_set[current_note]) self.march = 1 - self.march
      if self.hat_set[current_note] then
        self.flash = 4
        self.is_downbeat = false
      end
      if self.kick_set[current_note] then
        self.flash = 4
        self.is_downbeat = true
      end
    end

    if self.flash > 0 then
      self.flash -= 1
    end
  end
}

local currentMap = {
  lines = {},
  notes = {},
  cumulatedNotes = 0,
  generalTimer = 0,
  init = function(self, selectedMap)
    self.lines = {}
    self.notes = {}
    self.cumulatedNotes = 0
    self.generalTimer = 0
    for I = 1, #selectedMap.lines do
      local lineSplit = split(selectedMap.lines[I], ",")
      local lineStart = split(lineSplit[1], ":", true)
      local lineEnd = split(lineSplit[2], ":", true)
      self.lines[I] = { lineStart[1], lineStart[2], lineEnd[1], lineEnd[2] }
    end

    for I = 1, #selectedMap.notes do
      local pos = split(selectedMap.notes[I], ":", true)
      self.notes[I] = { pos[1], pos[2] }
    end
  end,
  update = function(self)
    self.generalTimer += 1
    if (self.generalTimer > 3600) then
      self.generalTimer = 0
    end
  end,
  get_immediate_collisions_data = function(self, x, y)
    -- left, right, up, down
    local collisions = { x - 1 <= 0, x + 1 >= 127, y - 1 <= 0, y + 1 >= 127 }
    for I = 1, #self.lines do
      if not collisions[1] then
        collisions[1] = self.check_point_in_line_collision(x - 1, y, self.lines[I][1], self.lines[I][2], self.lines[I][3], self.lines[I][4])
      end
      if not collisions[2] then
        collisions[2] = self.check_point_in_line_collision(x + 1, y, self.lines[I][1], self.lines[I][2], self.lines[I][3], self.lines[I][4])
      end
      if not collisions[3] then
        collisions[3] = self.check_point_in_line_collision(x, y - 1, self.lines[I][1], self.lines[I][2], self.lines[I][3], self.lines[I][4])
      end
      if not collisions[4] then
        collisions[4] = self.check_point_in_line_collision(x, y + 1, self.lines[I][1], self.lines[I][2], self.lines[I][3], self.lines[I][4])
      end
    end
    return collisions
  end,

  process_player_taking_note = function(self, x, y)
    local note_range = 4
    for I = 1, #self.notes do
      local note_x = self.notes[I][1]
      local note_y = self.notes[I][2]
      if (abs(note_x - x) <= note_range and abs(note_y - y) <= note_range) then
        del(self.notes, self.notes[I])
        self:score_note(note_y)
        break
      end
    end
  end,

  play_coin = function(self, y)
    local si = 5
    memset(saddr(si), 0, 68)
    local p = 36 + SCALES.major[mid(1, (8 - ceil(y / 16)) + 1, 8)]
    local n1 = nval(p, 5, 5)
    local n2 = nval(p + 7, 5, 4, 5)
    poke(saddr(si), n1 % 256, flr(n1 / 256))
    poke(saddr(si) + 2, n2 % 256, flr(n2 / 256))
    poke(saddr(si) + 64, 0, 3, 2, 0)
    sfx(si, 3)
  end,
  score_note = function(self, y)
    self.cumulatedNotes += 1
    self:play_coin(y)
  end,

  get_collision_x = function(self, x, y, speedX)
    if (speedX == 0) then
      return 0
    end

    local direction = speedX > 0 and 1 or -1
    local collision_range = abs(speedX)
    for xS = 0, abs(speedX) do
      local pixel = x + (direction * (xS + 1))
      if self.is_out_of_bounds(pixel, y) then
        collision_range = min(xS, collision_range)
        break
      end
      for I = 1, #self.lines do
        if self.check_point_in_line_collision(pixel, y, self.lines[I][1], self.lines[I][2], self.lines[I][3], self.lines[I][4]) then
          collision_range = min(xS, collision_range)
          break
        end
      end
    end

    return collision_range
  end,

  get_collision_y = function(self, x, y, speedY)
    if (speedY == 0) then
      return 0
    end

    local direction = speedY > 0 and -1 or 1
    local collision_range = abs(speedY)
    for yS = 0, abs(speedY) do
      local pixel = y + (direction * (yS + 1))
      if self.is_out_of_bounds(x, pixel) then
        collision_range = min(yS, collision_range)
        break
      end
      for I = 1, #self.lines do
        if self.check_point_in_line_collision(x, pixel, self.lines[I][1], self.lines[I][2], self.lines[I][3], self.lines[I][4]) then
          collision_range = min(yS, collision_range)
          break
        end
      end
    end
    return collision_range
  end,

  is_out_of_bounds = function(x, y)
    return x <= 0 or x >= 127 or y <= 0 or y >= 127
  end,

  check_point_in_line_collision = function(px, py, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local l2 = dx * dx + dy * dy
    if l2 == 0 then return false end
    local t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / l2))
    local nx = x1 + t * dx - px
    local ny = y1 + t * dy - py
    return (nx * nx + ny * ny) <= 0.25
  end,

  debug = function(self, i)
    local color = 5
    print(map1[i], 0, 100, color)
    print(self.lines[i][1], 0, 120, color)
    print(self.lines[i][2], 20, 120, color)
    print(self.lines[i][3], 40, 120, color)
    print(self.lines[i][4], 60, 120, color)
  end,
  draw = function(self)
    for I = 1, 7 do
      line(0, I * 16, 127, I * 16, 1)
    end

    local lc = 7
    if beat.flash > 0 then
      lc = (beat.is_downbeat and 6 or 5) * 16 + 7
      fillp(0x5A5A)
    end
    for I = 1, #self.lines do
      line(self.lines[I][1], self.lines[I][2], self.lines[I][3], self.lines[I][4], lc)
    end
    fillp()

    for I = 1, #self.notes do
      spr(flr(self.generalTimer % 60 / 10) + 1, self.notes[I][1] - 4, self.notes[I][2] - 4)
    end

    -- marching border: toggles on each kick hit
    fillp(0x5A5A)
    rect(0, 0, 127, 127, beat.march == 0 and 0xC1 or 0x1C)
    fillp()

    print(tostr(self.cumulatedNotes), 120, 5)
  end
}

local FACTOR = 100
local player = {
  SETTINGS = {
    speed = FACTOR,
    jump_force = FACTOR * 3,
    down_force = FACTOR * 3,
    gravity = FACTOR / 10,
    max_speed_x = 2 * FACTOR,
    max_speed_y = 3 * FACTOR,
    decay = FACTOR / 3
  },

  x = 8,
  y = 50,
  accX = 0,
  accY = 0,
  canJump = false,
  airJumps = 0,
  maxAirJumps = 1,
  jumpTriggered = 0,
  timeSinceJump = 0,
  timeSinceWallJump = 0,
  spiking = false,
  lastNote = 1,
  coyoteWall = 0,
  lastWallDir = 0,
  jumpSfxType = 0,
  -- scale physics so jump height = ~40px, full held jump = 2 beats
  sync_to_beat = function(self, spd)
    local fpb = spd * 1.875  -- frames per beat
    local dur = fpb           -- full jump = 1 beat
    local h = 40 * FACTOR    -- target height in factor units
    self.SETTINGS.jump_force = max(1, flr(4 * h / dur))
    self.SETTINGS.gravity = max(1, flr(8 * h / (dur * dur)))
    self.SETTINGS.down_force = self.SETTINGS.jump_force
    self.SETTINGS.max_speed_y = self.SETTINGS.jump_force
  end,
  moveLeft = function(self)
    if (self.timeSinceWallJump > 0) then
      return
    end
    self.accX += -self.SETTINGS.speed
  end,
  moveRight = function(self)
    if (self.timeSinceWallJump > 0) then
      return
    end
    self.accX += self.SETTINGS.speed
  end,
  -- sfx_type: 0=normal, 1=flourish
  jump = function(self, sfx_type)
    self.jumpTriggered = 10
    self.jumpSfxType = sfx_type or 0
  end,
  release_jump = function(self)
    if (self.accY > 0) then
      self.accY = 0
    end
  end,
  spike = function(self)
    self.spiking = true
  end,
  release_spike = function(self)
    self.spiking = false
  end,
  update = function(self)
    if (self.timeSinceJump > 0) then
      self.timeSinceJump -= 1
    end
    if (self.jumpTriggered > 0) then
      self.jumpTriggered -= 1
    end
    if (self.timeSinceWallJump > 0) then
      self.timeSinceWallJump -= 1
    end

    self.accX = clamp(decay(self.accX, self.SETTINGS.decay), -self.SETTINGS.max_speed_x, self.SETTINGS.max_speed_x)
    self.accY = clamp(self.accY, -self.SETTINGS.max_speed_y, self.SETTINGS.max_speed_y)

    local collision = currentMap:get_immediate_collisions_data(self.x, self.y)
    local is_hugging_left_wall = self.accX < 0 and collision[1]
    local is_hugging_right_wall = self.accX > 0 and collision[2]

    if not collision[4] and self.spiking then
      if (self.accY < -self.SETTINGS.down_force) then
        self:spike_sfx(self.lastNote)
      end
      self.accY = -self.SETTINGS.down_force
    end

    local currentNote = (8 - ceil(self.y / 16)) + 1
    if (currentNote ~= self.lastNote) then
      if self.spiking then
        self:spike_sfx(currentNote)
      end
      self.lastNote = currentNote
    end

    if is_hugging_left_wall or is_hugging_right_wall then
      self.coyoteWall = 4
      self.lastWallDir = is_hugging_left_wall and -1 or 1
    elseif self.coyoteWall > 0 then
      self.coyoteWall -= 1
    end

    local can_wall_coyote = self.coyoteWall > 0 and not collision[4]

    local on_surface = collision[4] == true or is_hugging_left_wall or is_hugging_right_wall or can_wall_coyote

    if on_surface and not self.canJump and self.timeSinceJump <= 0 then
      self.canJump = true
      self.airJumps = 0
    end

    if self.jumpTriggered > 0 and (self.canJump or self.airJumps < self.maxAirJumps) then
      local is_air_jump = not self.canJump
      self.accY = self.SETTINGS.jump_force
      self.canJump = false
      self.timeSinceJump = 20

      if is_air_jump then
        self.airJumps += 1
      else
        local wall_left = is_hugging_left_wall or (can_wall_coyote and self.lastWallDir == -1)
        local wall_right = is_hugging_right_wall or (can_wall_coyote and self.lastWallDir == 1)

        if wall_left then
          self.accX = self.SETTINGS.jump_force
          self.timeSinceWallJump = 5
        end
        if wall_right then
          self.accX = -self.SETTINGS.jump_force
          self.timeSinceWallJump = 5
        end
        self.coyoteWall = 0
      end

      self.jumpTriggered = 0

      if self.jumpSfxType == 1 then
        self:flourish_sfx()
      elseif self.jumpSfxType == 2 then
        self:pluck_sfx()
      else
        self:jump_sfx()
      end
    end

    if (is_hugging_left_wall or is_hugging_right_wall) then
      self.accY -= self.SETTINGS.gravity / 2
    else
      self.accY -= self.SETTINGS.gravity
    end

    local collision_x = currentMap:get_collision_x(self.x, self.y, self.accX / FACTOR) * FACTOR
    self.accX = clamp(self.accX, -collision_x, collision_x)

    local collision_y = currentMap:get_collision_y(self.x, self.y, self.accY / FACTOR) * FACTOR
    self.accY = clamp(self.accY, -collision_y, collision_y)

    self.x += flr(self.accX / FACTOR)
    self.y -= flr(self.accY / FACTOR)

    currentMap:process_player_taking_note(self.x, self.y)
  end,
  -- write a single note to an SFX slot and play it
  play_note = function(self, sfx_i, pitch, wave, vol, eff, spd, ch)
    memset(saddr(sfx_i), 0, 68)
    local val = nval(pitch, wave, vol, eff)
    poke(saddr(sfx_i), val % 256, flr(val / 256))
    poke(saddr(sfx_i) + 64, 0, spd, 1, 0)
    sfx(sfx_i, ch)
  end,
  -- write a chord arpeggio to an SFX slot and play it
  play_chord = function(self, sfx_i, pitches, wave, vol, spd, ch)
    memset(saddr(sfx_i), 0, 68)
    for i = 1, #pitches do
      local v = max(1, vol - flr(i / 3))
      local val = nval(pitches[i], wave, v)
      poke(saddr(sfx_i) + (i - 1) * 2, val % 256, flr(val / 256))
    end
    poke(saddr(sfx_i) + 64, 0, spd, #pitches, 0)
    sfx(sfx_i, ch)
  end,
  -- get scale degree, wrapping into next octave
  scale_at = function(self, n)
    if (n <= 8) return SCALES.major[n]
    return SCALES.major[n - 7] + 12
  end,
  jump_sfx = function(self)
    jump_note:play_at_pitch(SCALES.major[self.lastNote], 2)
  end,
  -- btn 4: short pluck (triangle, single note)
  pluck_sfx = function(self)
    local p = 24 + SCALES.major[self.lastNote]
    self:play_note(3, p, 1, 5, 5, 4, 2)
  end,
  -- btn 5: arpeggio chord from scale (square wave)
  flourish_sfx = function(self)
    local n = self.lastNote
    local base = 24
    local pitches = {
      base + self:scale_at(n),
      base + self:scale_at(n + 2),
      base + self:scale_at(n + 4),
      base + self:scale_at(n) + 12,
    }
    self:play_chord(4, pitches, 3, 5, 2, 3)
  end,
  spike_sfx = function(self, note)
    spike_note:play_at_pitch(flr(SCALES.major[note] / 2), 2)
  end,
  draw = function(self)
    pset(self.x, self.y, 3)
  end,
  debug = function(self)
    print("X:" .. tostr(self.accX) .. ":" .. tostr(self.accY), 5, 5)
    print("P:" .. tostr(self.x) .. ":" .. tostr(self.y) .. ", J:" .. tostr(self.canJump) .. ", T:" .. tostr(self.jumpTriggered), 5, 15)
  end
}

function menu_update()
  if btnp(2) then menu_sel = max(0, menu_sel - 1) end
  if btnp(3) then menu_sel = min(1, menu_sel + 1) end

  if menu_sel == 0 then
    if btnp(0) then sel_beat = max(0, sel_beat - 1) end
    if btnp(1) then sel_beat = min(14, sel_beat + 1) end
  else
    if btnp(0) then sel_speed = min(30, sel_speed + 2) end
    if btnp(1) then sel_speed = max(10, sel_speed - 2) end
  end

  -- rebuild preview on change
  if sel_beat ~= prev_beat or sel_speed ~= prev_speed then
    beat.speed = sel_speed
    music(-1)
    beat:init(music_configs[sel_beat])
    prev_beat = sel_beat
    prev_speed = sel_speed
  end

  beat:update()

  -- start game
  if btnp(4) or btnp(5) then
    game_state = 1
    music(-1)
    music_pattern = 0
    beat.speed = sel_speed
    player:sync_to_beat(sel_speed)
    currentMap:init(map1)
    beat:init(music_configs[sel_beat])
  end
end

function menu_draw()
  cls()
  local cfg = music_configs[sel_beat]
  local bpm = flr(7200 / (cfg.notes / cfg.beats * sel_speed))

  print("beat jumping", 28, 10, 7)
  line(10, 20, 118, 20, 1)

  for i = 0, 1 do
    local y = 30 + i * 12
    local c = (i == menu_sel) and 7 or 5
    local pre = (i == menu_sel) and "> " or "  "
    if i == 0 then
      print(pre.."beat: "..cfg.name, 8, y, c)
    else
      print(pre.."tempo: ~"..bpm.." bpm", 8, y, c)
    end
    if i == menu_sel then
      print("<", 2, y, 6)
      print(">", 122, y, 6)
    end
  end

  if t() % 1 > 0.5 then
    print("o/x to start", 34, 70, 10)
  end

  -- beat preview flash on border
  fillp(0x5A5A)
  rect(0, 0, 127, 127, beat.march == 0 and 0xC1 or 0x1C)
  fillp()
end

function go_to_menu()
  game_state = 0
  music(-1)
  prev_beat = -1
  prev_speed = -1
end

function _init()
  menuitem(1, "back to menu", go_to_menu)
  beat.speed = sel_speed
  beat:init(music_configs[sel_beat])
end

function clamp(val, min, max)
  if (val < min) then
    return min
  end
  if (val > max) then
    return max
  end
  return val
end

function decay(val, dec)
  if (val > 0) then
    return max(0, val - dec)
  end
  if (val < 0) then
    return min(0, val + dec)
  end
  return val
end

local is_holding_jump = false
local is_holding_spike = false
local is_holding_a = false
local is_holding_flourish = false
function check_controls()
  if btn(0) then
    player:moveLeft()
  end
  if btn(1) then
    player:moveRight()
  end
  if btn(2) and not is_holding_jump then
    is_holding_jump = true
    player:jump()
  end
  if is_holding_jump and not btn(2) then
    is_holding_jump = false
    player:release_jump()
  end
  if btn(3) and not is_holding_spike then
    is_holding_spike = true
    player:spike()
  end
  if is_holding_spike and not btn(3) then
    is_holding_spike = false
    player:release_spike()
  end
  if btn(4) and not is_holding_a then
    is_holding_a = true
    player:jump(2)
  end
  if is_holding_a and not btn(4) then
    is_holding_a = false
    player:release_jump()
  end
  if btn(5) and not is_holding_flourish then
    is_holding_flourish = true
    player:jump(1)
  end
  if is_holding_flourish and not btn(5) then
    is_holding_flourish = false
    player:release_jump()
  end
end

function _update60()
  if game_state == 0 then
    menu_update()
  else
    check_controls()
    player:update()
    currentMap:update()
    beat:update()
  end
end

function debug_collisions()
  local collisions = currentMap:get_immediate_collisions_data(player.x, player.y)
  print("L:" .. tostr(collisions[1]) .. ", R:" .. tostr(collisions[2]) .. ", U:" .. tostr(collisions[3]) .. ", D:" .. tostr(collisions[4]), 5, 5)
  print("Jump:" .. tostr(player.canJump) .. " D:" .. tostr(player.accY > 0 and 1 or -1) .. ":" .. tostr(player.timeSinceJump), 5, 15)
end

function _draw()
  if game_state == 0 then
    menu_draw()
    return
  end
  cls()
  currentMap:draw()
  player:draw()

  if (debug_mode == 1) then
    debug_collisions()
  end
  if (debug_mode == 2) then
    currentMap:debug(1)
  end
  if (debug_mode == 3) then
    player:debug()
  end
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000099900000990000099000009990000009900000009900000000000000000000000000000000000000000000000000000000000000000000000000
00000000000099000000900000009000000990000000900000009000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000090000000900000009000000090000000900000009000000000000000000000000000000000000000000000000000000000000000000000000000
00000000009990000099990000099990000099900009999000999900000000000000000000000000000000000000000000000000000000000000000000000000
00000000009990000099990000099990000099900009999000999900000000000000000000000000000000000000000000000000000000000000000000000000
00000000009990000099990000099990000099900009999000999900000000000000000000000000000000000000000000000000000000000000000000000000
__label__
1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011100001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010100001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011100001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1111111177777777777777777777777777771111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000999000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000099000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000900000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009990000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000099900000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009990000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1111111111111117777777777777777777777777777777777771111111111111111111111111111111111111111111111111111111111111111111111111111c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000009990000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000990000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000099900000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000999000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000099900000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000099900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000009900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000090000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000009990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000999000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c
c0000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
1111111111111117777777777777777777777777777777777777777777777777777777777777777771111111111111111111111111111111111111117111111c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000009990000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000990000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000099900000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000999000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000099900000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1111111111111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117111111c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000077777777777777777777777777777777777777777000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1111111111111117111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111117111111c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c0000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070000001
1000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000c
c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1

__sfx__
020000000c5100c5100c5100c5100c5200c5360c5470c5400c5510c5500c5500c5500c5510c5400c5471203708036050270302002020010100001000000000000000000000000000000000000000000050000000
000100002c0502b0502a0502a050290502805028050280502705026050260502505024050230502205021050200501f0501e0501c0501b0501a0501905017050160501405013050110500f0500d0500b05009050
001200100c063000000000000000000000000000000000000c0530000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001200100000000000000000000030625000000000000000000000000000000000003062500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200000c35010350133401834018335183250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00120c000c16300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00120c000000000000000000000018525000000000000000185250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
022000001885000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
03 02034243
03 05064243

