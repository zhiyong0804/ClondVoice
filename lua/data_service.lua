
local config = {
    redis_host   = "127.0.0.1",
    redis_port   = 6379,
    db_host      = "127.0.0.1",
    db_port      = 3306,
    db_name      = "ClondVoice",
    db_user      = "root",
    db_psw       = "123456"
}

local redis = require "resty.redis"
local mysql = require "resty.mysql"
local cjson = require "cjson"

--[[

redis save rule : object-type:key:param

--]]

local _M = {}

local function connect_redis()
    -- new redis connect
    local rd = redis:new();
    local ok, err = rd:connect(config.redis_host, config.redis_port)
    if not ok then
        ngx.log(ngx.ERR, "connect redis failed: ", err)
	return false
    end

    return true, rd
end

local function connect_database()
    local db, err = mysql:new()
    if not db then
	ngx.log(ngx.ERR, "new mysql client failed: ", err)
        return false
    end

    db:set_timeout(1000)
    
    local ok, err, errcode, sqlstate = db:connect{ 
	    host      = "127.0.0.1", --config.db_host, 
            port      = 3306, -- config.db_port, 
            database  = "ClondVoice", -- config.db_name, 
            user      = "root", --config.db_user, 
            password  = "123456", --config.db_psw,
	    charset   = "utf8",
            max_packet_size = 1024 * 1024
    }

    if not ok then
        ngx.log(ngx.ERR, "connect_database : failed to connect: ", err, ": ", errcode, " ", sqlstate)
	return false
    end
    
    return true, db
end

local function read_parameter(key, sql, filed)
    local ok, rd = connect_redis()
    if not ok then
        return false
    end

    local ret, err = rd:get(key);
    if not ret then
        ngx.log(ngx.ERR, "failed get value from redis with key : ", key, " for :", err)
    end

    ngx.log(ngx.INFO, "return value is : ", ret, ", err is ", err)

    if ret ~= ngx.null then
        return true, ret
    end

    local ok, db = connect_database()
    if not ok then
	ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    local res, err, errcode, sqlstate = db:query(sql)
    if not res then
        ngx.log(ngx.ERR, "failed to execute : ", sql, " bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return false
    end
    
    local ok, err = db:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.ERR, "failed to put database client to pool : ", err)
        return false
    end

    local ok, err = rd:set(key, res[1][filed])
    if not ok then
        ngx.log(ngx.WARN, "failed insert into redis : ", key, ":", value, "since :", err)
    end

    -- set redis keepalive
    local ok, err = rd:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.ERR, "failed to set keepalive: ", err)
        return false
    end
    
    ngx.log(ngx.INFO, "get secret from db with ", res[1][filed], ":sql =", sql, "filed : secret")

    return true, res[1][filed]
end

