--- 模块功能：MQTT客户端数据发送处理

module(...,package.seeall)

require"misc"
require"gps"
require"agps"
require"common"
require"utils"
require"pm"

--数据发送的消息队列
local msgQuene = {}

local function insertMsg(topic,payload,qos,user)
    table.insert(msgQuene,{t=topic,p=payload,q=qos,user=user})
end

local function pubQos0TestCb(result)
    log.info("mqttOutMsg.pubQos0TestCb",result)
end

--- 初始化“MQTT客户端数据发送”
-- @return 无
-- @usage mqttOutMsg.init()
function init()
    -- insertMsg("/data","6666666666666666666666666666666",0,{cb=pubQos0TestCb})
end

--- 去初始化“MQTT客户端数据发送”
-- @return 无
-- @usage mqttOutMsg.unInit()
function unInit()
    sys.timerStop(pubQos0Test)
    while #msgQuene>0 do
        local outMsg = table.remove(msgQuene,1)
        if outMsg.user and outMsg.user.cb then outMsg.user.cb(false,outMsg.user.para) end
    end
end

--- MQTT客户端是否有数据等待发送
-- @return 有数据等待发送返回true，否则返回false
-- @usage mqttOutMsg.waitForSend()
function waitForSend()
    return #msgQuene > 0
end

--- MQTT客户端数据发送处理
-- @param mqttClient，MQTT客户端对象
-- @return 处理成功返回true，处理出错返回false
-- @usage mqttOutMsg.proc(mqttClient)
function proc(mqttClient)
    while #msgQuene>0 do
        local outMsg = table.remove(msgQuene,1)
        local result = mqttClient:publish(outMsg.t,outMsg.p,outMsg.q)
        if outMsg.user and outMsg.user.cb then 
            outMsg.user.cb(result,outMsg.user.para) 
        end
        if not result then
            return 
        end
    end
    return true
end

--串口ID,1对应uart1
--如果要修改为uart2，把UART_ID赋值为2即可
local UART_ID = 1
--串口读到的数据缓冲区
local rdbuf = ""
local mlat=""
local mlatType=""
local mlng=""
local mlngType = ""

--[[
函数名：proc
功能  ：处理从串口读到的数据
参数  ：
        data：当前一次从串口读到的数据
返回值：无
]]
local function proc(data)
    if not data or string.len(data) == 0 then return end
    --追加到缓冲区
    rdbuf = rdbuf..data    
    if string.len(rdbuf) == 43 then
        log.info("rx data",rdbuf:toHex())
        local torigin = 
        {
            id = misc.getImei(),
            lat = mlat,
            lng = mlng,
            latType = mlatType,
            lngType = mlngType,
            data= rdbuf:toHex(),   
        }
        local data = json.encode(torigin)
        print("json data",data)

        insertMsg("/data",data,0,{cb=pubQos0TestCb})
            
        rdbuf=""
    end
end

--[[
函数名：read
功能  ：读取串口接收到的数据
参数  ：无
返回值：无
]]
local function read()
    local data = ""
    --底层core中，串口收到数据时：
    --如果接收缓冲区为空，则会以中断方式通知Lua脚本收到了新数据；
    --如果接收缓冲器不为空，则不会通知Lua脚本
    --所以Lua脚本中收到中断读串口数据时，每次都要把接收缓冲区中的数据全部读出，这样才能保证底层core中的新数据中断上来，此read函数中的while语句中就保证了这一点
    while true do        
        data = uart.read(UART_ID,"*l")
        if not data or string.len(data) == 0 then break end
        proc(data)
    end
end

--[[
函数名：write
功能  ：通过串口发送数据
参数  ：
        s：要发送的数据
返回值：无
]]
function write(s)
    log.info("testUart.write",s)
    uart.write(UART_ID,s.."\r\n")
end

local function writeOk()
    log.info("testUart.writeOk")
end


--保持系统处于唤醒状态，此处只是为了测试需要，所以此模块没有地方调用pm.sleep("testUart")休眠，不会进入低功耗休眠状态
--在开发“要求功耗低”的项目时，一定要想办法保证pm.wake("testUart")后，在不需要串口时调用pm.sleep("testUart")
pm.wake("testUart")
--注册串口的数据接收函数，串口收到数据后，会以中断方式，调用read接口读取数据
uart.on(UART_ID,"receive",read)
--注册串口的数据发送通知函数
uart.on(UART_ID,"sent",writeOk)

--配置并且打开串口
uart.setup(UART_ID,9600,8,uart.PAR_NONE,uart.STOP_1)

--[[
函数名：nemacb
功能  ：NEMA数据的处理回调函数
参数  ：
        data：一条NEMA数据
返回值：无
]]
function nmeaCb(nmeaItem)
    local head=string.sub(nmeaItem,0,6)
    if head=="$GPGGA" then
        mlat=string.sub(nmeaItem,19,27)
        mlatType=string.sub(nmeaItem,29,29)
        mlng=string.sub(nmeaItem,31,40)
        mlngType=string.sub(nmeaItem,42,42)
    end
end


--设置GPS+BD定位
--如果不调用此接口，默认也为GPS+BD定位
--gps.setAerialMode(1,1,0,0)

--设置仅gps.lua内部处理NEMA数据
--如果不调用此接口，默认也为仅gps.lua内部处理NEMA数据
--如果gps.lua内部不处理，把NMEA数据通过回调函数cb提供给外部程序处理，参数设置为1,nmeaCb
--如果gps.lua和外部程序都处理，参数设置为2,nmeaCb
gps.setNmeaMode(2,nmeaCb)

gps.open(gps.DEFAULT,{tag="TEST1",cb=test1Cb})
