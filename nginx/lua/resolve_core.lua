-- /resolve サブリクエスト応答 (res) から、クライアントへの振る舞いを決める純関数。
local runner_url = require("runner_url")

local _M = {}

local HTTP_OK = 200
local HTTP_INTERNAL_ERROR = 500

local own_stack_name = ""
local internal_domain_name = ""

-- init_by_lua から一度だけ設定する。同一イメージを region ごとに実行時 env で構成する。
function _M.configure(stack, domain)
    own_stack_name = stack or ""
    internal_domain_name = domain or ""
end

function _M.own_stack()
    return own_stack_name
end

function _M.internal_domain()
    return internal_domain_name
end

-- session_id は "<stack>_<hex>" 形式で、prefix が所属stack(AWS region 文字列)。
function _M.cookie_stack(session_id)
    if type(session_id) ~= "string" then
        return nil
    end
    return session_id:match("^([^_]+)_")
end

-- 任意文字列が proxy_pass の host へ流れ込むのを防ぐため stack を region 形に限定する。
function _M.host_of(stack, domain)
    if type(stack) ~= "string" or not stack:match("^[a-z0-9-]+$") then
        return nil
    end
    if type(domain) ~= "string" or domain == "" then
        return nil
    end
    return stack .. "." .. domain
end

-- session_id の prefix が自stackと異なれば所属stackの内部ALBへ転送する判断を返す。
function _M.decide_arrival(session_id, stack, domain)
    -- 自stack/domain 未設定時は所属を判定できないため転送しない(env 未設定の現挙動維持)。
    if stack == nil or stack == "" or domain == nil or domain == "" then
        return nil
    end
    local owner = _M.cookie_stack(session_id)
    if owner == nil or owner == stack then
        return nil
    end
    local host = _M.host_of(owner, domain)
    if host == nil then
        return { exit = HTTP_INTERNAL_ERROR, log = "resolve: invalid stack in session_id: " .. tostring(owner) }
    end
    return { forward_host = host }
end

-- decide は capture 応答 res {status, header} を受け取り、次のいずれかを返す:
--   { exit = <status>, log = <optional message> } ... その status で終了 
--   { runner_url = <url>, set_cookie = <?>, reassigned = <?> } ... runner へ proxy
function _M.decide(res)
    -- broker が非 2xx を返したらそのステータスを保持して終了する
    if res.status ~= HTTP_OK then
        return { exit = res.status }
    end

    -- runner宛先を検証
    local url = res.header["X-Runner-Url"]
    if not runner_url.is_valid(url) then
        return {
            exit = HTTP_INTERNAL_ERROR,
            log = "resolve: invalid X-Runner-Url from broker: " .. tostring(url),
        }
    end

    -- broker の Set-Cookie (session_id) と再割当てシグナルをクライアントへ伝播する。
    -- ngx.location.capture は複数 Set-Cookie をテーブルで返すため文字列へ畳む。
    local set_cookie = res.header["Set-Cookie"]
    if type(set_cookie) == "table" then
        set_cookie = table.concat(set_cookie, ", ")
    end
    return {
        runner_url = url,
        set_cookie = set_cookie,
        reassigned = res.header["X-Session-Reassigned"],
    }
end

return _M
