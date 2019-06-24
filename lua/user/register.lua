
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
local register = cjson.decode(rsaObj:decrypt(decodeBase64Body))

if register["name"] == ngx.null or register["user"] == ngx.null or register["password"] == ngx.null or register["code"] == ngx.null then
    return common.send_response(ngx.HTTP_BAD_REQUEST, 7, "invalid user info", "")
end

local ok, code = ds.get_from_cache("sms:" .. register["usr"] .. ":code")
if code ~=ngx.null and  code ~= register["code"] then
    return common.send_response(ngx.HTTP_BAD_REQUEST, 8, "invalid sms code", "") 
end

local ok, user = ds.get_user_by_phone(register["user"])
if user ~= ngx.null then
    return common.send_response(ngx.HTTP_BAD_REQUEST, 8, "registered phone", "")
end

local user = {
    name = register["name"],
    account = register["usr"],
    password = register["password"],
    type = 0,
    identifyCard = "",
    registerDate = os.time(),
    email = register["email"]
}

local ok = ds.add_user(user)
if not ok then
    return common.send_response(ngx.HTTP_INTERNAL_SERVER_ERROR, 9, "inter server error", "")
else
    return common.send_response(ngx.HTTP_OK, 200, "success", "")
end

return


