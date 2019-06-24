
local http  = require "resty.http"
local cjson = require "cjson"
local redis = require "resty.redis"
local ds    = require "data_service"

function generate_mobile_validate_code()
    local time = os.time()
    math.randomseed(time)
    code = math.random(100000,999999)

    return code
end

-- get phone number from request body
ngx.req.read_body()
local req_body = ngx.req.get_body_data()
ngx.log(ngx.INFO, "request body is ", req_body)
local req_data = cjson.decode(req_body)
local phone = req_data["phone"]
if not phone then
    local body = cjson.encode({
        code = 400,
        msg  = "no phone number in request body",
        data = ""
    })

    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.print(body)
    return
end

local code = generate_mobile_validate_code()
ngx.log(ngx.INFO, "generated mobile validate code is ", code)

local httpc = http.new()
local text_str = "【动脑单车】欢迎使用动脑单车,您的验证码是" .. code ..",请不要把验证码透露给别人."
local sms_body_str = "apikey=9ac068166011ccef83d9882c112810ac&" .. "text=" .. text_str .. "&mobile=" .. phone
local uri = "http://sms.yunpian.com/v2/sms/single_send.json"

local res, err = httpc:request_uri(uri, {
    method = "POST",
    headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded;charset=utf-8;",
	  ["Accept"]       = "application/json;charset=utf-8;"
    },
    body = sms_body_str,
    keepalive_timeout = 60,
    keepalive_pool = 10
})

local failed_send_sms = false

if not res then
    failed_send_sms = true
end

ngx.log(ngx.INFO, "send sms response is : ", res.body)

local res_body = cjson.decode(res.body)
if res_body["code"] ~= 0 or failed_send_sms then
    ngx.log(ngx.ERR, "failed to send sms for ", phone, "since ", err)
    local body = cjson.encode({
        code = 500,
        msg  = "failed to send sms",
        data = ""
    })

    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.print(body)
    return
end

-- save the code to redis
local key = "sms:" .. phone .. ":code"
local ok = ds.save_to_cache(key, code)
if not ok then
    ngx.log(ngx.ERR, "failed to save validate code to cache", err)
    return
end

-- send response
local body = cjson.encode({
    code = 200,
    msg  = "success",
    data = ""
})

ngx.status = ngx.HTTP_OK
ngx.print(body)


