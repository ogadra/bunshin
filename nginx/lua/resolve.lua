-- broker /resolve をサブリクエストで呼び、session_id cookie からセッションを解決する。
-- brokerの実ステータスをそのままクライアントへ返す。
local core = require("resolve_core")

-- 所属stackが別なら、ローカルにセッションを持たない broker を叩かず宛先stackへ転送する。
local arrival = core.decide_arrival(ngx.var.cookie_session_id, core.own_stack(), core.internal_domain())
if arrival then
    if arrival.log then
        ngx.log(ngx.ERR, arrival.log)
    end
    if arrival.exit then
        return ngx.exit(arrival.exit)
    end
    ngx.var.forward_host = arrival.forward_host
    return ngx.exec("@forward")
end

local res = ngx.location.capture("/_resolve")
local action = core.decide(res)

if action.log then
    ngx.log(ngx.ERR, action.log)
end
if action.exit then
    -- broker のエラー透過 or 不正宛先の遮断。
    return ngx.exit(action.exit)
end

-- idle 枯渇時、broker のシグナルに従い次の stack へ転送し、残り候補を中継する。
if action.forward_host then
    ngx.var.forward_host = action.forward_host
    ngx.var.fwd_fallback_stack = action.fallback_stack
    ngx.var.fwd_fallback_remaining = action.fallback_remaining
    return ngx.exec("@forward")
end

ngx.var.runner_url = action.runner_url
if action.set_cookie then
    ngx.var.resolve_set_cookie = action.set_cookie
end
if action.reassigned then
    ngx.var.session_reassigned = action.reassigned
end
