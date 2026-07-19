-- runner_url.is_valid の境界値テスト
package.path = "/usr/local/openresty/nginx/lua/?.lua;" .. package.path
local runner_url = require("runner_url")

local cases = {
    -- 正常: http スキームの host[:port]
    { url = "http://h:3000", want = true },
    { url = "http://runner.local:3000", want = true },
    { url = "http://10.0.0.1:8080", want = true },
    { url = "http://h", want = true },
    -- 異常: https / path / query / fragment / 別スキーム / 空 / 非文字列
    { url = "https://h:3000", want = false },
    { url = "http://h/path", want = false },
    { url = "http://h:3000/x", want = false },
    { url = "http://h:3000/", want = false },
    { url = "http://h:3000?x=1", want = false },
    { url = "http://h#frag", want = false },
    { url = "ftp://h:3000", want = false },
    { url = "//h:3000", want = false },
    -- 末尾コロン / 空ポートは不可
    { url = "http://h:", want = false },
    { url = "http://h:abc", want = false },
    { url = "", want = false },
    { url = nil, want = false },
    { url = 123, want = false },
}

local failed = 0
for _, c in ipairs(cases) do
    local got = runner_url.is_valid(c.url)
    if got ~= c.want then
        failed = failed + 1
        io.stderr:write(string.format(
            "FAIL is_valid(%s) = %s, want %s\n", tostring(c.url), tostring(got), tostring(c.want)))
    end
end

local host_cases = {
    { url = "http://runner-1:3000", want = "runner-1" },
    { url = "http://10.0.0.1:8080", want = "10.0.0.1" },
    { url = "http://runner.local", want = "runner.local" },
    -- 不正な url は nil を返し、呼び出し側に不在を伝える
    { url = "https://h:3000", want = nil },
    { url = "http://h/path", want = nil },
    { url = "", want = nil },
    { url = nil, want = nil },
}
for _, c in ipairs(host_cases) do
    local got = runner_url.host_only(c.url)
    if got ~= c.want then
        failed = failed + 1
        io.stderr:write(string.format(
            "FAIL host_only(%s) = %s, want %s\n", tostring(c.url), tostring(got), tostring(c.want)))
    end
end

if failed > 0 then
    io.stderr:write(string.format("runner_url: %d case(s) failed\n", failed))
    os.exit(1)
end
print(string.format("runner_url: all %d cases passed", #cases + #host_cases))
