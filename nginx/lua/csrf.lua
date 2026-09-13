-- /api/*はsession_idとshell_idを伴い、cookieはSameSite=Noneで他サイトからも送られる。
-- 送信元をSec-Fetch-Siteで見て、同一オリジン以外を閉じる。
local _M = {}

-- Originの突き合わせは使えない。
-- TLSはCloudFront / ALBで終端し、dev環境のproxyはHostを書き換えるため、
-- nginxが見るhostとブラウザが送るOriginが食い違う。
local ALLOWED = { ["same-origin"] = true, ["none"] = true }

-- ヘッダが無いのはブラウザ以外からのリクエスト。
-- cookieを持たされる相手がいないのでCSRFの経路にならない。
function _M.is_allowed(sec_fetch_site)
    if sec_fetch_site == nil or sec_fetch_site == "" then
        return true
    end
    return ALLOWED[sec_fetch_site] == true
end

return _M
