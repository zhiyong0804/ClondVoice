
local cjson  = require "cjson"
local rsa    = require "resty.rsa"
local ds     = require "data_service"
local common = require "common"

local ns = {
    "47.106.79.26:9001"
}

ngx.req.read_body()
local body = ngx.req.get_body_data()
local register = cjson.decode(body)

if not register["devSn"] then
    common.send_response(ngx.HTTP_BAD_REQUEST, 400, "no device sn parameter", "")
end

local ok, dev = ds.get_dev_by_sn(register["devSn"])
if not ok then
    common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 500, "internal server error", "")
end

if dev == nil or dev == ngx.null then
    common.send_response(ngx.HTTP_NOT_FOUND, 404, "invalid device sn", "")
end

-- 可以根据某些策略分配节点服务器，现在是写死的
local data = ""
if not register["volume"] then
data = cjson.encode({
    node_server = ns[1],
    devId       = dev["id"],
    volume      = dev["volume"]
})
else 
data = cjson.encode({
    node_server = ns[1],
    devId       = dev["id"],
})
end


common.send_response(ngx.HTTP_OK, 200, "register success", data)

dev["ip"]          = register["ip"]
dev["sw_version"]  = register["sw_version"]
dev["fw_version"]  = register["fw_version"]
dev["node_server"] = ns[1]
dev["lrd"]         = os.time()

local ok = ds.update_dev(dev)
if not ok then
    ngx.log(ngx.ERR, "device register but update ds failed devsn=", register["devSn"])
end

ngx.log(ngx.INFO, "device register success devsn=", register["devSn"])

return

