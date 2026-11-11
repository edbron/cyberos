-- Minimal stand-in for Hyprland's `hl` API. Records what the config asks for.
local calls = { bind = {}, bindcmd = {}, exec = {}, window_rule = 0, layer_rule = {}, cfg = {}, device = {} }
local function dsp(name) return function(args) return { name = name, args = args } end end
local function ns(prefix, names)
  local t = {}
  for _, n in ipairs(names) do t[n] = dsp(prefix .. n) end
  return t
end
hl = {
  monitor = function() end,
  env = function() end,
  curve = function() end,
  animation = function() end,
  on = function(ev, fn) if ev == "hyprland.start" then fn() end end,
  exec_cmd = function(cmd) calls.exec[#calls.exec + 1] = cmd end,
  bind = function(keys, d, opts)
    calls.bind[#calls.bind + 1] = keys
    if type(d) == "table" and d.name == "exec_cmd" then
      calls.bindcmd[#calls.bindcmd + 1] = keys .. " :: " .. tostring(d.args)
    end
    return {}
  end,
  window_rule = function() calls.window_rule = calls.window_rule + 1; return {} end,
  device = function(args) calls.device[#calls.device + 1] = args; return {} end,
  layer_rule = function(args) calls.layer_rule[#calls.layer_rule + 1] = args; return {} end,
  config = function(c)
    if c.general and c.general.col then calls.cfg.active_border = c.general.col.active_border end
  end,
  dsp = {
    exec_cmd = dsp("exec_cmd"), exit = dsp("exit"), focus = dsp("focus"), layout = dsp("layout"),
    window = ns("window.", { "close", "fullscreen", "float", "pseudo", "move", "drag", "resize" }),
    workspace = ns("workspace.", { "toggle_special" }),
  },
}
function report()
  for _, k in ipairs(calls.bind) do print("bind " .. k) end
  for _, c in ipairs(calls.bindcmd) do print("bindcmd " .. c) end
  for _, c in ipairs(calls.exec) do print("exec " .. c) end
  print("window_rules " .. calls.window_rule)
  print("layer_rules " .. #calls.layer_rule)
  for _, lr in ipairs(calls.layer_rule) do
    local ns = (lr.match and lr.match.namespace) or "?"
    print("layer_rule ns=" .. tostring(ns))
  end
  print("active_border=" .. tostring(calls.cfg.active_border))
  for _, d in ipairs(calls.device) do
    print("device name=" .. tostring(d.name) .. " enabled=" .. tostring(d.enabled))
  end
end
