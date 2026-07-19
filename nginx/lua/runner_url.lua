-- runner 宛先 URL の検証ロジック。broker が返す X-Runner-Url を proxy_pass に渡す前に
-- http スキームの host[:port] 形式へ限定し、SSRF / ヘッダーインジェクションを防ぐ。
local _M = {}

-- url が http://host または http://host:port 形式かどうかを返す。
function _M.is_valid(url)
    if type(url) ~= "string" then
        return false
    end
    -- Lua パターンはグループの ? を扱えないため 2 本で表現する。
    return url:match("^http://[%w%.%-]+$") ~= nil
        or url:match("^http://[%w%.%-]+:%d+$") ~= nil
end

-- is_valid が true な url から host 部分だけ取り出す。port-forward で
-- broker が返した runner URL の :3000 を捨てて :5000 に差し替えるために使う。
function _M.host_only(url)
    if type(url) ~= "string" then
        return nil
    end
    return url:match("^http://([%w%.%-]+)$") or url:match("^http://([%w%.%-]+):%d+$")
end

return _M
