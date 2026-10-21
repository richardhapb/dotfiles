rex.action{
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
