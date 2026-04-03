menu_state = {
  sel = 0,        -- 0=beat, 1=speed, 2=map, 3=scale, 4=octave
  sel_beat = 0,
  sel_speed = 18,
  sel_map = 1,
  sel_scale = 1,
  sel_octave = 0, -- -1, 0, +1
  prev_beat  = -1,
  prev_speed = -1,

  enter = function(self)
    self.prev_beat = -1
    self.prev_speed = -1
    self.clip_err = false
  end,

  update = function(self)
    if btnp(2) then self.sel = max(0, self.sel - 1) end
    if btnp(3) then self.sel = min(4, self.sel + 1) end

    if self.sel == 0 then
      if btnp(0) then self.sel_beat = (self.sel_beat - 1) % 15 end
      if btnp(1) then self.sel_beat = (self.sel_beat + 1) % 15 end
    elseif self.sel == 1 then
      if btnp(0) then self.sel_speed = min(30, self.sel_speed + 2) end
      if btnp(1) then self.sel_speed = max(10, self.sel_speed - 2) end
    elseif self.sel == 2 then
      if btnp(0) then self.sel_map = (self.sel_map - 2) % #maps + 1 end
      if btnp(1) then self.sel_map = self.sel_map % #maps + 1 end
    elseif self.sel == 3 then
      if btnp(0) then self.sel_scale = (self.sel_scale - 2) % #SCALES + 1 end
      if btnp(1) then self.sel_scale = self.sel_scale % #SCALES + 1 end
    elseif self.sel == 4 then
      if btnp(0) then self.sel_octave = max(-1, self.sel_octave - 1) end
      if btnp(1) then self.sel_octave = min(1, self.sel_octave + 1) end
    end

    -- preview scale/octave on change
    if (self.sel == 3 or self.sel == 4) and (btnp(0) or btnp(1)) then
      play_scale_run(SCALES[self.sel_scale].notes, self.sel_octave * 12, 8, 8)
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

    -- paste replay from clipboard (ctrl+v)
    local clip = stat(4)
    if clip and #clip >= 6 and clip ~= last_export then
      local s, ev = import_clipboard()
      printh("", "@clip")
      if s then
        start_replay(s, ev)
      else
        self.clip_err = true
      end
    end

    -- start game
    if btnp(4) or btnp(5) then
      current_scale = SCALES[self.sel_scale].notes
      octave_offset = self.sel_octave * 12
      countdown_state:start(self.sel_beat, self.sel_speed, self.sel_map)
    end
  end,

  draw = function(self)
    cls()
    local cfg = music_configs[self.sel_beat]
    local bpm = flr(7200 / (cfg.notes / cfg.beats * self.sel_speed))

    print("beat jumping", 28, 10, 7)
    line(10, 20, 118, 20, 1)

    local oct_label = self.sel_octave == 0 and "normal" or (self.sel_octave > 0 and "+"..self.sel_octave or tostr(self.sel_octave))
    local labels = {
      "beat: "..cfg.name,
      "tempo: ~"..bpm.." bpm",
      "map: "..maps[self.sel_map].name,
      "scale: "..SCALES[self.sel_scale].name,
      "octave: "..oct_label,
    }
    for i = 0, 4 do
      local y = 26 + i * 10
      local c = (i == self.sel) and 7 or 5
      local pre = (i == self.sel) and "> " or "  "
      print(pre..labels[i + 1], 8, y, c)
      if i == self.sel then
        print("<", 2, y, 6)
        print(">", 122, y, 6)
      end
    end

    if beat.march == 0 then
      print("o/x to start", 34, 86, 10)
      print(self.clip_err and "invalid replay? try again" or "ctrl+v to paste replay", self.clip_err and 10 or 16, 96, 8)
    end

    print("v"..REPLAY_VERSION, 2, 122, 1)

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
    rec_reset()
    self.beat_count = 0
    self.last_note = -1
    local map_data = maps[sel_map].data
    self.start_x = map_data.start[1]
    self.start_y = map_data.start[2]
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
          play_state.end_sel = 0
          play_state.copied = false
          play_state.end_ready = false
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
  end_sel = 0,   -- 0=copy replay, 1=menu (or 0=menu in replay)
  copied = false,
  end_ready = false,

  update = function(self)
    if is_replay then replay_advance() end
    if currentMap.complete then
      gpio_update()
      -- skip first frame so held buttons don't fire
      if not self.end_ready then
        self.end_ready = true
      elseif is_replay then
        if real_btnp(4) or real_btnp(5) then
          stop_replay()
          self.end_ready = false
          go_to_menu()
        end
      else
        if btnp(2) then self.end_sel = max(0, self.end_sel - 1) end
        if btnp(3) then self.end_sel = min(1, self.end_sel + 1) end
        if btnp(4) or btnp(5) then
          if self.end_sel == 0 and not self.copied then
            local bytes = encode_replay()
            export_clipboard(bytes)
            gpio_start(bytes)
            self.copied = true
            self.end_sel = 1
          else
            self.end_sel = 0
            self.copied = false
            self.end_ready = false
            go_to_menu()
          end
        end
      end
    else
      if (not is_replay) rec_update()
      check_controls()
      player:update()
    end
    currentMap:update()
    beat:update()
  end,

  draw = function(self)
    cls()
    currentMap:draw()
    player:draw()
    currentMap:draw_complete()

    if (is_replay and beat.march == 1) print("rep", 4, 5, 8)

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
