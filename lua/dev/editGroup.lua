
local cjson  = require "cjson"
local ds     = require "data_service"
local common = require "common"

local args = ngx.req.get_uri_args()
ngx.req.read_body()
local group = cjson.decode(ngx.req.get_body_data())

--首先根据access token获取uid
local ok, uid = get_user_by_token(args.token)
if not ok or uid = ngx.null then
    return common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 500, "internal server error", "")
end




