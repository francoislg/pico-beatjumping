menu_state = {
  sel = 0,        -- 0=beat, 1=speed, 2=map
  sel_beat = 0,
  sel_speed = 18,
  sel_map = 1,
  prev_beat = -1,
  prev_speed = -1,

  enter = function(self)
    self.prev_beat = -1
    self.prev_speed = -1
  end,

  update = function(self)
    if btnp(2) then self.sel = max(0, self.sel - 1) end
    if btnp(3) then self.sel = min(2, self.sel + 1) end

    if self.sel == 0 then
      if btnp(0) then self.sel_beat = max(0, self.sel_beat - 1) end
      if btnp(1) then self.sel_beat = min(14, self.sel_beat + 1) end
    elseif self.sel == 1 then
      if btnp(0) then self.sel_speed = min(30, self.sel_speed + 2) end
      if btnp(1) then self.sel_speed = max(10, self.sel_speed - 2) end
    elseif self.sel == 2 then
      if btnp(0) then self.sel_map = max(1, self.sel_map - 1) end
      if btnp(1) then self.sel_map = min(#maps, self.sel_map + 1) end
    end

    -- rebuild preview on change
    if self.sel_beat ~= self.prev_beat or self.sel_speed ~= self.prev_speed then
      beat.speed = self.sel_speed
      music(-1)
      beat:init(music_configs[self.sel_beat])
      self.prev_beat = self.sel_beat
      self.prev_speed = self.sel_speed
    end

    beat:update()

    -- start game
    if btnp(4) or btnp(5) then
      countdown_state:start(self.sel_beat, self.sel_speed, self.sel_map)
    end
  end,

  draw = function(self)
    cls()
    local cfg = music_configs[self.sel_beat]
    local bpm = flr(7200 / (cfg.notes / cfg.beats * self.sel_speed))

    print("beat jumping", 28, 10, 7)
    line(10, 20, 118, 20, 1)

    local labels = {
      "beat: "..cfg.name,
      "tempo: ~"..bpm.." bpm",
      "map: "..maps[self.sel_map].name,
    }
    for i = 0, 2 do
      local y = 30 + i * 12
      local c = (i == self.sel) and 7 or 5
      local pre = (i == self.sel) and "> " or "  "
      print(pre..labels[i + 1], 8, y, c)
      if i == self.sel then
        print("<", 2, y, 6)
        print(">", 122, y, 6)
      end
    end

    if t() % 1 > 0.5 then
      print("o/x to start", 34, 70, 10)
    end

    fillp(0x5A5A)
    rect(0, 0, 127, 127, beat.march == 0 and 0xC1 or 0x1C)
    fillp()
  end
}

countdown_state = {
  total_beats = 0,
  beat_count = 0,
  last_note = -1,
  start_x = 0,
  start_y = 0,

  start = function(self, sel_beat, sel_speed, sel_map)
    self.beat_count = 0
    self.last_note = -1
    local map_data = maps[sel_map].data
    self.start_x = map_data.start.x
    self.start_y = map_data.start.y
    music(-1)
    music_pattern = 0
    beat.speed = sel_speed
    player:sync_to_beat(sel_speed)
    currentMap:init(map_data)
    local cfg = music_configs[sel_beat]
    self.total_beats = cfg.beats * 2  -- 2 full measures
    beat:init(music_configs[sel_beat])
    current_state = self
  end,

  update = function(self)
    beat:update()
    local ticks = stat(56)
    local cn = flr(ticks / beat.speed) % beat.total_notes
    if cn ~= self.last_note then
      self.last_note = cn
      if beat.kick_set[cn] or beat.hat_set[cn] then
        if self.beat_count >= self.total_beats then
          -- "go!" was shown last beat, now start playing
          player.x = self.start_x
          player.y = self.start_y
          player.accX = 0
          player.accY = 0
          current_state = play_state
        end
        self.beat_count += 1
      end
    end
  end,

  draw = function(self)
    cls()
    currentMap:draw()

    -- blink player marker on beat
    if beat.flash > 0 then
      circ(self.start_x, self.start_y, 3, 3)
    end
    pset(self.start_x, self.start_y, 3)

    -- count-in: "1.. 2.." (half-bar) then "1.2.3.4." then GO
    local bpb = beat.beats_per_bar
    local beat_in_bar = (self.beat_count - 1) % bpb + 1
    local measure = flr((self.beat_count - 1) / bpb) + 1
    local half = flr(bpb / 2) + 1  -- halfway point in bar
    local txt = ""
    if self.beat_count >= self.total_beats then
      txt = "go!"
    elseif measure == 1 then
      if (beat_in_bar == 1) txt = "1"
      if (beat_in_bar == half) txt = "2"
    elseif measure >= 2 then
      txt = tostr(beat_in_bar)
    end
    if txt ~= "" then
      local tx = 64 - #txt * 2
      print(txt, tx, 58, measure >= 2 and 10 or 6)
    end
  end
}

play_state = {
  update = function(self)
    check_controls()
    player:update()
    currentMap:update()
    beat:update()
  end,

  draw = function(self)
    cls()
    currentMap:draw()
    player:draw()

    if (debug_mode == 1) debug_collisions()
    if (debug_mode == 2) currentMap:debug(1)
    if (debug_mode == 3) player:debug()
  end
}

function go_to_menu()
  music(-1)
  menu_state:enter()
  current_state = menu_state
end
