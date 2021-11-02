require "yaml"

module BitShares
  # => TODO:这里面是库的默认值，需要调整。

  class Config
    property auto_restart = true # => 是否重新启动
    property api_nodes : String | Array(String) = ""
    property api_list = [] of String        # => 开启的api列表
    property tx_expiration_seconds = 15_i32 # => 交易过期时间（单位：秒），参数 0 则不处理交易 timeout 。

    # property logger
    property task : YAML::Any? = nil

    def initialize
      # @auto_restart = true

      switch_bts_mainnet!

      # => asset、crypto、orders、network_node、block、debug
      @api_list = ["database", "network_broadcast", "history", "custom_operations"]

      # @tx_expiration_seconds = 15_i32
      # @logger = Logger.new(STDOUT)
      # @task = nil
    end

    def initialize
      initialize
      yield
    end

    def switch_bts_testnet!
      # TODO: api
      @api_nodes = "ws://api-test.bts.btspp.io:10099"
    end

    def switch_bts_mainnet!
      @api_nodes = "wss://api.bts.btspp.io:10100"
    end
  end
end
