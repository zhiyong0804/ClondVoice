
local common = require "common"
local ds     = require "data_service"
local cjson  = require "cjson"
local uuid   = require "resty.uuid"

local args = ngx.req.get_uri_args()
if not args.refreshToken then
    return common.send_response(ngx.HTTP_BAD_REQUEST, 400, "no refresh token", "" );
end

local ok, uid = ds.get_from_cache("t_client:" .. args.refreshToken ..":uid")
ngx.log(ngx.INFO, "key is :", "t_client:" .. args.refreshToken ..":uid")
if not ok or uid == ngx.null then
    return common.send_response(ngx.HTTP_BAD_REQUEST, 400, "invalid refresh token", "" )
end 

local ok, client = ds.get_client_by_uid(uid)
if not ok or client["access_token"] == nil  then
    return common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 500, "internal server error", "" )
end

local currentTime = os.time()


if currentTime < tonumber(client["access_token_validaty"]) then
    local data = cjson.encode({
        access_token = client["access_token"],
	access_token_validaty = client["access_token_validaty"] - currentTime,
	refresh_token = client["refresh_token"],
        refresh_token_validaty = client["refresh_token_validaty"]
    })

    return common.send_response(ngx.HTTP_OK, 200, "refresh token success", data)
end

-- 如果access token过期，则需要重新生成access token
if currentTime >= tonumber(client["access_token_validaty"]) then
    -- 删除旧的access token 在缓存里的值
    ds.delete_from_redis("t_client:" .. client["access_token"])

    client["access_token"]  = ngx.encode_base64(uuid.generate())    
    client["access_token_validaty"]  = currentTime + 3600*2
    ds.save_client_token(client)

    local data = cjson.encode({
        access_token = client["access_token"],
	access_token_validaty  = client["access_token_validaty"],
	refresh_token = client["refresh_token"],
	refresh_token_validaty = client["refresh_token_validaty"]
    })

    return common.send_response(ngx.HTTP_OK, 200, "refresh token success", data)
end

-- 如果refresh token 过期，则需要重新登录
if currentTime > (client["refresh_token_validaty"]) then
    ds.delete_access_token(uid)
    return common.send_response(ngx.HTTP_NOT_ALLOWED, 5, "refresh token is expire")
end

