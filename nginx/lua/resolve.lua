-- broker /resolve をサブリクエストで呼び、session_id cookie からセッションを解決する。
-- brokerの実ステータスをそのままクライアントへ返す。
local core = require("resolve_core")

local fallback_stack = ngx.var.relay_fallback_stack
local arrival = core.decide_arrival(
    ngx.var.cookie_session_id,
    core.own_stack(),
    core.stacks(),
    core.internal_domain(),
    fallback_stack
)
if arrival then
    if arrival.log then
        ngx.log(ngx.ERR, arrival.log)
    end
    if arrival.exit then
        return ngx.exit(arrival.exit)
    end
    ngx.var.forward_host = arrival.forward_host
    return ngx.exec("@forward_owner")
end

local res = ngx.location.capture("/_resolve")
local invalid = core.validate_resolve_response(res)
if invalid then
    if invalid.log then
        ngx.log(ngx.ERR, invalid.log)
    end
    return ngx.exit(invalid.exit)
end

local action = core.decide(res, core.stacks(), core.internal_domain())

if action.log then
    ngx.log(ngx.ERR, action.log)
end
if action.exit then
    -- broker のエラー透過 or 不正宛先の遮断。
    return ngx.exit(action.exit)
end

if action.forward_host then
    ngx.var.forward_host = action.forward_host
    ngx.var.fwd_fallback_stack = action.fallback_stack
    ngx.var.fwd_fallback_remaining = action.fallback_remaining
    return ngx.exec("@forward_fallback")
end

ngx.var.runner_url = action.runner_url
if action.set_cookie then
    ngx.var.resolve_set_cookie = action.set_cookie
end
if action.reassigned then
    ngx.var.session_reassigned = action.reassigned
end
