require "http/web_socket"
require "json"

module BitShares
  class GrapheneWebSocket
    KGWS_MAX_SEND_LIFE = 4
    KGWS_MAX_RECV_LIFE = 8

    class BaseError < Exception
    end

    class ResponseError < BaseError
      getter error : JSON::Any

      def initialize(err)
        super()
        @error = err
      end

      def inspect(io : IO) : Nil
        @error.inspect(io)
      end

      def to_s(io : IO) : Nil
        @error.to_s(io)
      end
    end

    class TimeoutError < BaseError
    end

    class SocketClosed < BaseError
    end

    alias ChannelDataType = JSON::Any | BaseError

    enum Status
      Pending

      Connected
      Timeout

      Logined

      Closed
      Closing
    end

    @websock : HTTP::WebSocket? = nil
    getter status = Status::Pending
    @timer_keep_alive : Proc(Nil)? = nil
    @_send_life = KGWS_MAX_SEND_LIFE
    @_recv_life = KGWS_MAX_RECV_LIFE

    # 同步调用服务器 API 接口
    def call(api_name : String, method : String, params)
      raise SocketClosed.new unless @status.logined?
      return async_send_data(@api_ids[api_name], method, params).await
    end

    # 同时调用多个 API 接口，具体参数参考 `call` 方法。
    def multi_call(*args)
      args.each { |arg| async_call(arg[0], arg[1], arg[2]?) }
      return await_all(args.size)
    end

    # 异步调用服务器 API 接口
    def async_call(api_name : String, method : String, params)
      raise SocketClosed.new unless @status.logined?
      async_send_data(@api_ids[api_name], method, params)
    end

    # 等待获取异步调用结果
    def await : JSON::Any
      return await_all.first
    end

    # 等待获取1个或多个异步调用结果
    def await_all(n = 1) : Array(JSON::Any)
      all_result = [] of JSON::Any

      Array(ChannelDataType).new(n) { @channel.receive }.each do |result|
        if result.is_a?(BaseError)
          raise result
        else
          all_result << result
        end
      end

      return all_result
    end

    # 关闭websocket连接，会自动触发 on_close 事件。
    def close_websocket(reason = "")
      return if @status.closed? || @status.closing?
      @status = Status::Closing
      @websock.try &.close
    end

    # 事件函数：心跳包。
    def on_keep_alive(&@on_keep_alive : GrapheneWebSocket ->)
    end

    # TODO: ode_url, logger, api_list, keep_alive_callback = nil
    def initialize(node_url : String, timeout : Time::Span? = nil, @api_list = ["database", "network_broadcast", "history"])
      @channel = Channel(ChannelDataType).new(1)

      @username = ""
      @password = ""
      @currentId = 0

      @api_ids = Hash(String, Int32).new
      @normal_callback_hash = Hash(Int32, Bool).new
      @subscribe_callback_hash = Hash(Int32, Serialize::Raw::SubscribeCallbackType).new

      @websock = open_websocket(node_url, timeout: timeout)

      connect_to_server
    end

    # --------------------------------------------------------------------------
    # ● (private) 打开 websocket 并等待连接成功
    # --------------------------------------------------------------------------
    private def open_websocket(uri : String, timeout : Time::Span? = nil) : HTTP::WebSocket
      wait_connecting_channel = Channel(HTTP::WebSocket | Exception).new(1)
      connect_status = Status::Pending

      # => 超时处理
      if timeout
        BitShares::Utility.delay(timeout) do
          if connect_status.pending?
            connect_status = Status::Timeout
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
            connect_status = Status::Connected
            wait_connecting_channel.send(tmp_socket)
            tmp_socket.run
          else
            tmp_socket.close
          end
        rescue e : Socket::ConnectError
          if connect_status.pending?
            connect_status = Status::Closed
            wait_connecting_channel.send(e)
          end
        end
      end

      # => 等待结果：超时 or 连接成功
      sock_of_err = wait_connecting_channel.receive
      raise sock_of_err if sock_of_err.is_a?(Exception)

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
      async_send_data(1, "login", [@username, @password]).await

      # => 初始化 API ID
      @api_list.map { |api_name| async_send_data(1, api_name) }
      api_ids_list = await_all(@api_list.size)
      @api_list.each_with_index { |api_name, idx| @api_ids[api_name] = api_ids_list[idx].as_i }

      # => 启动心跳计时器
      @timer_keep_alive = start_loop_timer(seconds: 5) { __internal_keep_alive_timer_tick }

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
      return if @status.closed?

      # => 处于 pending、logined 状态则直接关闭
      @status = Status::Closed

      # => 取消心跳计时器
      @timer_keep_alive.try &.call
      @timer_keep_alive = nil

      # => 连接中断，关闭所有 callback 和 等待中的 await 对象。
      @normal_callback_hash.tap { |hash| hash.each { |callback_id, _| @channel.send SocketClosed.new } }.clear
      @subscribe_callback_hash.tap { |hash| hash.each { |callback_id, sub_callback| sub_callback.call(false, "on_close") } }.clear
    end

    private def on_message(message)
      # => 重置接受数据包的心跳计数
      @_recv_life = KGWS_MAX_RECV_LIFE

      # => 解析服务器返回的数据
      json = JSON.parse(message) rescue nil
      if json.nil?
        close_websocket("invalid responsed json string.")
      else
        meth = json["method"]?
        if meth && meth == "notice"
          # => 服务器推送消息 订阅方法 callback 返回 true 则移出 callback。
          callback_id = json["params"][0]
          @subscribe_callback_hash.delete(callback_id) if @subscribe_callback_hash[callback_id].call(true, json["params"][1])
        else
          callback_id = json["id"]
          # => 普通请求   callback id 完成，移除。
          @normal_callback_hash.delete(callback_id)
          # => 返回
          error = json["error"]?
          if error
            @channel.send ResponseError.new(error)
          else
            @channel.send json["result"]
          end
        end
      end
    end

    private def async_send_data(api_id : Int32, method : String, params = nil)
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

      if params.nil?
        params = Serialize::Raw.new([] of Serialize::Raw)
      else
        params = Serialize::Raw.new(params)
      end

      # pp params.as_a

      # TODO:replace proc to id
      # meth = params[1]
      # if meth == 'set_subscribe_callback' or
      #   meth == 'subscribe_to_market' or
      #   meth == 'broadcast_transaction_with_callback' or
      #   meth == 'set_pending_transaction_callback'

      #   # => 订阅的 callback 替换为 @currentId 传送到服务器。
      #   sub_calback = params[2][0]
      #   params[2][0] = @currentId

      #   # => 保存订阅callback
      #   @subscribe_callback_hash[@currentId] = sub_calback
      # end

      new_params = [] of Serialize::Raw

      params.as_a.each_with_index do |value_or_callback, idx|
        callback = value_or_callback.as_callback?
        if callback
          if idx == 0
            @subscribe_callback_hash[@currentId] = callback
            # => 订阅的 callback 替换为 @currentId 传送到服务器。
            value_or_callback.value = @currentId

            new_params << value_or_callback
          else
            raise "The CALLBACK can only be at the first element of the params parameter."
          end
        else
          new_params << value_or_callback
        end
      end

      # => 序列化
      json = {"id" => @currentId, "method" => "call", "params" => [api_id, method, Serialize::Raw.new(new_params)]}

      # => 发送数据
      @_send_life = KGWS_MAX_SEND_LIFE
      @websock.try &.send(json.to_json)
      @normal_callback_hash[@currentId] = true

      # => 返回 TODO:改成 future 对象方便以后  await？
      return self
    end
  end

  class GrapheneConnection
    # --------------------------------------------------------------------------
    # ● (public) 异步调用API
    # => api_name   - database、network_broadcast、history、custom_operations
    # => REMARK：asset api大部分节点默认未开启。
    # --------------------------------------------------------------------------

    def call(api_name, method, params = nil)
      call_api(api_name, method, params)
    end

    def call_db(method, params = nil)
      call("database", method, params)
    end

    def call_net(method, params = nil)
      call("network_broadcast", method, params)
    end

    def call_history(method, params = nil)
      call("history", method, params)
    end

    def call_custom_operations(method, params = nil)
      call("custom_operations", method, params)
    end

    def call_asset(method, params = nil)
      call("asset", method, params)
    end

    # # --------------------------------------------------------------------------
    # # ● (public) 同步调用API，支持安全和非安全调用，安全调用失败时返回nil，非安全调用失败抛出异常。
    # # => api_name   - database、network_broadcast、history、custom_operations
    # # => REMARK：asset api大部分节点默认未开启。
    # # --------------------------------------------------------------------------
    # def call(*args)
    #   async_call(*args).await
    # end

    # def call?(*args)
    #   async_call(*args).await?
    # end

    # def call_db(*args)
    #   async_call_db(*args).await
    # end

    # def call_db?(*args)
    #   async_call_db(*args).await?
    # end

    # def call_net(*args)
    #   async_call_net(*args).await
    # end

    # def call_net?(*args)
    #   async_call_net(*args).await?
    # end

    # def call_history(*args)
    #   async_call_history(*args).await
    # end

    # def call_history?(*args)
    #   async_call_history(*args).await?
    # end

    # def call_custom_operations(*args)
    #   async_call_custom_operations(*args).await
    # end

    # def call_custom_operations?(*args)
    #   async_call_custom_operations(*args).await?
    # end

    # def call_asset(*args)
    #   async_call_asset(*args).await
    # end

    # def call_asset?(*args)
    #   async_call_asset(*args).await?
    # end

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

    private def gen_websocket
      # TODO:心跳 待处理
      # lambda { |sock| on_keep_alive_callback(sock) # TODO:args lambda
      @sock = GrapheneWebSocket.new(gen_next_ws_node, Time::Span.new(seconds: 15), @config.api_list)
    end

    private def safe_get_websocket : GrapheneWebSocket
      sock = @sock
      if sock.nil?
        # => 初始化网络连接
        gen_websocket
        return @sock.not_nil!
      else
        # => 状态处理

        # Pending

        # Connected
        # Timeout

        # Logined

        # Closed
        # Closing

        case sock.status
        when .pending?, .logined? # => 正在初始化、已经连接中
          return sock
        when .closed?, .closing? # => 正在断开连接、已断开连接
          if @config.auto_restart
            gen_websocket
            return sock
          else
            # => TODO:ing
            raise "WebSocket disconnected..."
            # return BitShares::Promise.reject("websock disconnected...")
          end
        else
          raise "unknown socket status: #{sock.status}"
        end
      end
    end

    private def sync_query_network_arguments
      data_array = safe_get_websocket.multi_call({"database", "get_chain_properties"}, {"database", "get_config"})

      @graphene_chain_properties = data_array[0]
      @graphene_chain_config = data_array[1]
      @graphene_chain_id = @graphene_chain_properties.not_nil!["chain_id"].as_s
      @graphene_core_asset_symbol = @graphene_chain_config.not_nil!["GRAPHENE_SYMBOL"].as_s
      @graphene_address_prefix = @graphene_chain_config.not_nil!["GRAPHENE_ADDRESS_PREFIX"].as_s
    end

    private def call_api(api_name : String, method : String, params)
      return safe_get_websocket.call(api_name, method, params)
    end

    # TODO:heart beat
    # #--------------------------------------------------------------------------
    # # ● (private) 心跳。
    # #--------------------------------------------------------------------------
    # def on_keep_alive_callback(sock)
    #   cb_then = lambda do |data|
    #     @config.logger&.debug 'heartbeat tick ok~'
    #   end
    #   cb_catch = lambda do |error|
    #     @config.logger&.warn "heartbeat tick failed, error: #{error}."
    #   end
    #   async_call_db("get_objects", [['2.1.0']]).then(cb_then, cb_catch) if sock.connected?
    # end

  end
end
