-- resolve_core.decide の分岐テスト。
package.path = "/usr/local/openresty/nginx/lua/?.lua;" .. package.path
local core = require("resolve_core")

local failed = 0
local function check(name, cond)
    if not cond then
        failed = failed + 1
        io.stderr:write("FAIL " .. name .. "\n")
    end
end

-- broker 非 2xx はそのステータスを保持して終了 (503/500 透過)
local r = core.decide({ status = 503, header = {} })
check("503 transparency", r.exit == 503 and r.runner_url == nil)

r = core.decide({ status = 500, header = {} })
check("500 transparency", r.exit == 500)

-- 200 + 不正 X-Runner-Url は 500 で遮断
for _, bad in ipairs({ "http://evil/path", "https://h:3000", "http://h:", "", "//h" }) do
    r = core.decide({ status = 200, header = { ["X-Runner-Url"] = bad } })
    check("ssrf guard rejects " .. bad, r.exit == 500 and r.log ~= nil)
end

-- 200 + X-Runner-Url ヘッダ欠落 (nil) も 500
r = core.decide({ status = 200, header = {} })
check("missing X-Runner-Url", r.exit == 500)

-- 正常: runner へ proxy。exit せず宛先を返す。ヘッダ不在時は set_cookie/reassigned を伝播しない。
r = core.decide({ status = 200, header = { ["X-Runner-Url"] = "http://runner-1:3000" } })
check("valid proxies", r.exit == nil and r.runner_url == "http://runner-1:3000")
check("no set-cookie when absent", r.set_cookie == nil)
check("no reassigned when absent", r.reassigned == nil)

-- Set-Cookie / X-Session-Reassigned の伝播
r = core.decide({ status = 200, header = {
    ["X-Runner-Url"] = "http://runner-1:3000",
    ["Set-Cookie"] = "session_id=abc; Path=/",
    ["X-Session-Reassigned"] = "true",
} })
check("propagates set-cookie", r.set_cookie == "session_id=abc; Path=/")
check("propagates reassigned", r.reassigned == "true")

-- 複数 Set-Cookie (capture はテーブルで返す) を文字列へ畳む
r = core.decide({ status = 200, header = {
    ["X-Runner-Url"] = "http://runner-1:3000",
    ["Set-Cookie"] = { "a=1", "b=2" },
} })
check("joins multiple set-cookie", r.set_cookie == "a=1, b=2")

-- cookie_stack は session_id "<stack>_<hex>" の prefix を返す
check("cookie_stack extracts prefix", core.cookie_stack("ap-northeast-1_deadbeef") == "ap-northeast-1")
check("cookie_stack nil for non-string", core.cookie_stack(nil) == nil)
check("cookie_stack nil without underscore", core.cookie_stack("nounderscore") == nil)
check("cookie_stack nil for empty prefix", core.cookie_stack("_abc") == nil)

-- host_of は region 形の stack のみ <stack>.<domain> を組み立てる
check("host_of builds host", core.host_of("ap-northeast-3", "example.com") == "ap-northeast-3.example.com")
check("host_of rejects underscore", core.host_of("ap_northeast", "example.com") == nil)
check("host_of rejects uppercase", core.host_of("AP-NORTHEAST-3", "example.com") == nil)
check("host_of rejects path chars", core.host_of("../evil", "example.com") == nil)
check("host_of rejects empty domain", core.host_of("ap-northeast-3", "") == nil)
check("host_of rejects nil stack", core.host_of(nil, "example.com") == nil)

-- decide_arrival: 自stack/domain 未設定なら転送しない (env 未設定の現挙動維持)
check("arrival nil when stack unset", core.decide_arrival("ap-northeast-3_x", "", "example.com") == nil)
check("arrival nil when domain unset", core.decide_arrival("ap-northeast-3_x", "ap-northeast-1", "") == nil)

-- decide_arrival: cookie 無 / 自stack宛 はローカル解決
check("arrival nil without cookie", core.decide_arrival(nil, "ap-northeast-1", "example.com") == nil)
check("arrival nil for own stack", core.decide_arrival("ap-northeast-1_x", "ap-northeast-1", "example.com") == nil)

-- decide_arrival: 別stack宛は所属stackの内部ALBへ転送
r = core.decide_arrival("ap-northeast-3_deadbeef", "ap-northeast-1", "example.com")
check("arrival forwards foreign stack", r.forward_host == "ap-northeast-3.example.com" and r.exit == nil)

-- decide_arrival: 不正な prefix は 500 で遮断
r = core.decide_arrival("EVIL_x", "ap-northeast-1", "example.com")
check("arrival rejects invalid stack", r.exit == 500 and r.log ~= nil)

-- decide_resolve: 503 + X-Fallback-Stack は次stackの内部ALBへ転送し残り候補を中継
r = core.decide_resolve({ status = 503, header = {
    ["X-Fallback-Stack"]     = "ap-northeast-3",
    ["X-Fallback-Remaining"] = "ap-northeast-2",
} }, "example.com")
check("fallback forwards next stack", r.forward_host == "ap-northeast-3.example.com")
check("fallback relays stack", r.fallback_stack == "ap-northeast-3")
check("fallback relays remaining", r.fallback_remaining == "ap-northeast-2")

-- decide_resolve: 残り候補が無ければ空文字で中継 (ヘッダ削除)
r = core.decide_resolve({ status = 503, header = { ["X-Fallback-Stack"] = "ap-northeast-3" } }, "example.com")
check("fallback empty remaining", r.forward_host == "ap-northeast-3.example.com" and r.fallback_remaining == "")

-- decide_resolve: 不正な fallback stack は 503 で遮断 (転送しない)
r = core.decide_resolve({ status = 503, header = { ["X-Fallback-Stack"] = "EVIL" } }, "example.com")
check("fallback rejects invalid stack", r.exit == 503 and r.log ~= nil and r.forward_host == nil)

-- decide_resolve: X-Fallback-Stack 無し/空 の 503 は終端 (転送しない)
r = core.decide_resolve({ status = 503, header = {} }, "example.com")
check("fallback terminal without header", r.exit == 503 and r.forward_host == nil)
r = core.decide_resolve({ status = 503, header = { ["X-Fallback-Stack"] = "" } }, "example.com")
check("fallback terminal on empty header", r.exit == 503 and r.forward_host == nil)

-- decide_resolve: 200/runner は従来どおり (回帰)
r = core.decide_resolve({ status = 200, header = { ["X-Runner-Url"] = "http://runner-1:3000" } }, "example.com")
check("resolve still proxies runner", r.runner_url == "http://runner-1:3000" and r.forward_host == nil)

if failed > 0 then
    io.stderr:write(string.format("resolve_core: %d check(s) failed\n", failed))
    os.exit(1)
end
print("resolve_core: all checks passed")
