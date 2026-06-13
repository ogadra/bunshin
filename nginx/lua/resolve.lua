-- broker /resolve をサブリクエストで呼び、session_id cookie からセッションを解決する。
-- brokerの実ステータスをそのままクライアントへ返す。
local core = require("resolve_core")

local res = ngx.location.capture("/_resolve")
local action = core.decide(res)

if action.log then
    ngx.log(ngx.ERR, action.log)
end
if action.exit then
    -- broker のエラー透過 or 不正宛先の遮断。
    return ngx.exit(action.exit)
end

ngx.var.runner_url = action.runner_url
if action.set_cookie then
    ngx.var.resolve_set_cookie = action.set_cookie
end
if action.reassigned then
    ngx.var.session_reassigned = action.reassigned
end
