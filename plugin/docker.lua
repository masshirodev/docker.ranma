-- docker: containers as a screen.
--
-- leader D   (shift+d), `docker` in the palette, or ranma.emit("docker_open")
--            opens a screen of the containers (`docker ps -a`), running ones
--            first: each with its state, image, ports and how long it has
--            been up (or since it exited). On it:
--   enter  logs -f in a new pane         s  a shell in it (bash, else sh)
--   r      restart (asks)                x  stop (asks)
--   t      start a stopped one           i  inspect: the whole of
--   h      the next host (docker.hosts)     `docker inspect`, on a view
--   u      look again now
-- The list is fetched again every docker.refresh seconds, only while the
-- screen is open; nothing runs while it is closed.
--
-- Hosts: docker.hosts lists name=address pairs (`vps=ssh://vps`); `local`
-- is the docker the server's environment points at. `h` steps through them,
-- `docker [host]` opens on one. A pane opened for a remote container runs
-- `docker -H <address> …` there.
--
-- Panes (logs, shell) open beside the focused pane, in its workspace, as
-- `exec` does, named after the container.
--
-- Needs ranma 0.2.2 or newer, and the docker CLI.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Screens",
-- "Timers and processes", "Actions").

ranma.option("docker.hosts", {
  type = "string", default = "local",
  name = "Hosts", desc = "The hosts h steps through: `local`, and name=address pairs for docker -H (vps=ssh://vps), space-separated.",
})
ranma.option("docker.refresh", {
  type = "int", min = 1, max = 60, default = 3, slider = false,
  name = "Refresh", desc = "Seconds between two looks while the screen is open.",
})
ranma.option("docker.command", {
  type = "string", default = "docker",
  name = "Command", desc = "The docker CLI (podman works too, as it takes the same arguments).",
})

local function fail(err)
  ranma.toast("docker: " .. tostring(err), { urgent = true })
end

local function sh(word)
  return "'" .. word:gsub("'", "'\\''") .. "'"
end

-- Hosts ----------------------------------------------------------------------

