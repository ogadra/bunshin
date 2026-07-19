-- port-forward の {hex32}.{stack}.<internal_domain> Host から runner の :app_port
-- へ振り分ける access phase。所有 stack でなければ 404、broker が session を持って
-- いなければ 404、成功したら $pf_upstream を組み立てて proxy_pass に渡す。
local core = require("resolve_core")

local arrival = core.decide_app_arrival(ngx.var.host)
if arrival.exit then
    return ngx.exit(arrival.exit)
end

local res = ngx.location.capture("/_pf_resolve", {
    vars = { pf_hex = arrival.hex },
})

local decided = core.decide_app_resolve(res.status, res.header)
if decided.exit then
    return ngx.exit(decided.exit)
end

ngx.var.pf_upstream = decided.upstream
