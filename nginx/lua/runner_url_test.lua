-- runner_url.is_valid の境界値テスト。
-- brokerが返す X-Runner-Host は host label 形式のみを許可する。
package.path = "/usr/local/openresty/nginx/lua/?.lua;" .. package.path
local runner_url = require("runner_url")

local cases = {
    -- 正常: 英数字 / ドット / ハイフンだけの host label
    { host = "h", want = true },
    { host = "runner-1", want = true },
    { host = "runner.local", want = true },
    { host = "10.0.0.1", want = true },
    { host = "10-0-0-1.internal.example", want = true },
    -- 異常: scheme / port / path / 特殊文字を含むもの、非文字列
    { host = "http://h", want = false },
    { host = "h:3000", want = false },
    { host = "h/", want = false },
    { host = "h?x=1", want = false },
    { host = "runner_01", want = false },
    { host = "user@runner", want = false },
    { host = "[::1]", want = false },
    { host = "run ner", want = false },
    { host = "", want = false },
    { host = nil, want = false },
    { host = 123, want = false },
    { host = {}, want = false },
}

local failed = 0
for _, c in ipairs(cases) do
    local got = runner_url.is_valid(c.host)
    if got ~= c.want then
        failed = failed + 1
        io.stderr:write(string.format(
            "FAIL is_valid(%s) = %s, want %s\n", tostring(c.host), tostring(got), tostring(c.want)))
    end
end

if failed > 0 then
    io.stderr:write(string.format("runner_url: %d case(s) failed\n", failed))
    os.exit(1)
end
print(string.format("runner_url: all %d cases passed", #cases))
