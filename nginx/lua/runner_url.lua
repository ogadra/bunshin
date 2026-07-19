-- brokerが返す X-Runner-Host の host label を検証する。
-- SSRF / proxy_pass ヘッダー injection を防ぐため、
-- 英数字 / ドット / ハイフンのみの host label に限定する。
local _M = {}

function _M.is_valid(host)
    if type(host) ~= "string" then
        return false
    end
    return host:match("^[%w%.%-]+$") ~= nil
end

return _M
