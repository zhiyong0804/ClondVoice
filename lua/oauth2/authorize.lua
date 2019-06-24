
local common = require "common"
local cjson  = require "cjson"
local rsa    = require "resty.rsa" 
local uuid   = require "resty.uuid" 
local ds     = require "data_service"

local RSA_PKCS8_PRI_KEY = [[
-----BEGIN RSA PRIVATE KEY-----
MIICdwIBADANBgkqhkiG9w0BAQEFAASCAmEwggJdAgEAAoGBAL6Cm8itZFnz0vSu
eDEVSwlOn94MGLmviv9f4/2ZhTebJXRyDpP3v8XAWqJA2gCYd7en9wDuATDLsj6K
LX6iahvpDVlsdNsRit2VFbvld9oU+NP5mvx1VjL1S1wTgHBhmE304CpXY+Wfzn7z
jIDk+pJJM5go/gR1ERvQzAravwwBAgMBAAECgYEAlfbwNI8xUJHbvNpeKJ0PXTs0
IzG4gOrLau2L5gRkVnpdiIWELjw3DK63acPNF+ztSHgCuwufik6+d/aDi4zEIupu
6PFUhyaoawSM4YVQUF/NWOXS2qipyfQCNmwHX1c1IBP3N8kCnRf9uu7OiUxqbA/V
JQVFHhVIrUM4g2nFmSUCQQDk+wF3AWIaNwpdu/J6+VNGa8+wN79wOfPIioBCuK8c
meFVqp6ssESxZcwdz/J9pPuwhwqvKNfSNtMGEqnOS8zbAkEA1P2ABKsIcfFoz0/K
2Bt1+ByJrqyiIRIXQlQfZVj5i0cLzpj/CL1+QHJSIwv8vFHtvjU0g8WBsqdg3VBj
e9QzUwJAMV50+GWR8zj+wSruotjyvXItOz8pxVaZWxmRgdEz4CTFUqUQxQbUKLNc
COl2zOQvZ+YVxaI2thof8WVAuzvYlQJBAMT0gjxO2GldXplOZPoAMs+zvBHdq7M/
ImkAl2PFqkUD9sQeMMApUqVP0ep8vEJ81IcudhhgPHYzV1xwaP5qFOcCQDMaHVfM
Cvns6Xsc8qq7IZOKcgm17AYTPfYW/TMeY2zh2VL3MQmzC6vvVO05ElMgGnKRQbAw
LgElyhltfylEES0=
-----END RSA PRIVATE KEY-----
]]

local rsaObj, err = rsa:new({
    private_key = RSA_PKCS8_PRI_KEY,
    key_type   = rsa.KEY_TYPE.PKCS8
})

if not rsaObj then
    ngx.log(ngx.ERR, "new rsa err:", err)
    return common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 500, "validate parameter failed", "")
end

-- base64 解码，然后再RSA解密
local args = ngx.req.get_uri_args()
ngx.req.read_body()
local body = ngx.req.get_body_data()
local decodeBase64Body = ngx.decode_base64(body)
ngx.log(ngx.INFO, "data is : ", body, ", after decode base64 is", decodeBase64Body)
local loginParameters = cjson.decode(rsaObj:decrypt(decodeBase64Body))

ngx.log(ngx.INFO, "data is : ", body, ", after decrypt", loginParameters["user"])

if not args.grantType or not loginParameters["user"] or not loginParameters["password"] then
    return common.send_response(ngx.HTTP_BAD_REQUEST, 1, "no user name or password", "")
end

local ok, user = ds.get_user_by_phone(loginParameters["user"])
if not ok or user == nil then 
    return common.send_response(ngx.HTTP_BAD_REQUEST, 2, "invalid user", "")
end

ngx.log(ngx.INFO, "login password is: ", loginParameters["password"])
ngx.log(ngx.INFO, "user password is: ", user["password"])

local str = ""
for k , v in pairs(user) do
    str = str .. k .. ":" .. v .. ","
end

ngx.log(ngx.INFO, "read from redis is ", str)

if user["password"] ~= loginParameters["password"] then
    return common.send_response(ngx.HTTP_NOT_ACCEPTABLE, 3, "invalid password", "")
end

local ok, client = ds.get_client_by_uid(user["uid"])

-- 如果有access token，则该access token是另外一个手机登录的，需要删掉
if client ~= nil and client["access_token"] ~= nil then
    ds.delete_access_token(user["uid"])
end

-- 如果ds里没有access token，则生成access token 和refresh token，并且设置其过期时间
local accessToken  = ngx.encode_base64(uuid.generate())
local refreshToken = ngx.encode_base64(uuid.generate())
local currentTime  = os.time()
-- access token 有效时间是两个小时
local accessTokenValidaty = currentTime + 3600 * 2 
-- refresh token 有效时间是14天
local refreshTokenValidaty = currentTime + 3600 * 24 * 14

local param = {
    uri = "",
    access_token = accessToken,
    refresh_token = refreshToken,
    access_token_validaty = accessTokenValidaty,
    refresh_token_validaty = refreshTokenValidaty,
    uid = user["uid"]
}

local ok = ds.save_client_token(param)
-- 通过access token 找到用户ID
ds.save_to_cache("t_client:" .. accessToken .. ":uid", user["uid"])
-- 通过refresh token 找到用户ID
ds.save_to_cache("t_client:" .. refreshToken .. ":uid", user["uid"])

if not ok then
    return common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 500, "save to ds failed", "")
end

local data = cjson.encode({
    access_token = accessToken,
    refresh_token = refreshToken,
    access_token_validaty = accessTokenValidaty,
    refresh_token_validaty = refreshTokenValidaty
})

return common.send_response(ngx.HTTP_OK, 200, "success", data)



