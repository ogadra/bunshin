package.path = "/usr/local/openresty/nginx/lua/?.lua;" .. package.path
local csrf = require("csrf")

local failed = 0
local function check(name, cond)
    if not cond then
        failed = failed + 1
        io.stderr:write("FAIL " .. name .. "\n")
    end
end

-- frontはslideサイトのiframeに載るが、/api/*を呼ぶ文書のoriginはapexのまま。
check("same-origin fetch passes", csrf.is_allowed("same-origin") == true)
-- アドレスバーからの遷移とブックマークはnoneで届く。
check("top level navigation passes", csrf.is_allowed("none") == true)
-- ブラウザ以外のクライアントはヘッダを付けない。
check("missing header passes", csrf.is_allowed(nil) == true)
check("empty header passes", csrf.is_allowed("") == true)

-- port-forwardサブドメインのユーザーappからapexを叩く経路。
check("same-site request is blocked", csrf.is_allowed("same-site") == false)
check("cross-site request is blocked", csrf.is_allowed("cross-site") == false)
check("unknown value is blocked", csrf.is_allowed("Same-Origin") == false)
check("joined duplicate headers are blocked", csrf.is_allowed("same-origin, cross-site") == false)

if failed > 0 then
    io.stderr:write(string.format("csrf: %d check(s) failed\n", failed))
    os.exit(1)
end
print("csrf: all checks passed")
