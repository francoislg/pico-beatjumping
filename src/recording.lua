-- replay recording, encoding, decoding, and GPIO export
-- bump REPLAY_VERSION when physics/controls change
REPLAY_VERSION = 1

local rec, rec_f, rec_pb = {}, 0, 0

function rec_reset()
  rec, rec_f, rec_pb = {}, 0, 0
end

function rec_update()
  rec_f += 1
  local b = 0
  for i = 0, 5 do
    if (btn(i)) b += shl(1, i)
  end
  if b ~= rec_pb then
    add(rec, {rec_f, b})
    rec_pb = b
  end
end

function encode_replay()
  local bytes = {}
  add(bytes, REPLAY_VERSION)
  local ms = menu_state
  add(bytes, ms.sel_beat * 16 + flr((ms.sel_speed - 10) / 2))
  add(bytes, (ms.sel_map - 1) * 32 + (ms.sel_scale - 1) * 4 + (ms.sel_octave + 1))
  local pf = 0
  for e in all(rec) do
    local d = e[1] - pf
    pf = e[1]
    if d >= 128 then
      add(bytes, 128 + flr(d / 256))
      add(bytes, d % 256)
    else
      add(bytes, d)
    end
    add(bytes, e[2])
  end
  return bytes
end

local HEX = "0123456789abcdef"
last_export = ""
function export_clipboard(bytes)
  local h = ""
  for b in all(bytes) do
    local hi = flr(b / 16) + 1
    h ..= sub(HEX, hi, hi) .. sub(HEX, b % 16 + 1, b % 16 + 1)
  end
  last_export = h
  printh(h, "@clip")
end

function import_clipboard()
  local h = stat(4)
  if #h < 6 then return nil end
  local bytes = {}
  for i = 1, #h, 2 do
    local hi = instr(HEX, sub(h, i, i))
    local lo = instr(HEX, sub(h, i + 1, i + 1))
    if (not hi or not lo) return nil
    add(bytes, (hi - 1) * 16 + (lo - 1))
  end
  return decode_replay(bytes)
end

function instr(s, c)
  for i = 1, #s do
    if (sub(s, i, i) == c) return i
  end
end

-- gpio chunked export for JS bridge
local gpio_bytes, gpio_idx, gpio_active = {}, 1, false

function gpio_start(bytes)
  gpio_bytes, gpio_idx, gpio_active = bytes, 1, true
  poke(0x5f80, 0xfe)
end

function gpio_update()
  if (not gpio_active) return
  if (peek(0x5f80) ~= 0xfe) return
  local n = min(125, #gpio_bytes - gpio_idx + 1)
  if n <= 0 then
    poke(0x5f80, 0xfd)
    gpio_active = false
    return
  end
  poke(0x5f81, n)
  for j = 0, n - 1 do
    poke(0x5f82 + j, gpio_bytes[gpio_idx + j])
  end
  gpio_idx += n
  poke(0x5f80, 0xff)
end

function decode_replay(bytes)
  if bytes[1] ~= REPLAY_VERSION then return nil end
  local b1, b2 = bytes[2], bytes[3]
  local s = {
    beat = flr(b1 / 16),
    speed = (b1 % 16) * 2 + 10,
    map = flr(b2 / 32) + 1,
    scale = flr(b2 / 4) % 8 + 1,
    octave = (b2 % 4) - 1
  }
  local events, f, i = {}, 0, 4
  while i <= #bytes do
    local d = bytes[i]
    i += 1
    if d >= 128 then
      d = (d - 128) * 256 + bytes[i]
      i += 1
    end
    f += d
    add(events, {f, bytes[i]})
    i += 1
  end
  return s, events
end

-- replay: input override
real_btn, real_btnp = btn, btnp
local rep_b, rep_pb = 0, 0
local rep_events, rep_idx, rep_frame = {}, 1, 0
is_replay = false

function start_replay(s, events)
  is_replay = true
  rep_events, rep_idx, rep_frame, rep_b, rep_pb = events, 1, 0, 0, 0
  btn = function(i) return band(rep_b, shl(1, i)) ~= 0 end
  btnp = function(i) return band(rep_b, shl(1, i)) ~= 0 and band(rep_pb, shl(1, i)) == 0 end
  current_scale = SCALES[s.scale].notes
  octave_offset = s.octave * 12
  countdown_state:start(s.beat, s.speed, s.map)
end

function replay_advance()
  rep_frame += 1
  rep_pb = rep_b
  while rep_idx <= #rep_events and rep_events[rep_idx][1] <= rep_frame do
    rep_b = rep_events[rep_idx][2]
    rep_idx += 1
  end
end

function stop_replay()
  btn, btnp = real_btn, real_btnp
  is_replay = false
end
