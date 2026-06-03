-- runner 宛先 URL の検証ロジック。broker が返す X-Runner-Url を proxy_pass に渡す前に
-- http スキームの host[:port] 形式へ限定し、SSRF / ヘッダーインジェクションを防ぐ。
-- 純関数として切り出し、resty で単体テスト可能にしている (runner_url_test.lua)。
local _M = {}

-- is_valid は url が http://host または http://host:port 形式 (path/query/fragment なし、
-- 末尾コロンや空ポート不可) かどうかを返す。broker は登録時の validateRunnerURL で同形式を
-- 保証するため、これは多層防御。Lua パターンはグループの ? を扱えないため 2 本で表現する。
function _M.is_valid(url)
    if type(url) ~= "string" then
        return false
    end
    return url:match("^http://[%w%.%-]+$") ~= nil
        or url:match("^http://[%w%.%-]+:%d+$") ~= nil
end

return _M
