require "http/web_socket"
require "json"
require "log"

require "./error"

module BitShares
  Log = ::Log.for("websocket")

  class GrapheneWebSocket
    KGWS_MAX_SEND_LIFE = 4
    KGWS_MAX_RECV_LIFE = 8

    alias ChannelDataType = JSON::Any | BaseError
    alias SubscribeCallbackType = (Bool, JSON::Any | String) -> Bool

    # => 仅连接中 状态类型
    private enum ConnectStatus
      Pending

      Connected
      Timeout

      Closed
    end

    # => 完整生命周期 状态类型
    enum Status
      Pending

      Logined

      Closed
      Closing
    end

    struct Future
      @channel = Channel(ChannelDataType).new(1)

      def error(e)
        @channel.send(e)
      end

      def done(result)
        @channel.send(result)
      end

      def await : JSON::Any
        result = @channel.receive
        raise result if result.is_a?(BaseError)
        return result
      end
    end

    @websock : HTTP::WebSocket? = nil

    getter graphene_chain_config : JSON::Any? = nil # => 石墨烯链配置信息，如果 database API 未开启则默认为 nil。
    getter graphene_address_prefix = ""             # => 石墨烯链地址前缀信息，如果 database API 未开启则默认为 空。

    getter status = Status::Pending
    @timer_keep_alive : Proc(Nil)? = nil
    @_send_life = KGWS_MAX_SEND_LIFE
    @_recv_life = KGWS_MAX_RECV_LIFE

    # 同步调用服务器 API 接口
    def call(api_name : String, method : String, params : Tuple | Array | Nil, callback : SubscribeCallbackType? = nil)
      raise SocketClosed.new("socket is not connected, status: #{@status}.") unless @status.logined?
      return async_send_data(@api_ids[api_name], method, params, callback: callback).await
    end

    # 同时调用多个 API 接口，具体参数参考 `call` 方法。
    def multi_call(*args)
      return args.map { |arg| async_call(arg[0], arg[1], arg[2]?, arg[3]?) }.map(&.await)
    end

    # 异步调用服务器 API 接口
    def async_call(api_name : String, method : String, params : Tuple | Array | Nil, callback : SubscribeCallbackType? = nil) : Future
      raise SocketClosed.new("socket is not connected, status: #{@status}.") unless @status.logined?
      async_send_data(@api_ids[api_name], method, params, callback: callback)
    end

    # 关闭websocket连接，会自动触发 on_close 事件。
    def close_websocket(reason = "")
      Log.debug { "user call close_websocket: #{reason}, status: #{@status}" }
      return if @status.closed? || @status.closing?
      @status = Status::Closing
      @websock.try &.close
    end

    # 事件函数：心跳包。
    def on_keep_alive(&@on_keep_alive : GrapheneWebSocket ->)
    end

    # TODO: ode_url, logger, api_list, keep_alive_callback = nil
    def initialize(node_url : String, timeout : Time::Span? = nil, @api_list = ["database", "network_broadcast", "history"])
      @username = ""
      @password = ""
      @currentId = 0

      @api_ids = Hash(String, Int32).new
      @normal_callback_hash = Hash(Int32, Future).new
      @subscribe_callback_hash = Hash(Int32, SubscribeCallbackType).new

      @websock = open_websocket(node_url, timeout: timeout)

      connect_to_server
    end

    # --------------------------------------------------------------------------
    # ● (private) 打开 websocket 并等待连接成功
    # --------------------------------------------------------------------------
    private def open_websocket(uri : String, timeout : Time::Span? = nil) : HTTP::WebSocket
      Log.debug { "ready to open url: #{uri}" }

      wait_connecting_channel = Channel(HTTP::WebSocket | Exception).new(1)
      connect_status = ConnectStatus::Pending

      # => 超时处理
      if timeout
        BitShares::Utility.delay(timeout) do
          if connect_status.pending?
            connect_status = ConnectStatus::Timeout
            wait_connecting_channel.send(TimeoutError.new)
          end
        end
      end

      # => 连接到服务器
      spawn do
        begin
          tmp_socket = HTTP::WebSocket.new(URI.parse(uri))

          tmp_socket.on_message { |message| on_message(message) }
          tmp_socket.on_binary { |bytes| on_message String.new(bytes) } # REMARK：crystal lang 内部 string 默认编码 UTF-8
          tmp_socket.on_close { |code, str| on_close(code, str) }

          if connect_status.pending?
            connect_status = ConnectStatus::Connected
            wait_connecting_channel.send(tmp_socket)
            tmp_socket.run
          else
            tmp_socket.close
          end
        rescue e : Socket::ConnectError
          if connect_status.pending?
            connect_status = ConnectStatus::Closed
            wait_connecting_channel.send(e)
          end
        end
      end

      # => 等待结果：超时 or 连接成功
      sock_of_err = wait_connecting_channel.receive
      raise sock_of_err if sock_of_err.is_a?(Exception)

      Log.debug { "open url successful: #{uri}" }

      # => 返回
      return sock_of_err.not_nil!
    end

    # --------------------------------------------------------------------------
    # ● (private) 处理连接状态初始化
    # --------------------------------------------------------------------------
    private def connect_to_server
      # => 初始化数据
      @currentId = 0
      @normal_callback_hash.clear
      @subscribe_callback_hash.clear
      @api_ids.clear

      # => 心跳数据
      @timer_keep_alive.try &.call
      @_send_life = KGWS_MAX_SEND_LIFE
      @_recv_life = KGWS_MAX_RECV_LIFE

      # => 登录服务器
      async_send_data(1, "login", {@username, @password}).await

      # => 初始化 API ID
      api_ids_list = @api_list.map { |api_name| async_send_data(1, api_name) }.map(&.await)
      @api_list.each_with_index { |api_name, idx| @api_ids[api_name] = api_ids_list[idx].as_i }

      # => 初始化链配置信息
      if database_api_id = @api_ids["database"]?
        @graphene_chain_config = graphene_chain_config = async_send_data(database_api_id, "get_config").await
        @graphene_address_prefix = graphene_chain_config["GRAPHENE_ADDRESS_PREFIX"].as_s
      end

      # => 启动心跳计时器
      @timer_keep_alive = start_loop_timer(seconds: 5) { __internal_keep_alive_timer_tick }

      Log.debug { "login to server done." }

      # => 更新状态：已登录
      @status = Status::Logined
    end

    # --------------------------------------------------------------------------
    # ● (private) 启动一个定时器，返回一个定时器的控制 Proc。
    # --------------------------------------------------------------------------
    private def start_loop_timer(seconds, &block) : Proc(Bool)
      timespan = Time::Span.new(seconds: seconds)
      stoped = false
      spawn do
        loop do
          break if stoped
          sleep(timespan)
          break if stoped
          block.call
        end
      end
      Fiber.yield
      return ->{ stoped = true }
    end

    private def __internal_keep_alive_timer_tick
      # => 处理接受数据心跳
      @_recv_life -= 1
      if @_recv_life <= 0
        close_websocket("heartbeat")
        return
      end
      # => 处理发送数据包心跳
      @_send_life -= 1
      if @_send_life <= 0
        @on_keep_alive.try &.call(self)
        @_send_life = KGWS_MAX_SEND_LIFE
      end
    end

    private def on_close(code, str)
      Log.debug { "websocket trigger ON_CLOSE event, str: #{str} code: #{code}. current status: #{@status}" }

      return if @status.closed?

      Log.debug { "on close clean, force trigger future, normal: #{@normal_callback_hash.size}, subscribe: #{@subscribe_callback_hash.size}" }

      # => 处于 pending、logined 状态则直接关闭
      @status = Status::Closed

      # => 取消心跳计时器
      @timer_keep_alive.try &.call
      @timer_keep_alive = nil

      # => 连接中断，关闭所有 callback 和 等待中的 await 对象。
      @normal_callback_hash.tap { |hash| hash.each { |callback_id, future| future.error(SocketClosed.new("on close, msg: #{str} code: #{code}.")) } }.clear
      @subscribe_callback_hash.tap { |hash| hash.each { |callback_id, sub_callback| sub_callback.call(false, "on_close") rescue nil } }.clear
    end

    private def on_message(message)
      # Log.info { "websocket trigger on message event, current status: #{@status}" }

      # => 重置接受数据包的心跳计数
      @_recv_life = KGWS_MAX_RECV_LIFE

      # => 解析服务器返回的数据
      json = JSON.parse(message) rescue nil
      if json.nil?
        close_websocket("invalid responsed json string.")
        return
      end

      meth = json["method"]?
      if meth && meth == "notice"
        # => 服务器推送消息 订阅方法 callback 返回 true 则移出 callback。
        callback_id = json["params"][0]
        # => REMARK: 这里相同的CALLBACK存在触发多次回调的可能性，所以需要判断下callback是否还存在(或已经被删除了)。
        # => 猜测原因可能是 部分节点双出导致？同一个 block apply 了2次？
        if callback = @subscribe_callback_hash[callback_id]?
          # => REMARK: 该 callback 回调不应该 block 当前 fiber
          @subscribe_callback_hash.delete(callback_id) if callback.call(true, json["params"][1])
        else
          Log.error { "unknown websocket response, notice type." }
        end
      else
        # => 普通请求   callback id 完成，移除。
        callback_id = json["id"]
        if future = @normal_callback_hash.delete(callback_id)
          # => 返回
          error = json["error"]?
          if error
            future.error(ResponseError.new(error))
          else
            future.done(json["result"])
          end
        else
          Log.error { "unknown websocket response, normal callback." }
        end
      end
    end

    private def async_send_data(api_id : Int32, method : String, params : Tuple | Array | Nil = nil, callback : SubscribeCallbackType? = nil) : Future
      # => ID计数器
      @currentId += 1

      # => 针对部分 api 第一个参数是 callback 的情况处理   REMARK：callback仅支持在第一个参数的情况
      # => [database api]
      # => set_subscribe_callback
      # => set_pending_transaction_callback
      # => set_block_applied_callback
      # => subscribe_to_market
      #
      # => [network_broadcast api]
      # => broadcast_transaction_with_callback

      # => 处理 callback 参数
      final_params = if callback
                       @subscribe_callback_hash[@currentId] = callback
                       case params
                       in Tuple
                         {@currentId, *params}
                       in Array
                         tmp = Array(typeof(params[0]) | typeof(@currentId)).new
                         tmp << @currentId
                         tmp.concat(params)
                         tmp
                       in Nil
                         {@currentId}
                       end
                     else
                       params || Tuple.new
                     end

      # => 序列化 TODO: PublicKey to json 可能缺少公钥前缀？
      json = {id: @currentId, method: "call", params: {api_id, method, final_params}}

      # => 发送数据
      @_send_life = KGWS_MAX_SEND_LIFE
      @websock.try &.send(json.to_graphene_json(graphene_address_prefix: @graphene_address_prefix))

      future = @normal_callback_hash[@currentId] = Future.new
      return future
    end
  end

  class GrapheneConnection
    # --------------------------------------------------------------------------
    # ● (public) 调用API
    # => api_name   - database、network_broadcast、history、custom_operations
    # => REMARK：asset api大部分节点默认未开启。
    # --------------------------------------------------------------------------
    def call(api_name, method, params = nil, callback : GrapheneWebSocket::SubscribeCallbackType? = nil)
      call_api(api_name, method, params, callback: callback)
    end

    def call_db(method, params = nil, callback : GrapheneWebSocket::SubscribeCallbackType? = nil)
      call("database", method, params, callback: callback)
    end

    def call_net(method, params = nil, callback : GrapheneWebSocket::SubscribeCallbackType? = nil)
      call("network_broadcast", method, params, callback: callback)
    end

    def call_history(method, params = nil, callback : GrapheneWebSocket::SubscribeCallbackType? = nil)
      call("history", method, params, callback: callback)
    end

    def call_custom_operations(method, params = nil, callback : GrapheneWebSocket::SubscribeCallbackType? = nil)
      call("custom_operations", method, params, callback: callback)
    end

    def call_asset(method, params = nil, callback : GrapheneWebSocket::SubscribeCallbackType? = nil)
      call("asset", method, params, callback: callback)
    end

    def batch_call_api(*args)
      return safe_get_websocket.multi_call(*args)
    end

    getter config : BitShares::Config

    @api_nodes : Array(String)
    @sock : GrapheneWebSocket? = nil

    getter graphene_chain_id = ""
    getter graphene_address_prefix = ""
    getter graphene_core_asset_symbol = ""
    getter graphene_chain_properties : JSON::Any? = nil
    getter graphene_chain_config : JSON::Any? = nil

    def initialize(@config : BitShares::Config)
      if @config.api_nodes.is_a?(String)
        @api_nodes = [@config.api_nodes.as(String)]
      else
        @api_nodes = @config.api_nodes.as(Array(String))
      end

      @reconnect_times = 0

      gen_websocket # TODO:consider delay? init

      sync_query_network_arguments
    end

    def close
      @sock.try &.close_websocket
      @sock = nil
    end

    # --------------------------------------------------------------------------
    # ● (private) 获取连接的节点地址（根据数组大小进行轮询）
    # --------------------------------------------------------------------------
    private def gen_next_ws_node
      url = @api_nodes[@reconnect_times % @api_nodes.size]
      @reconnect_times += 1
      return url
    end

    private def gen_websocket : GrapheneWebSocket
      if @sock.nil?
        Log.info { "client gen websocket first time." }
      else
        Log.info { "client gen websocket again." }
      end
      s = @sock = GrapheneWebSocket.new(gen_next_ws_node, Time::Span.new(seconds: 15), @config.api_list)
      s.on_keep_alive do |sock|
        if sock.status.logined?
          begin
            head_block_number = sock.call("database", "get_objects", [["2.1.0"]]).as_a.first["head_block_number"].as_i.to_u64
            Log.info { "heartbeat tick ok, head block number: #{head_block_number}." }
          rescue e : Exception
            Log.error(exception: e) { "heartbeat tick failed" }
          end
        end
      end
      return s
    end

    private def safe_get_websocket : GrapheneWebSocket
      sock = @sock
      if sock.nil?
        # => 初始化网络连接
        return gen_websocket
      else
        # => 状态处理
        case sock.status
        in .pending?, .logined? # => 正在初始化、已经连接中
          return sock
        in .closed?, .closing? # => 正在断开连接、已断开连接
          if @config.auto_restart
            return gen_websocket
          else
            # => TODO:ing
            raise "WebSocket disconnected..."
            # return BitShares::Promise.reject("websock disconnected...")
          end
        end
      end
    end

    private def sync_query_network_arguments
      sock = safe_get_websocket

      @graphene_chain_properties = sock.call("database", "get_chain_properties", nil)
      @graphene_chain_config = sock.graphene_chain_config

      @graphene_chain_id = @graphene_chain_properties.not_nil!["chain_id"].as_s
      @graphene_core_asset_symbol = @graphene_chain_config.not_nil!["GRAPHENE_SYMBOL"].as_s
      @graphene_address_prefix = @graphene_chain_config.not_nil!["GRAPHENE_ADDRESS_PREFIX"].as_s
    end

    private def call_api(api_name : String, method : String, params, callback : GrapheneWebSocket::SubscribeCallbackType? = nil)
      return safe_get_websocket.call(api_name, method, params, callback: callback)
    end
  end
end
