-- resolve_core の分岐テスト。
package.path = "/usr/local/openresty/nginx/lua/?.lua;" .. package.path
local core = require("resolve_core")

local STACKS = { ["ap-northeast-1"] = true, ["ap-northeast-3"] = true }

local failed = 0
local function check(name, cond)
    if not cond then
        failed = failed + 1
        io.stderr:write("FAIL " .. name .. "\n")
    end
end

-- broker 非 2xx はそのステータスを保持して終了 (503/500 透過)
local r = core.decide({ status = 503, header = {} }, STACKS, "example.com")
check("503 transparency exit", r.exit == 503)
check("503 transparency no runner", r.runner_url == nil)

r = core.decide({ status = 500, header = {} }, STACKS, "example.com")
check("500 transparency", r.exit == 500)

-- 200 + 不正 X-Runner-Url は 500 で遮断
for _, bad in ipairs({ "http://evil/path", "https://h:3000", "http://h:", "", "//h" }) do
    r = core.decide({ status = 200, header = { ["X-Runner-Url"] = bad } }, STACKS, "example.com")
    check("ssrf guard exit " .. bad, r.exit == 500)
    check("ssrf guard log " .. bad, r.log ~= nil)
end

-- 200 + X-Runner-Url ヘッダ欠落 (nil) も 500
r = core.decide({ status = 200, header = {} }, STACKS, "example.com")
check("missing X-Runner-Url", r.exit == 500)

-- 正常: runner へ proxy。exit せず宛先を返す。ヘッダ不在時は set_cookie/reassigned を伝播しない。
r = core.decide({ status = 200, header = { ["X-Runner-Url"] = "http://runner-1:3000" } }, STACKS, "example.com")
check("valid proxy no exit", r.exit == nil)
check("valid proxy runner", r.runner_url == "http://runner-1:3000")
check("valid proxy no forward host", r.forward_host == nil)
check("no set-cookie when absent", r.set_cookie == nil)
check("no reassigned when absent", r.reassigned == nil)

-- Set-Cookie / X-Session-Reassigned の伝播
r = core.decide({ status = 200, header = {
    ["X-Runner-Url"] = "http://runner-1:3000",
    ["Set-Cookie"] = "session_id=abc; Path=/",
    ["X-Session-Reassigned"] = "true",
} }, STACKS, "example.com")
check("propagates set-cookie", r.set_cookie == "session_id=abc; Path=/")
check("propagates reassigned", r.reassigned == "true")

-- 複数 Set-Cookie (capture はテーブルで返す) を文字列へ畳む
r = core.decide({ status = 200, header = {
    ["X-Runner-Url"] = "http://runner-1:3000",
    ["Set-Cookie"] = { "a=1", "b=2" },
} }, STACKS, "example.com")
check("joins multiple set-cookie", r.set_cookie == "a=1, b=2")

-- cookie_stack は session_id "<stack>_<hex>" の prefix を返す
check("cookie_stack extracts prefix", core.cookie_stack("ap-northeast-1_deadbeef") == "ap-northeast-1")
check("cookie_stack nil for non-string", core.cookie_stack(nil) == nil)
check("cookie_stack nil without underscore", core.cookie_stack("nounderscore") == nil)
check("cookie_stack nil for empty prefix", core.cookie_stack("_abc") == nil)

-- host_of は allowlist 内の stack のみ <stack>.<domain> を組み立てる
check("host_of builds host", core.host_of("ap-northeast-3", STACKS, "example.com") == "ap-northeast-3.example.com")
check("host_of rejects unknown stack", core.host_of("ap-southeast-9", STACKS, "example.com") == nil)
check("host_of rejects injection value", core.host_of("evil.example.com/", STACKS, "example.com") == nil)
check("host_of rejects nil stack", core.host_of(nil, STACKS, "example.com") == nil)

