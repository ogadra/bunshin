-- broker /resolve をサブリクエストで呼び、runner_id cookie からセッションを解決する。
-- auth_request の代替実装。auth_request はサブリクエストの非 2xx を 401/403/500 に潰すが、
-- ここでは broker の実ステータス (例: idle runner 無しの 503) をそのままクライアントへ返す。
-- 判定ロジックは resolve_core (純関数) に切り出し、ここでは ngx 副作用の適用のみ行う。
local core = require("resolve_core")

local res = ngx.location.capture("/_resolve")
local action = core.decide(res)

if action.log then
    ngx.log(ngx.ERR, action.log)
end
if action.exit then
    -- broker のエラー透過 or 不正宛先の遮断。JSON ボディは errors.conf の error_page が描画する
    -- (runner 由来のエラーは本流 proxy_pass がそのまま透過するため error_page では捕まらない)。
    return ngx.exit(action.exit)
end

ngx.var.runner_url = action.runner_url
if action.set_cookie then
    ngx.var.resolve_set_cookie = action.set_cookie
end
if action.reassigned then
    ngx.var.session_reassigned = action.reassigned
end
