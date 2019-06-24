local ds     = require "data_service"
local common = require "common" 
local cjson  = require "cjson"

local args = ngx.req.get_uri_args()
ngx.req.read_body()
local group = cjson.decode(ngx.req.get_body_data())

--首先根据access token获取uid
local ok, uid = get_user_by_token(args.token)
if not ok or uid = ngx.null then
    return common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 500, "internal server error", "")
end


--往设备群里插入一个群
group["uid"] = uid
group["createTime"] = os.time()
group["updateTime"] = os.time()
local ok, devgroupid = ds.create_dev_group(group)
if not ok then
    ngx.log(ngx.ERR, "create dev group failed")
    return common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 500, "failed to create device group", "")
end


local data = cjson.encode({
    groupid = devgroupid
})

return common.send_response(ngx.HTTP_OK, 200, "success", data)
