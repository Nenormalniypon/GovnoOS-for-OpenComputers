-- XFCE-Lite OS для OpenComputers (без OpenOS, грузится как /init.lua)
local component, computer, unicode = component, computer, unicode
local function proxy(t) local a = component.list(t)() return a and component.proxy(a) end
local gpu, fs = proxy("gpu"), component.proxy(computer.getBootAddress())
gpu.bind(component.list("screen")())
local W, H = gpu.maxResolution()
gpu.setResolution(W, H)

local C = {desk=0x3B6EA5, panel=0x2E3436, ptxt=0xEEEEEC, win=0xF6F5F4, wtxt=0x2E3436,
  title=0x4A90D9, titleOff=0x7A8A99, ttxt=0xFFFFFF, sel=0x4A90D9, menu=0xEEEEEC,
  btnX=0xCC0000, bar=0xE0DFDE, term=0x300A24}

---------------------------------------------------------------- утилиты
local function rect(x, y, w, h, bg) gpu.setBackground(bg); gpu.fill(x, y, w, h, " ") end
local function text(x, y, s, fg, bg) gpu.setBackground(bg); gpu.setForeground(fg); gpu.set(x, y, s) end
local function len(s) return unicode.len(s) end
local function sub(s, a, b) return unicode.sub(s, a, b) end
local function clip(s, n) if len(s) > n then return sub(s, 1, n) end return s end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function join(a, b)
  b = b:gsub("/$", "")
  if b:sub(1, 1) == "/" then return b end
  if a == "/" then return "/" .. b end
  return a .. "/" .. b
