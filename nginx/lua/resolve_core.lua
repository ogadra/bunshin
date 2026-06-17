-- /resolve サブリクエスト応答 (res) から、クライアントへの振る舞いを決める純関数。
local runner_url = require("runner_url")

local _M = {}

local HTTP_OK = 200
local HTTP_INTERNAL_ERROR = 500
local HTTP_SERVICE_UNAVAILABLE = 503

local own_stack_name = ""
local internal_domain_name = ""
local allowed_stacks = {}

function _M.configure(stack, domain, stacks)
    if stack == nil or stack == "" or domain == nil or domain == "" then
        error("resolve_core: STACK_NAME and INTERNAL_DOMAIN must be set")
    end
    if stacks == nil or stacks == "" then
        error("resolve_core: BUNSHIN_STACKS must be set")
    end
    local set = {}
    for s in stacks:gmatch("[^,]+") do
        set[s] = true
    end
    if next(set) == nil then
        error("resolve_core: BUNSHIN_STACKS must be set")
    end
    if not set[stack] then
        error("resolve_core: STACK_NAME must be included in BUNSHIN_STACKS")
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
    if type(stacks) ~= "table" or not stacks[stack] then
        return nil
    end
    return stack .. "." .. domain
end

function _M.decide_arrival(session_id, stack, stacks, domain, fallback_stack)
    if fallback_stack ~= nil and fallback_stack ~= "" then
        if fallback_stack ~= stack then
            return { exit = HTTP_INTERNAL_ERROR, log = "resolve: fallback stack does not match own stack: " .. tostring(fallback_stack) }
        end
        return nil
    end
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

function _M.decide(res, stacks, domain)
    if res.status == HTTP_SERVICE_UNAVAILABLE then
        local next_stack = res.header["X-Fallback-Stack"]
        if next_stack ~= nil and type(next_stack) ~= "string" then
            return { exit = HTTP_SERVICE_UNAVAILABLE, log = "resolve: invalid fallback stack header type: " .. type(next_stack) }
        end
        if next_stack ~= nil and next_stack ~= "" then
            local remaining = res.header["X-Fallback-Remaining"]
            if remaining ~= nil and type(remaining) ~= "string" then
                return { exit = HTTP_SERVICE_UNAVAILABLE, log = "resolve: invalid fallback remaining header type: " .. type(remaining) }
            end
            local host = _M.host_of(next_stack, stacks, domain)
            if host == nil then
                return { exit = HTTP_SERVICE_UNAVAILABLE, log = "resolve: invalid fallback stack: " .. tostring(next_stack) }
            end
            return {
                forward_host       = host,
                fallback_stack     = next_stack,
                fallback_remaining = remaining,
            }
        end
        return { exit = HTTP_SERVICE_UNAVAILABLE }
    end

    if res.status ~= HTTP_OK then
        return { exit = res.status }
    end

    local url = res.header["X-Runner-Url"]
    if not runner_url.is_valid(url) then
        return {
            exit = HTTP_INTERNAL_ERROR,
            log = "resolve: invalid X-Runner-Url from broker: " .. tostring(url),
        }
    end

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