local function read_object_filed(key, filed, sql)
    ngx.log(ngx.INFO, "key:" .. key, ",filed:", filed, ",sql:", sql)
    local ok, rd = connect_redis()
    if not ok then
        ngx.log(ngx.ERR, "connect redis failed key = ", key, ", sql = ", sql)
        return false
    end

    local res = rd:hget(key, filed)
    ngx.log(ngx.INFO, "key:" .. key, ",filed:", filed, ",sql:", sql, "res:", res)

    if res ~= ngx.null then 
        return true, res
    end

    ngx.log(ngx.INFO, "key:" .. key, ",filed:", filed, ",sql:", sql, "res:", res)

    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    local res, err, errcode, sqlstate = db:query(sql)
    if not res then
        ngx.log(ngx.ERR, "failed to execute : ", sql, " bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return false
    end

    ngx.log(ngx.INFO, "read from mysql, " .. filed .. ":", res[1][filed])

    rd:hset(key, filed, res[1][filed])

    return true, res[1][filed]
end

local function read_object(key, sql)

    local ok, rd = connect_redis()
    if not ok then
	ngx.log(ngx.ERR, "connect redis failed key = ", key, ", sql = ", sql)
        return false
    end

    -- get object from redis
    local res, err = rd:hgetall(key)
    if res ~= nil and res ~= ngx.null  then
        ngx.log(ngx.ERR, "read from redis success key:", key)
	return true, rd:array_to_hash(res)
    end

    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    local res, err, errcode, sqlstate = db:query(sql)
    if not res or #res < 1 then
        ngx.log(ngx.ERR, "failed to execute : ", sql, " bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return false
    end
    
    local ok, err = db:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.ERR, "failed to put database client to pool : ", err)
        return false
    end

    -- insert to redis
    rd:hmset(key, res[1])

    return true, res[1]
end

local function save_to_redis(key, value)
    local ok, rd = connect_redis()
    if not ok then
	ngx.log(ngx.ERR, "connect redis failed.")
        return false
    end

    local ok, err = rd:set(key, value)
    if not ok then
        ngx.log(ngx.ERR, "failed to save to redis with key :", key, ", value:", value)
	return false
    end

    return true
end

local function get_from_redis(key)
    local ok, rd = connect_redis()
    if not ok then
        ngx.log(ngx.ERR, "connect redis failed.")
        return false
    end

    local res, err = rd:get(key)
    if not ok then
        ngx.log(ngx.ERR, "failed to save to redis with key :", key)
        return false
    end

    return true, res
end

local function delete_from_redis(key)
    local ok, rd = connect_redis()
    if not ok then
        ngx.log(ngx.ERR, "connect redis failed.")
        return false
    end

    local res, err = rd:del(key)
    if not ok then
        ngx.log(ngx.ERR, "failed to save to redis with key :", key)
        return false
    end

    return true
end

local function save_object(key, sql, ...)
    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    local res, err, errcode, sqlstate = db:query(sql)
    if not res then
        ngx.log(ngx.ERR, "failed to execute : ", sql, " bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return false
    end

    local ok, err = db:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.ERR, "failed to put database client to pool : ", err)
        return false
    end

    local ok, rd = connect_redis()
    if not ok then
        ngx.log(ngx.ERR, "connect redis failed.")
        return false
    end

    rd:hmset(key, ...)

    return true
end

local function insert_object(key_prefix, sql, ...)
    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect redis failed.")
        return false
    end

    res, err, errcode, sqlstate = db:query(sql)
    if not res then
        ngx.log(ngx.ERR, "failed to execute : ", sql, " bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return false
    end

    local res, err, errcode, sqlstate = db:query("select last_insert_id()")
    if not res then
        ngx.log(ngx.ERR, "failed to execute : ", sql, " bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
        return false
    end

    primary_key = res
   
    local ok, rd = connect_redis()
    if not ok then
        ngx.log(ngx.ERR, "connect redis failed.")
        return false
    end

    local key = key_prefix .. ":" .. primary_key
    rd:hmset(key, ...)

    return true
end

------------------------------------------------------------------------------
-- 第三方开发接口
------------------------------------------------------------------------------

function _M.get_app_secret(appkey)   
    local key = "t_develop:" .. appkey
    -- local sql = "select * from AppAuth;"
    local sql = string.format([[select * from t_develop where appKey = '%s']], appkey)
    return read_object_filed(key, "secret", sql)
end

------------------------------------------------------------------------------
-- 用户操作接口
------------------------------------------------------------------------------
function _M.get_user_by_token(token)
    local key = "t_user:" .. token .. ":uid"
    local sql = "select * from t_user where token = '" .. token .. "'"
    return read_parameter(key, sql, userid)
end

function _M.save_to_cache(key, value)
    return save_to_redis(key, value)
end

function _M.get_from_cache(key)
    return get_from_redis(key)
end

function _M.delete_from_cache(key)
    return delete_from_redis(key)    
end

function _M.get_user_by_phone(phone)
    local key = "t_user:" .. phone
    return read_object(key, "select * from t_user where account = " .. phone)
end

function _M.add_user(user)
    local key_prefix = "t_user:"
    local sql  = string.format("insert into t_user values('%s', '%s', '%s', 0, '%s', %d, '%s')", user["name"], user["account"], user["password"], user["type"], user["identyfyCard"], os.time(), user["email"]);
    insert_object(key_prefix, sql, "name", user["name"], "account", user["account"], "password", user["password"], "type", user["type"], "identyfyCard", user["identifyCard"], "registerDate", user["registerDate"], "email", user["email"])
end

--------------------------------------------------------------------------------
-- 终端验证的操作
--------------------------------------------------------------------------------
function _M.get_client_by_uid(uid)
    local key = "t_client:" .. uid
    local sql = "select * from t_client where uid = " .. uid
    return read_object(key, sql)
end

function _M.save_client_token(tokenParam)
    local key = "t_client:" .. tokenParam["uid"]
    local sql = string.format("replace into t_client values ('%s','%s','%s',%d,%d,%d)", tokenParam["uri"], tokenParam["access_token"], tokenParam["refresh_token"], tokenParam["access_token_validaty"], tokenParam["refresh_token_validaty"], tokenParam["uid"])

    return save_object(key, sql, "uri", tokenParam["uri"], "access_token", tokenParam["access_token"], "refresh_token", tokenParam["refresh_token"], "access_token_validaty", tokenParam["access_token_validaty"], "refresh_token_validaty", tokenParam["refresh_token_validaty"])

end

function _M.delete_access_token(uid)
    local ok, rd = connect_redis()
    if not rd then
        ngx.log(ngx.ERR, "connect redis failed err :", err)
        return false
    end

    rd:hdel("t_client:" .. uid, "access_token")

    local sql = "delete from t_client where uid = " .. uid
    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    db:query(sql)

    return true
end

-----------------------------------------------------------------------------
-- 设备群的操作
-----------------------------------------------------------------------------
function _M.create_dev_group(group)
    local key_prefix = "t_dev_group:"    
    local sql = string.format("replace into t_dev_group values(%d, '%s', '%s', %d, %d, %d, %d)", group["uid"],group["name"], group["desc"], group["coverId"], group["createTime"], group["updateTime"], group["audienceCount"])
    insert_object(key_prefix, sql, "uid", group["uid"], "name", group["name"], "desc", group["desc"], "coverId", group["converId"], "createTime", group["createTime"], "updateTime", group["updateTime"], "audienceCount", group["audienceCount"])
    
    -- 设备群与设备关联表插入群的设备成员
    local ok, rd = connect_redis()
    if not rd then
        ngx.log(ngx.ERR, "connect redis failed err :", err)
        return false
    end

    sql = "select auto_increment from information_schema.tables where table_schema="ClondVoice" and table_name="t_dev_group";"

    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    local lastGroupid = db:query(sql)
    if not res then
         ngx.log(ngx.ERR, "get primary key value from db failed")
	 return false
    end

    groupid = lastGroupid - 1
    
    rd:sadd("t_group_map:" .. groupid, group["devs"])
    for k,v in pairs(group["devs"]) do
        db:query(string.format("insert into t_group_map value(%d, %d)", groupid, v))
    end

    db:set_keepalive(10000, 100)
    rd:set_keepalive(10000, 100)

    -- 返回groupid，设备群的ID
    return true, groupid
end

function _M.update_dev_group(group, addDevs, delDevs)
    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    local ok, rd = connect_redis()
    if not rd then
        ngx.log(ngx.ERR, "connect redis failed err :", err)
        return false
    end

    local key = "t_dev_group:" .. group["id"]
    local fileds = {}
    local sql = "update t_dev_group set "
    local i = 0
    for k, v in pairs(group) do
        fileds[i+1] = k
	fileds[i+2] = v
	sql = sql .. k .. "=" .. v 
	i = i + 2
	if < #group then
        sql = sql .. ", and "
	end
    end

    rd:hmset(key, fileds)
    db:query(sql)

    rd:sadd("t_group_map:" .. group["id"], addDevs)
    rd:srem("t_group_map:" .. group["id"], delDevs)

    for k,v in pairs(addDevs) do
        db:query(string.format("insert into t_group_map value(%d, %d)", group["id"], v))
    end

    for k, v in pairs(delDevs) do
        db:query(string.format("delete from t_group_map where groupId=%d and devId=%d", group["id"], v))
    end

    db:set_keepalive(10000, 100)
    rd:set_keepalive(10000, 100)

    return true
end

function _M.del_dev_group(groupid)
    local ok, db = connect_database()
    if not ok then
        ngx.log(ngx.ERR, "connect mysql failed.")
        return false
    end

    local ok, rd = connect_redis()
    if not rd then
        ngx.log(ngx.ERR, "connect redis failed err :", err)
        return false
    end

    db:query(string.format("delete from t_group_map where groupId=%d", groupid))
    rd:del("t_group_map:" .. groupid)

    db:set_keepalive(10000, 100)
    rd:set_keepalive(10000, 100)

    return true
end

----------------------------------------------------------------------------
-- 设备的操作
----------------------------------------------------------------------------
function _M.get_dev_by_sn(sn)
    local key = "t_dev:" .. sn
    local sql = "select * from t_dev where index_sn=" .. sn
    return read_object(key, sql)
end

function _M.update_dev(dev)
    local key = "t_dev" .. dev["sn"]
    local sql = string.format("update t_dev set node_server='%s', ip='%s', sw_version='%s', fw_version='%s',volume=%d, lrd=%d;", dev["node_server"], dev["ip"], dev["sw_version"], dev["fw_version"], dev["volume"], dev["lrd"])
    return save_object(key, sql, "node_server", dev["node_server"], "ip", dev["ip"], "sw_version", dev["sw_version"], "fw_version", dev["fw_version"], "volume", dev["volume"], "lrd", dev["lrd"])
end


return _M
