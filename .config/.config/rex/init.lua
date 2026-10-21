rex.action {
  name  = "session_goto",
  title = "Go to Session by Index",
  args  = { index = "integer" },
  run   = function(ctx, args)
    local res, err = rex.call("session.list")
    if res == nil then error(err, 0) end
    local s = res.sessions and res.sessions[args.index]
    if s == nil then return end
    rex.client.queue("session.select", { session_id = s.session_id })
  end,
}

for i = 1, 9 do
  rex.bind("cmd+" .. i, "session_goto", { index = i })
end

rex.bind("alt+shift+p", "client.tab.previous")
rex.bind("alt+shift+n", "client.tab.next")

local NOTES_DIR = os.getenv("HOME") .. "/notes"
local NOTES_RATIO = 0.8

rex.action {
  name  = "notes_side",
  title = "Notes on the Side",
  run   = function(ctx)
    local view = rex.call("session.view", { session_id = ctx.session_id })
    local win
    for _, w in ipairs(view.windows) do
      if w.window_id == view.active_window_id then win = w end
    end
    if win == nil then return end

    for _, layer in ipairs(win.layers) do
      if layer.kind == "tiled" then
        for _, b in ipairs(layer.blocks) do
          if b.label == "notes" then
            rex.call("session.focus_block", { session_id = ctx.session_id, block_id = b.block_id })
            return
          end
        end
      end
    end

    local anchor = win.focused_block_id
    local res = rex.call("session.new_split", {
      session_id = ctx.session_id,
      window_id  = win.window_id,
      direction  = "horizontal",
      side       = "after",
      ratio      = NOTES_RATIO,
      focus      = true,
      layout     = {
        block = {
          flavor  = "com.superlogical.terminal.shell",
          label   = "notes",
          options = { command = { "nvim", NOTES_DIR .. "/inbox.md" }, cwd = NOTES_DIR },
        }
      },
    })

    -- The app resets a fresh split to 50/50 shortly after creation, and
    -- rex.sleep is not available in init.lua, so wait on a short process.
    rex.exec.start({ "sleep", "0.5" }):wait()
    rex.call("session.resize_pane", {
      session_id      = ctx.session_id,
      direction       = "horizontal",
      before_block_id = anchor,
      after_block_id  = res.block_ids[1],
      ratio           = NOTES_RATIO,
    })
  end,
}

rex.bind("ctrl+alt+shift+n", "notes_side")

local PASSTHROUGH = { nvim = true, vim = true }
local CTRL_BYTE = { left = "\8", down = "\10", up = "\11", right = "\12" }

rex.action {
  name  = "pane_nav",
  title = "Navigate Pane (nvim aware)",
  args  = { direction = "string" },
  run   = function(ctx, args)
    local view = rex.call("session.view", { session_id = ctx.session_id })
    local bid
    for _, w in ipairs(view.windows) do
      if w.window_id == view.active_window_id then bid = w.focused_block_id end
    end

    if bid then
      local p = rex.call("block.method", { session_id = ctx.session_id, block_id = bid, method = "process" })
      local fg = p and p.foreground and p.foreground.name
      if PASSTHROUGH[fg] then
        rex.call("block.method", {
          session_id = ctx.session_id,
          block_id = bid,
          method = "write",
          args = { data = CTRL_BYTE[args.direction] },
        })
        return
      end
    end

    rex.call("session.focus_direction", { session_id = ctx.session_id, direction = args.direction })
  end,
}

for key, dir in pairs({ ["ctrl+h"] = "left", ["ctrl+j"] = "down", ["ctrl+k"] = "up", ["ctrl+l"] = "right" }) do
  rex.bind(key, "pane_nav", { direction = dir })
end

-- Projects: one command-palette action per directory ("Project: <name>"),
-- which creates or switches to a session named after the directory.
local HOME = os.getenv("HOME")
local PROJECT_ROOTS = {
  HOME .. "/proj", HOME .. "/proj/cont", HOME .. "/dev", HOME .. "/plugins",
  HOME .. "/wip", HOME .. "/dotfiles/.config/.config",
}
local PROJECT_DIRS = { HOME .. "/dotfiles", HOME .. "/notes" }

rex.action{
  name  = "project_open",
  title = "Open Project",
  args  = { dir = "string" },
  run   = function(ctx, args)
    local label = args.dir:match("([^/]+)$"):gsub("%.", "_")
    local id
    for _, s in ipairs(rex.call("session.list").sessions or {}) do
      if s.label == label then id = s.session_id end
    end
    if id == nil then
      local res = rex.call("session.create", {
        label = label,
        initial_windows = { { layout = { block = {
          flavor  = "com.superlogical.terminal.shell",
          options = { cwd = args.dir },
        } } } },
      })
      id = res.session_id
    end
    rex.client.queue("session.select", { session_id = id })
  end,
}

local function project_dirs()
  local dirs, seen = {}, {}
  local function add(d)
    if not seen[d] then seen[d] = true; dirs[#dirs + 1] = d end
  end
  for _, d in ipairs(PROJECT_DIRS) do add(d) end
  for _, root in ipairs(PROJECT_ROOTS) do
    local res = rex.exec.start({ "find", root, "-mindepth", "1", "-maxdepth", "1", "-type", "d" }):wait()
    for d in (res.stdout or ""):gmatch("[^\n]+") do
      if not d:match("/%.[^/]*$") then add(d) end
    end
  end
  return dirs
end

local taken = {}
for _, dir in ipairs(project_dirs()) do
  local name = dir:match("([^/]+)$")
  local id = "project_" .. name:lower():gsub("[^%w]", "_")
  if not taken[id] then
    taken[id] = true
    rex.action{
      name  = id,
      title = "Project: " .. name,
      run   = function(ctx) return rex.invoke("project_open", { dir = dir }) end,
    }
  end
end