-- configure は STACK_NAME / INTERNAL_DOMAIN / BUNSHIN_STACKS 未設定を許さず起動を失敗させる
check("configure rejects missing stack", not pcall(core.configure, nil, "example.com", "ap-northeast-1"))
check("configure rejects empty stack", not pcall(core.configure, "", "example.com", "ap-northeast-1"))
check("configure rejects missing domain", not pcall(core.configure, "ap-northeast-1", nil, "ap-northeast-1"))
check("configure rejects missing stacks", not pcall(core.configure, "ap-northeast-1", "example.com", nil))
check("configure rejects empty stacks", not pcall(core.configure, "ap-northeast-1", "example.com", ""))
check("configure rejects own stack outside allowlist", not pcall(core.configure, "ap-northeast-1", "example.com", "ap-northeast-3"))

-- decide_arrival: cookie 無 / 自stack宛 はローカル解決
check("arrival nil without cookie", core.decide_arrival(nil, "ap-northeast-1", STACKS, "example.com") == nil)
check("arrival nil for own stack", core.decide_arrival("ap-northeast-1_x", "ap-northeast-1", STACKS, "example.com") == nil)

-- decide_arrival: 別stack宛は所属stackの内部ALBへ転送
r = core.decide_arrival("ap-northeast-3_deadbeef", "ap-northeast-1", STACKS, "example.com")
check("arrival forwards foreign stack host", r.forward_host == "ap-northeast-3.example.com")
check("arrival forwards foreign stack no exit", r.exit == nil)

-- decide_arrival: allowlist 外の prefix は 500 で遮断
r = core.decide_arrival("evilhost_x", "ap-northeast-1", STACKS, "example.com")
check("arrival rejects unknown stack exit", r.exit == 500)
check("arrival rejects unknown stack log", r.log ~= nil)

-- decide_arrival: fallback 転送中は既存 cookie の所属stackへ戻さずローカル broker を呼ぶ
check("arrival skips during own fallback", core.decide_arrival("ap-northeast-1_deadbeef", "ap-northeast-3", STACKS, "example.com", "ap-northeast-3") == nil)
r = core.decide_arrival("ap-northeast-1_deadbeef", "ap-northeast-3", STACKS, "example.com", "ap-northeast-1")
check("arrival rejects mismatched fallback stack exit", r.exit == 500)
check("arrival rejects mismatched fallback stack log", r.log ~= nil)

-- decide: 503 + X-Fallback-Stack は次stackの内部ALBへ転送し残り候補を中継
r = core.decide({ status = 503, header = {
    ["X-Fallback-Stack"]     = "ap-northeast-3",
    ["X-Fallback-Remaining"] = "ap-northeast-2",
} }, STACKS, "example.com")
check("fallback forwards next stack", r.forward_host == "ap-northeast-3.example.com")
check("fallback relays stack", r.fallback_stack == "ap-northeast-3")
check("fallback relays remaining", r.fallback_remaining == "ap-northeast-2")

-- decide: 残り候補が無ければ空文字で中継 (ヘッダ削除)
r = core.decide({ status = 503, header = { ["X-Fallback-Stack"] = "ap-northeast-3" } }, STACKS, "example.com")
check("fallback empty remaining host", r.forward_host == "ap-northeast-3.example.com")
check("fallback empty remaining value", r.fallback_remaining == "")

-- decide: 不正な fallback stack は 503 で遮断 (転送しない)
r = core.decide({ status = 503, header = { ["X-Fallback-Stack"] = "EVIL" } }, STACKS, "example.com")
check("fallback rejects invalid stack exit", r.exit == 503)
check("fallback rejects invalid stack log", r.log ~= nil)
check("fallback rejects invalid stack no host", r.forward_host == nil)

-- decide: X-Fallback-Stack 無し/空 の 503 は終端 (転送しない)
r = core.decide({ status = 503, header = {} }, STACKS, "example.com")
check("fallback terminal without header exit", r.exit == 503)
check("fallback terminal without header no host", r.forward_host == nil)
r = core.decide({ status = 503, header = { ["X-Fallback-Stack"] = "" } }, STACKS, "example.com")
check("fallback terminal on empty header exit", r.exit == 503)
check("fallback terminal on empty header no host", r.forward_host == nil)

if failed > 0 then
    io.stderr:write(string.format("resolve_core: %d check(s) failed\n", failed))
    os.exit(1)
end
print("resolve_core: all checks passed")