local function hosts()
  local out = {}
  for pair in ranma.get("docker.hosts"):gmatch("%S+") do
    local name, addr = pair:match("^(.-)=(.+)$")
    out[#out + 1] = { name = name or pair, addr = addr }
  end
  if #out == 0 then out[1] = { name = "local" } end
  return out
end

local function host_named(name)
  for _, h in ipairs(hosts()) do
    if h.name == name then return h end
  end
end

-- The docker command's words, for one host.
local function argv(host, ...)
  local out = { ranma.get("docker.command") }
  if host.addr then
    out[#out + 1] = "-H"
    out[#out + 1] = host.addr
  end
  for _, a in ipairs({ ... }) do out[#out + 1] = a end
  return out
end

local function line(words)
  local q = {}
  for _, w in ipairs(words) do q[#q + 1] = sh(w) end
  return table.concat(q, " ")
end

local function docker(host, args, done, timeout)
  ranma.spawn(argv(host, table.unpack(args)), {
    timeout = timeout or 20,
    on_exit = function(r)
      if r.error then return done(nil, r.error) end
      if r.code ~= 0 then
        local why = (r.stderr or ""):gsub("%s+$", "")
        return done(nil, why ~= "" and why or ("exit " .. tostring(r.code)))
      end
      done(r.stdout or "")
    end,
  })
end

-- The list ---------------------------------------------------------------------

local function containers(host, done)
  docker(host, { "ps", "-a", "--no-trunc", "--format", "{{json .}}" }, function(out, err)
    if not out then return done(nil, err) end
    local list = {}
    for l in out:gmatch("[^\n]+") do
      local ok, c = pcall(ranma.json.decode, l)
      if ok and type(c) == "table" then list[#list + 1] = c end
    end
    table.sort(list, function(a, b)
      local ra, rb = a.State == "running", b.State == "running"
      if ra ~= rb then return ra end
      return (a.Names or "") < (b.Names or "")
    end)
    done(list)
  end, 15)
end

local ROLE = { running = "accent", restarting = "urgent", paused = "dim", exited = "dim", dead = "urgent", created = "dim" }
local GLYPH = { running = "●", restarting = "↻", paused = "‖", exited = "○", dead = "✗", created = "·" }

-- Ports as docker prints them, shorter: 127.0.0.1:5435->5432/tcp is :5435→5432.
local function ports(s)
  if not s or s == "" then return nil end
  local seen, out = {}, {}
  for part in s:gmatch("[^,]+") do
    part = part:gsub("^%s+", "")
    local host_port, cport = part:match(":(%d+)%->(%d+)")
    local text = host_port and (":" .. host_port .. "→" .. cport) or part:gsub("/tcp$", "")
    if not seen[text] then
      seen[text] = true
      out[#out + 1] = text
    end
  end
  return table.concat(out, " ")
end

local screen = { s = nil, host = nil, list = {}, timer = nil, pane = nil }

local function by_id(id)
  for _, c in ipairs(screen.list) do
    if c.ID == id then return c end
  end
end

local function name(c)
  return (c.Names or c.ID or "?"):match("^[^,]+")
end

local function body()
  local out = {}
  local running, stopped = {}, {}
  for _, c in ipairs(screen.list) do
    if c.State == "running" or c.State == "restarting" or c.State == "paused" then
      running[#running + 1] = c
    else
      stopped[#stopped + 1] = c
    end
  end
  local function rows(list)
    for _, c in ipairs(list) do
      local st = c.State or "?"
      local p = ports(c.Ports)
      local detail = {
        { "facts",
          { "image", c.Image or "" },
          { "state", c.Status or st, ROLE[st] },
          { "ports", p or "none" },
          { "id", (c.ID or ""):sub(1, 12) },
        },
      }
      if c.Command and c.Command ~= "" then detail[#detail + 1] = { "text", c.Command, "dim", max = 2 } end
      out[#out + 1] = {
        "row", id = c.ID, name = name(c),
        mark = { GLYPH[st] or "?", ROLE[st] or "normal" },
        note = c.Image,
        value = { c.Status or st, ROLE[st] },
        detail = detail,
      }
    end
  end
  if #running > 0 then
    out[#out + 1] = { "heading", "running", count = #running }
    rows(running)
  end
  if #stopped > 0 then
    out[#out + 1] = { "heading", "stopped", count = #stopped }
    rows(stopped)
  end
  return out
end

local function status()
  local n = 0
  for _, c in ipairs(screen.list) do
    if c.State == "running" then n = n + 1 end
  end
  return n .. " running · " .. #screen.list .. " in all"
end

local function redraw()
  if not screen.s then return end
  screen.s:set { body = body(), count = status() }
end

local function refresh(after)
  local host = screen.host
  containers(host, function(list, err)
    if not screen.s or screen.host ~= host then return end
    if not list then
      screen.s:set { status = { err, "urgent" } }
      return
    end
    screen.list = list
    screen.s:set { status = false }
    redraw()
    if after then after() end
  end)
end

local function close()
  if screen.timer then ranma.cancel(screen.timer) end
  screen.timer = nil
  if screen.s then screen.s:close() end
  screen.s = nil
end

-- Panes ---------------------------------------------------------------------------

local pending_title = nil   -- what the next pane opened is named

-- `hold`: the pane stays when the command ends, however it ends (the logs
-- of a stopped container end at once); else only when it failed.
local function open_pane(words, title, hold)
  local s = screen
  close()
  if s.pane and s.pane:alive() then s.pane:focus() end
  pending_title = title
  ranma.defer(3000, function() pending_title = nil end)
  local after = hold
    and [[; s=$?; printf '\n[ended, %s] Enter closes this pane. ' "$s"; read _]]
    or [[ || { s=$?; printf '\nexited %s; Enter closes this pane. ' "$s"; read _; }]]
  ranma.action("exec " .. line(words) .. after)
end

-- A pane opened for a container is named after it.
ranma.on("pane_open", function(ev)
  if not pending_title then return end
  local p = ranma.pane(ev.pane)
  if p then p:rename(pending_title) end
  pending_title = nil
end)

local function logs(c)
  open_pane(argv(screen.host, "logs", "-f", "--tail", "500", c.ID), "logs:" .. name(c), true)
end

local function shell(c)
  if c.State ~= "running" then return fail(name(c) .. " is not running") end
  local words = argv(screen.host, "exec", "-it", c.ID, "sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh")
  open_pane(words, "sh:" .. name(c))
end

-- One of docker's verbs on a container, after asking when it is destructive.
local function act(c, verb, ask)
  local function go()
    screen.s:set { status = { verb .. " " .. name(c) .. "…", "dim" } }
    docker(screen.host, { verb, c.ID }, function(_, err)
      if err then return fail(verb .. " " .. name(c) .. ": " .. err) end
      ranma.toast("docker: " .. verb .. " " .. name(c) .. " done")
      if screen.s then refresh() end
    end, 60)
  end
  if not ask then return go() end
  screen.s:ask {
    blocks = { { "text", verb .. " " .. name(c) .. "?", strong = true },
               { "text", (c.Image or "") .. " · " .. (c.Status or ""), "dim" } },
    keys = {
      { "y", verb, function() screen.s:ask(nil) go() end, role = "urgent" },
      { "esc", "keep it", function() screen.s:ask(nil) end },
    },
  }
end

local function inspect(c)
  docker(screen.host, { "inspect", c.ID }, function(out, err)
    if not out then return fail(err) end
    if not screen.s then return end
    local lines = {}
    for l in out:gmatch("[^\n]*") do lines[#lines + 1] = l end
    screen.s:push { body = { { "log", lines = lines } }, subtitle = name(c), count = #lines .. " lines" }
  end)
end

local function with(fn)
  return function(id)
    local c = id and by_id(id)
    if c then fn(c) end
  end
end

local function open_screen(arg)
  local want = arg and arg:match("^%s*(%S+)")
  local host = want and host_named(want)
  if want and not host then return fail("no host " .. want .. " in docker.hosts") end
  screen.pane = ranma.pane()
  close()
  screen.host = host or hosts()[1]
  screen.list = {}
  screen.s = ranma.screen {
    title = "docker · " .. screen.host.name,
    chip = "DOCKER",
    filter = "names",
    detail = 6,
    empty = "no containers",
    body = {},
    keys = {
      { "enter", "logs", with(logs) },
      { "s", "shell", with(shell) },
      { "r", "restart", with(function(c) act(c, "restart", true) end) },
      { "x", "stop", with(function(c) act(c, "stop", true) end) },
      { "t", "start", with(function(c) act(c, "start", false) end) },
      { "i", "inspect", with(inspect) },
      { "h", "host", function()
        local list = hosts()
        local i = 1
        for k, h in ipairs(list) do if h.name == screen.host.name then i = k end end
        screen.host = list[i % #list + 1]
        screen.list = {}
        screen.s:set { title = "docker · " .. screen.host.name }
        redraw()
        refresh()
      end },
      { "u", "update", function() refresh() end },
    },
    card = {
      { "enter", "docker logs -f in a new pane" },
      { "s", "a shell in the container (bash, else sh), in a new pane", "running" },
      { "r", "restart it, after asking" },
      { "x", "stop it, after asking", "running" },
      { "t", "start it", "stopped" },
      { "i", "docker inspect, whole" },
      { "h", "the next host in docker.hosts" },
      { "u", "look again now" },
    },
    options = true,
    group = "docker",
    on_close = function()
      if screen.timer then ranma.cancel(screen.timer) end
      screen.timer = nil
      screen.s = nil
    end,
  }
  refresh()
  screen.timer = ranma.every(ranma.get("docker.refresh") * 1000, function()
    if screen.s then refresh() end
  end)
end

ranma.command("docker", open_screen, {
  desc = "the containers, as a screen",
  args = "[host]",
  complete = function()
    local out = {}
    for _, h in ipairs(hosts()) do out[#out + 1] = h.name end
    return out
  end,
})
ranma.on("user:docker_open", function(data) open_screen(type(data) == "string" and data or nil) end)

-- WM mode ends as the screen opens: it has the keyboard from there.
ranma.bind("shift+d", function() open_screen() end, { desc = "docker", group = "plugins", exit = true })
