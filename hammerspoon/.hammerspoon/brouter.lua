-- brouter — route http(s) URLs to specific Brave profiles.
-- Reads ~/.config/brouter/rules.json and opens each URL in the matching
-- Brave profile. Simple substring match on the host; no regex.
--
-- Make Hammerspoon the default browser once (prompts the system dialog):
--   hs -c 'hs.urlevent.setDefaultHandler("http")'
-- Then every clicked link flows through httpCallback below.

local CONFIG = os.getenv("HOME") .. "/.config/brouter/rules.json"
local BRAVE = "Brave Browser"

local function loadConfig()
  local cfg = hs.json.read(CONFIG)
  if not cfg or not cfg.default_profile then
    return { rules = {}, default_profile = "Default" }
  end
  return cfg
end

local function profileFor(host, cfg)
  host = host or ""
  for _, rule in ipairs(cfg.rules or {}) do
    -- Lua-pattern match (not full regex): supports classes/anchors/quantifiers.
    -- Note: "." is a wildcard here, so "checkr.com" also matches "checkrXcom";
    -- write "checkr%.com" for a literal dot, "%.checkr%.com$" to anchor the TLD.
    if rule.match and host:find(rule.match) then
      return rule.profile or cfg.default_profile
    end
  end
  return cfg.default_profile
end

hs.urlevent.httpCallback = function(_scheme, host, _params, fullURL, _senderPID)
  local cfg = loadConfig()
  local profile = profileFor(host, cfg)
  hs.task.new("/usr/bin/open", nil, {
    "-na", BRAVE, "--args",
    "--profile-directory=" .. profile,
    fullURL,
  }):start()
end
