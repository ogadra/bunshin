-- resolve_core.decide の分岐テスト。openresty イメージ内で luajit で実行する:
--   luajit /usr/local/openresty/nginx/lua/resolve_core_test.lua
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

-- 200 + 不正 X-Runner-Url は 500 で遮断 (SSRF ガード)。各種不正形を網羅。
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
    ["Set-Cookie"] = "runner_id=abc; Path=/",
    ["X-Session-Reassigned"] = "true",
} })
check("propagates set-cookie", r.set_cookie == "runner_id=abc; Path=/")
check("propagates reassigned", r.reassigned == "true")

-- 複数 Set-Cookie (capture はテーブルで返す) を文字列へ畳む
r = core.decide({ status = 200, header = {
    ["X-Runner-Url"] = "http://runner-1:3000",
    ["Set-Cookie"] = { "a=1", "b=2" },
} })
check("joins multiple set-cookie", r.set_cookie == "a=1, b=2")

if failed > 0 then
    io.stderr:write(string.format("resolve_core: %d check(s) failed\n", failed))
    os.exit(1)
end
print("resolve_core: all checks passed")
