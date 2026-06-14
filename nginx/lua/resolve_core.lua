-- /resolve サブリクエスト応答 (res) から、クライアントへの振る舞いを決める純関数。
local runner_url = require("runner_url")

local _M = {}

local HTTP_OK = 200
local HTTP_INTERNAL_ERROR = 500

local own_stack_name = ""
local internal_domain_name = ""
local allowed_stacks = {}

function _M.configure(stack, domain, stacks)
    if stack == nil or stack == "" or domain == nil or domain == "" then
        error("resolve_core: STACK_NAME and INTERNAL_DOMAIN must be set")
    end
    local set = {}
    for s in (stacks or ""):gmatch("[^,]+") do
        set[s] = true
    end
    if next(set) == nil then
        error("resolve_core: BUNSHIN_STACKS must be set")
    end
    own_stack_name = stack
    internal_domain_name = domain
    allowed_stacks = set
end

function _M.own_stack()
    return own_stack_name
end

function _M.internal_domain()
    return internal_domain_name
end

function _M.stacks()
    return allowed_stacks
end

function _M.cookie_stack(session_id)
    if type(session_id) ~= "string" then
        return nil
    end
    return session_id:match("^([^_]+)_")
end

-- 既知 stack のみ許可し、未知/詐称値が proxy_pass の host へ流れるのを防ぐ。
function _M.host_of(stack, stacks, domain)
    if not stacks[stack] then
        return nil
    end
    return stack .. "." .. domain
end

function _M.decide_arrival(session_id, stack, stacks, domain)
    local owner = _M.cookie_stack(session_id)
    if owner == nil or owner == stack then
        return nil
    end
    local host = _M.host_of(owner, stacks, domain)
    if host == nil then
        return { exit = HTTP_INTERNAL_ERROR, log = "resolve: unknown stack in session_id: " .. tostring(owner) }
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
