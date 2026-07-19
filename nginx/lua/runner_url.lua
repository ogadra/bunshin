-- runner 宛先 URL の検証ロジック。broker が返す X-Runner-Url を proxy_pass に渡す前に
-- http スキームの host[:port] 形式へ限定し、SSRF / ヘッダーインジェクションを防ぐ。
local _M = {}

-- brokerが返したrunner URLのportを捨ててRUNNER_APP_PORTに差し替えるため、
-- 検証を兼ねてhost部分だけ抽出する。許可形式外はnil。
-- Luaパターンはグループの ? を扱えないため2本で表現する。
function _M.host_only(url)
    if type(url) ~= "string" then
        return nil
    end
    return url:match("^http://([%w%.%-]+)$") or url:match("^http://([%w%.%-]+):%d+$")
end

function _M.is_valid(url)
    return _M.host_only(url) ~= nil
end

return _M
