-- /resolve サブリクエスト応答 (res) から、クライアントへの振る舞いを決める純関数。
-- ngx に依存しないため luajit で単体テスト可能 (resolve_core_test.lua)。
-- resolve.lua がこの判定結果を ngx 副作用 (ngx.exit / ngx.var.*) に適用する。
local runner_url = require("runner_url")

local _M = {}

local HTTP_OK = 200
local HTTP_INTERNAL_ERROR = 500

-- decide は capture 応答 res {status, header} を受け取り、次のいずれかを返す:
--   { exit = <status>, log = <optional message> } ... その status で終了 (broker エラー透過 / 不正宛先遮断)
--   { runner_url = <url>, set_cookie = <?>, reassigned = <?> } ... runner へ proxy
function _M.decide(res)
    -- broker が非 2xx を返したらそのステータスを保持して終了する
    -- (auth_request と違い 503/500 を潰さない。JSON ボディは errors.conf が描画)。
    if res.status ~= HTTP_OK then
        return { exit = res.status }
    end

    -- runner 宛先を厳格に検証 (SSRF / ヘッダーインジェクション防止の多層防御)。
    local url = res.header["X-Runner-Url"]
    if not runner_url.is_valid(url) then
        return {
            exit = HTTP_INTERNAL_ERROR,
            log = "resolve: invalid X-Runner-Url from broker: " .. tostring(url),
        }
    end

    -- broker の Set-Cookie (runner_id) と再割当てシグナルをクライアントへ伝播する。
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