end
local function parent(p) local q = (p:gsub("/[^/]+/?$", "")) return q == "" and "/" or q end
local function readFile(p)
  local h = fs.open(p, "r"); if not h then return nil end
  local b = {}
  repeat local d = fs.read(h, math.huge); b[#b + 1] = d until not d
  fs.close(h); return table.concat(b)
end
local function writeFile(p, s)
  local h = fs.open(p, "w"); if not h then return false end
  fs.write(h, s); fs.close(h); return true
end

---------------------------------------------------------------- окна
local wins, ctrl, menuOpen, drag, lastErr = {}, false, false, nil, nil
local function newWin(title, w, h, app)
  w, h = math.min(w, W), math.min(h, H - 1)
  local n = #wins
  local win = {title = title, w = w, h = h,
    x = clamp(math.floor((W - w) / 2) + n * 2, 1, W - w + 1),
    y = clamp(math.floor((H - h) / 2) + n, 2, H - h + 1)}
  for k, v in pairs(app) do win[k] = v end
  wins[#wins + 1] = win
  if win.init then win:init() end
  return win
end

---------------------------------------------------------------- приложения
local Files = {
  init = function(s) s.path = "/"; s:load() end,
  load = function(s)
    local l = fs.list(s.path) or {}
    table.sort(l)
    s.items = {}
    if s.path ~= "/" then s.items[1] = "../" end
    for _, n in ipairs(l) do s.items[#s.items + 1] = n end
    s.scroll = 0
  end,
  draw = function(s, x, y, w, h)
    rect(x, y, w, 1, C.bar)
    text(x, y, clip(" " .. s.path, w), C.wtxt, C.bar)
    for r = 1, h - 1 do
      local it = s.items[s.scroll + r]
      if it then
        local dir = it:sub(-1) == "/"
        text(x, y + r, clip((dir and " ▸ " or "   ") .. it, w), dir and 0x1C5FA8 or C.wtxt, C.win)
      end
    end
  end,
  click = function(s, mx, my)
    local it = s.items[my - (s.y + 1) + s.scroll]
    if not it then return end
    if it == "../" then s.path = parent(s.path); s:load()
    elseif it:sub(-1) == "/" then s.path = join(s.path, it); s:load()
    else openEditor(join(s.path, it)) end
  end,
  scroll = function(s, mx, my, d)
    s.scroll = clamp(s.scroll - d, 0, math.max(0, #s.items - (s.h - 2)))
  end,
}

local Editor = {
  init = function(s) s.lines = {""}; s.cx, s.cy, s.top, s.left = 1, 1, 0, 0; s.msg = "Ctrl+S - сохранить" end,
  loadFile = function(s, p)
    s.file = p
    local d = readFile(p) or ""
    s.lines = {}
    for l in (d .. "\n"):gmatch("(.-)\r?\n") do s.lines[#s.lines + 1] = l end
    if #s.lines == 0 then s.lines = {""} end
  end,
  draw = function(s, x, y, w, h)
    local rows = h - 1
    if s.cy <= s.top then s.top = s.cy - 1 elseif s.cy > s.top + rows then s.top = s.cy - rows end
    if s.cx <= s.left then s.left = s.cx - 1 elseif s.cx > s.left + w then s.left = s.cx - w end
    for r = 1, rows do
      local line = s.lines[s.top + r]
      if line then text(x, y + r - 1, sub(line, s.left + 1, s.left + w), C.wtxt, C.win) end
    end
    local ch = sub(s.lines[s.cy], s.cx, s.cx); if ch == "" then ch = " " end
    text(x + s.cx - 1 - s.left, y + s.cy - 1 - s.top, ch, 0xFFFFFF, C.panel)
    rect(x, y + h - 1, w, 1, C.bar)
    text(x, y + h - 1, clip(" " .. s.msg .. "  | " .. s.cy .. ":" .. s.cx, w), C.wtxt, C.bar)
  end,
  key = function(s, char, code)
    local L, line = s.lines, s.lines[s.cy]
    if ctrl and code == 31 then
      s.file = s.file or "/untitled.txt"
      s.msg = writeFile(s.file, table.concat(L, "\n")) and ("Сохранено: " .. s.file) or "Ошибка записи!"
    elseif code == 28 then
      L[s.cy] = sub(line, 1, s.cx - 1); table.insert(L, s.cy + 1, sub(line, s.cx)); s.cy = s.cy + 1; s.cx = 1
    elseif code == 14 then
      if s.cx > 1 then L[s.cy] = sub(line, 1, s.cx - 2) .. sub(line, s.cx); s.cx = s.cx - 1
      elseif s.cy > 1 then local p = L[s.cy - 1]; s.cx = len(p) + 1; L[s.cy - 1] = p .. line; table.remove(L, s.cy); s.cy = s.cy - 1 end
    elseif code == 211 then
      if s.cx <= len(line) then L[s.cy] = sub(line, 1, s.cx - 1) .. sub(line, s.cx + 1)
      elseif s.cy < #L then L[s.cy] = line .. L[s.cy + 1]; table.remove(L, s.cy + 1) end
    elseif code == 200 then s.cy = math.max(1, s.cy - 1)
    elseif code == 208 then s.cy = math.min(#L, s.cy + 1)
    elseif code == 203 then
      if s.cx > 1 then s.cx = s.cx - 1 elseif s.cy > 1 then s.cy = s.cy - 1; s.cx = len(L[s.cy]) + 1 end
    elseif code == 205 then
      if s.cx <= len(line) then s.cx = s.cx + 1 elseif s.cy < #L then s.cy = s.cy + 1; s.cx = 1 end
    elseif code == 199 then s.cx = 1
    elseif code == 207 then s.cx = len(line) + 1
    elseif code == 15 then L[s.cy] = sub(line, 1, s.cx - 1) .. "  " .. sub(line, s.cx); s.cx = s.cx + 2
    elseif char >= 32 and not ctrl then
      L[s.cy] = sub(line, 1, s.cx - 1) .. unicode.char(char) .. sub(line, s.cx); s.cx = s.cx + 1
    end
    s.cx = math.min(s.cx, len(L[s.cy]) + 1)
  end,
}

local function say(s, t)
  for l in (tostring(t) .. "\n"):gmatch("(.-)\n") do s.out[#s.out + 1] = l end
  while #s.out > 200 do table.remove(s.out, 1) end
end

local function sh(s, line)
  say(s, "$ " .. line)
  local cmd, arg = line:match("^%s*(%S+)%s*(.*)$")
  if not cmd then return end
  local path = arg == "" and s.cwd or join(s.cwd, arg)
  if cmd == "help" then say(s, "ls cd cat mkdir rm echo lua free clear reboot shutdown")
  elseif cmd == "ls" then say(s, table.concat(fs.list(path) or {}, "  "))
  elseif cmd == "cd" then
    if arg == ".." then s.cwd = parent(s.cwd)
    elseif arg == "" then s.cwd = "/"
    elseif fs.isDirectory(path) then s.cwd = path else say(s, "нет такой папки") end
  elseif cmd == "cat" then say(s, readFile(path) or "не удалось прочитать")
  elseif cmd == "mkdir" then fs.makeDirectory(path)
  elseif cmd == "rm" then fs.remove(path)
  elseif cmd == "echo" then say(s, arg)
  elseif cmd == "clear" then s.out = {}
  elseif cmd == "free" then say(s, math.floor(computer.freeMemory() / 1024) .. " / " .. math.floor(computer.totalMemory() / 1024) .. " KB")
  elseif cmd == "lua" then
    local f, e = load("return " .. arg, "=lua", "t", _ENV)
    if not f then f, e = load(arg, "=lua", "t", _ENV) end
    if not f then say(s, e) else
      local ok, r = pcall(f); say(s, ok and tostring(r) or ("ошибка: " .. tostring(r))) end
  elseif cmd == "reboot" then computer.shutdown(true)
  elseif cmd == "shutdown" then computer.shutdown()
  else say(s, cmd .. ": команда не найдена") end
end

local Terminal = {
  init = function(s) s.out, s.cwd, s.input = {"Терминал XFCE-Lite. Введите help."}, "/", "" end,
  draw = function(s, x, y, w, h)
    rect(x, y, w, h, C.term)
    local rows = h - 1
    local start = math.max(1, #s.out - rows + 1)
    for i = start, #s.out do text(x, y + i - start, clip(s.out[i], w), C.ptxt, C.term) end
    local n = math.min(#s.out, rows)
    text(x, y + n, clip("user@oc:" .. s.cwd .. "$ " .. s.input .. "█", w), 0x8AE234, C.term)
  end,
  key = function(s, char, code)
    if code == 28 then local l = s.input; s.input = ""; sh(s, l)
    elseif code == 14 then s.input = sub(s.input, 1, len(s.input) - 1)
    elseif char >= 32 and not ctrl then s.input = s.input .. unicode.char(char) end
  end,
}

local About = {
  draw = function(s, x, y, w, h)
    local t = {"XFCE-Lite OS", "Лёгкий ремейк в духе MineOS", "",
      "Разрешение: " .. W .. "x" .. H,
      "ОЗУ: " .. math.floor(computer.freeMemory() / 1024) .. " / " .. math.floor(computer.totalMemory() / 1024) .. " KB",
      "Энергия: " .. math.floor(computer.energy()) .. " / " .. math.floor(computer.maxEnergy()),
      "Аптайм: " .. math.floor(computer.uptime()) .. " c"}
    for i, l in ipairs(t) do text(x + 1, y + i, clip(l, w - 2), C.wtxt, C.win) end
  end,
}

function openEditor(p)
  local w = newWin("Редактор", 70, 22, Editor)
  if p then w:loadFile(p); w.title = "Редактор - " .. p:match("[^/]*$") end
end
local function openFiles() newWin("Файлы", 44, 18, Files) end
local function openTerm() newWin("Терминал", 70, 20, Terminal) end
local function openAbout() newWin("О системе", 40, 11, About) end

---------------------------------------------------------------- рабочий стол
local icons = {
  {"Файлы", 0xE5A50A, "DIR", openFiles},
  {"Терминал", 0x2E3436, "$_", openTerm},
  {"Редактор", 0x73B35A, "TXT", function() openEditor() end},
  {"О системе", 0x8F6BB8, "(i)", openAbout},
}
local selIcon, lastIcon, lastT = nil, nil, 0
local menu = {
  {"Файловый менеджер", openFiles}, {"Терминал", openTerm},
  {"Текстовый редактор", function() openEditor() end}, {"О системе", openAbout},
  {"Перезагрузка", function() computer.shutdown(true) end},
  {"Выключение", function() computer.shutdown() end},
}
local MW = 24

local function drawPanel()
  rect(1, 1, W, 1, C.panel)
  text(2, 1, " ▼ Приложения ", C.ptxt, menuOpen and C.sel or C.panel)
  local x = 18
  for i, w in ipairs(wins) do
    local lb = clip(w.title, 12)
    text(x, 1, " " .. lb .. " ", C.ptxt, i == #wins and 0x555753 or C.panel)
    w.tx, w.tw = x, len(lb) + 2
    x = x + w.tw + 1
  end
  if lastErr then text(x + 1, 1, clip(lastErr, W - x - 8), 0xFF6666, C.panel) end
  text(W - 5, 1, os.date("%H:%M"), C.ptxt, C.panel)
end

local function redraw()
  rect(1, 2, W, H - 1, C.desk)
  for i, ic in ipairs(icons) do
    local x, y = 3, 3 + (i - 1) * 5
    rect(x, y, 7, 3, ic[2])
    text(x + 2, y + 1, ic[3], 0xFFFFFF, ic[2])
    text(x, y + 3, clip(ic[1], 9), 0xFFFFFF, selIcon == i and C.sel or C.desk)
  end
  for i, w in ipairs(wins) do
    rect(w.x, w.y, w.w, 1, i == #wins and C.title or C.titleOff)
    text(w.x + 1, w.y, clip(w.title, w.w - 6), C.ttxt, i == #wins and C.title or C.titleOff)
    text(w.x + w.w - 3, w.y, " × ", C.ttxt, C.btnX)
    rect(w.x, w.y + 1, w.w, w.h - 1, C.win)
    if w.draw then w:draw(w.x, w.y + 1, w.w, w.h - 1) end
  end
  if menuOpen then
    for i, m in ipairs(menu) do text(2, 1 + i, clip(" " .. m[1] .. string.rep(" ", MW), MW), C.wtxt, C.menu) end
  end
  drawPanel()
end

local function raise(i) local w = table.remove(wins, i); wins[#wins + 1] = w; return w end

local function touch(x, y, btn)
  local was = menuOpen; menuOpen = false
  if was and x >= 2 and x < 2 + MW and y >= 2 and y <= 1 + #menu then menu[y - 1][2](); return end
  if y == 1 then
    if x >= 2 and x <= 16 then menuOpen = not was; return end
    for i, w in ipairs(wins) do
      if w.tx and x >= w.tx and x < w.tx + w.tw then raise(i); return end
    end
    return
  end
  for i = #wins, 1, -1 do
    local w = wins[i]
    if x >= w.x and x < w.x + w.w and y >= w.y and y < w.y + w.h then
      raise(i)
      if y == w.y then
        if x >= w.x + w.w - 3 then table.remove(wins, #wins) else drag = {w = w, dx = x - w.x, dy = y - w.y} end
      elseif w.click then w:click(x, y, btn) end
      return
    end
  end
  selIcon = nil
  for i, ic in ipairs(icons) do
    local ix, iy = 3, 3 + (i - 1) * 5
    if x >= ix and x <= ix + 8 and y >= iy and y <= iy + 3 then
      selIcon = i
      if lastIcon == i and computer.uptime() - lastT < 0.6 then ic[4](); lastIcon = nil else lastIcon, lastT = i, computer.uptime() end
    end
  end
end

---------------------------------------------------------------- главный цикл
redraw()
while true do
  local e, _, a, b, c = computer.pullSignal(1)
  local ok, err = pcall(function()
    if e == "touch" then touch(a, b, c)
    elseif e == "drag" and drag then
      drag.w.x = clamp(a - drag.dx, 1, W - drag.w.w + 1)
      drag.w.y = clamp(b - drag.dy, 2, H - drag.w.h + 1)
    elseif e == "drop" then drag = nil
    elseif e == "key_down" then
      if b == 29 or b == 157 then ctrl = true
      else local w = wins[#wins]; if w and w.key then w:key(a, b) end end
    elseif e == "key_up" and (b == 29 or b == 157) then ctrl = false
    elseif e == "scroll" then
      for i = #wins, 1, -1 do
        local w = wins[i]
        if a >= w.x and a < w.x + w.w and b >= w.y and b < w.y + w.h then
          if w.scroll then w:scroll(a, b, c) end
          break
        end
      end
    end
    redraw()
  end)
  if not ok then lastErr = tostring(err); pcall(redraw) end
end
