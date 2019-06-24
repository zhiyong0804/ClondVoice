
local cjson = require "cjson"

local _M = {}

function _M.send_response(status, repCode, repMsg, repData)
    local body = cjson.encode({
        code = repCode,
        msg  = repMsg,
        data = repData
    })

    ngx.status = status
    return ngx.print(body)
end


return _M


