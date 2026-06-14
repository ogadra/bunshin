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

-- configure は STACK_NAME / INTERNAL_DOMAIN 未設定を許さず起動を失敗させる
check("configure rejects missing stack", not pcall(core.configure, nil, "example.com"))
check("configure rejects empty stack", not pcall(core.configure, "", "example.com"))
check("configure rejects missing domain", not pcall(core.configure, "ap-northeast-1", nil))

-- decide_arrival: cookie 無 / 自stack宛 はローカル解決
check("arrival nil without cookie", core.decide_arrival(nil, "ap-northeast-1", "example.com") == nil)
check("arrival nil for own stack", core.decide_arrival("ap-northeast-1_x", "ap-northeast-1", "example.com") == nil)

-- decide_arrival: 別stack宛は所属stackの内部ALBへ転送
r = core.decide_arrival("ap-northeast-3_deadbeef", "ap-northeast-1", "example.com")
check("arrival forwards foreign stack", r.forward_host == "ap-northeast-3.example.com" and r.exit == nil)

-- decide_arrival: 不正な prefix は 500 で遮断
r = core.decide_arrival("EVIL_x", "ap-northeast-1", "example.com")
check("arrival rejects invalid stack", r.exit == 500 and r.log ~= nil)

if failed > 0 then
    io.stderr:write(string.format("resolve_core: %d check(s) failed\n", failed))
    os.exit(1)
end
print("resolve_core: all checks passed")
