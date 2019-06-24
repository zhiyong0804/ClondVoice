local ds    = require "data_service"
local cjson = require "cjson"

local function to_hex(str)
   return ({str:gsub(".", function(c) return string.format("%02X", c:byte(1)) end)})[1]
end

-- check API sign
local function check_api_sign(args)
    if not args.apiSign or not args.timestamp or not args.appKey then
        ngx.log(ngx.ERR, "lack some required parameters : ", args.timestamp)
        return false
    end

    -- get secret
    local ok, secret = ds.get_app_secret(args.appKey)
    if not ok or secret == nil then
	ngx.log(ngx.ERR, "failed to get secret from ds : ", args.appKey)
	return false
    end

    -- check sign with SHA
    table.sort(args)
    local parameters = ""

    for k,v in pairs(args) do
        if k ~= "apiSign" then
	    parameters = parameters .. k .. v
	end
    end

    parameters = parameters
    calc_sign =string.upper(to_hex(ngx.hmac_sha1(secret, parameters)))

    if calc_sign ~= args.apiSign then
	ngx.log(ngx.ERR, "check apiSign failed, calc sign is : ", calc_sign , "parameters is :", parameters)
	return false
    end

    return true
end

local function validate_token(uri, args)
    if string.match(uri, "/api/oauth2/authorize") or string.match(uri, "/api/oauth2/refreshToken") or string.match(uri, "/api/smsCode/get") then
        return true
    end

    if not args.token then 
        return false
    end

    -- check token is valide
    local ok, uid = ds.get_user_by_token(args.token)
    if not ok then 
        ngx.log(ngx.ERR, "get user token failed token: ", args.token)
        return false
    end

    if not uid then 
	ngx.log(ngx.ERR, "uid is invalid token:", args.token)
        return false
    end

    return true
end

local args = ngx.req.get_uri_args()

--step 1 : check sign
local ok = check_api_sign(args)
if not ok then
    ngx.log(ngx.ERR, "check openapi failed for: ", ngx.var.uri)
    
    local body = cjson.encode({
        code = 401,
        msg  = "invalid sign argument",
        data = ""
    })

    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.print(body)
    return
end

--step 2 : check token
local ok = validate_token(ngx.var.uri, args)
if not ok then
    ngx.log(ngx.ERR, "validate token failed.", ngx.var.uri)
    local body = cjson.encode({
        code = 401,
	msg  = "invalide token argument",
	data = ""
    })

    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.print(body)
end


