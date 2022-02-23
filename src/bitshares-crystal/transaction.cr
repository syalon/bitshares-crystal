# TODO:未完成
require "log"

module BitShares
  # 交易构造器。
  class Transaction
    Log = ::Log.for("tx")

    def initialize(client : Client)
      @client = client

      @ref_block_num = 0_u16
      @ref_block_prefix = 0_u32
      @expiration = 0_u32
      @operations = [] of Array(Int8 | Serialize::Raw)
      @extensions = [] of String
      @signatures = [] of Bytes

      @sign_keys_hash = Hash(String, Secp256k1Zkp::PrivateKey).new
    end

    # 添加 operation 到当前交易对象。
    def add_operation(opcode : Blockchain::Operations, opdata)
      @operations << [opcode.value, Serialize::Raw.new(opdata)]
    end

    # 添加交易需要签名的私钥，不添加则默认使用钱包中的所有私钥进行签名。
    def add_sign_keys(sign_keys_hash : Hash(String, Secp256k1Zkp::PrivateKey))
      @sign_keys_hash.merge!(sign_keys_hash)
    end

    # :ditto:
    def add_sign_key(public_key : String, private_key : Secp256k1Zkp::PrivateKey)
      @sign_keys_hash[public_key] = private_key
    end

    # 广播到链上。
    def broadcast
      set_required_fees
      return broadcast_core(tx_finalize)
    end

    private def operations_to_object
      return @operations.map { |ops| Operations::T_operation.to_json(ops, @client.graphene_address_prefix) }
    end

    private def set_required_fees
      result = Hash(String, Bool).new
      @operations.each { |op_ary| result[op_ary.last.as(Serialize::Raw).as_h["fee"].as_h["asset_id"].as_s] = true }
      fee_asset_id = result.keys.first

      op_fee_array = @client.call_db("get_required_fees", [operations_to_object, fee_asset_id]).as_a

      op_fee_array.each_with_index do |op_fee, idx|
        # REMARK：如果OP为提案类型，这里会把提案的手续费以及提案中对应的所有实际OP的手续费全部返回。（因此需要判断。）
        op_fee_is_ary = op_fee.as_a?
        op_fee = op_fee_is_ary[0] if op_fee_is_ary
        op_fee = op_fee.as_h
        # => 更新
        @operations[idx].last.as(Serialize::Raw).as_h["fee"] = Serialize::Raw.new(op_fee)
      end

      # => return
      return op_fee_array
    end

    private def tx_finalize
      data = @client.call_db("get_objects", [["2.1.0"]]).as_a.first

      # {"id"=>"2.1.0",
      #  "head_block_number"=>29539824,
      #  "head_block_id"=>"01c2bdf047a79681cec825657aa6ae9ad4503887",
      #  "time"=>"2018-08-12T05:17:39",
      #  "current_witness"=>"1.6.17",
      #  "next_maintenance_time"=>"2018-08-12T06:00:00",
      #  "last_budget_time"=>"2018-08-12T05:00:00",
      #  "witness_budget"=>85000000,
      #  "accounts_registered_this_interval"=>5,
      #  "recently_missed_count"=>0,
      #  "current_aslot"=>29695556,
      #  "recent_slots_filled"=>"340282366920938463463374607431768211455",
      #  "dynamic_flags"=>0,
      #  "last_irreversible_block_num"=>29539803}

      head_block_ts = BitShares::Utility.parse_time_string_i64(data["time"].as_s)
      now_ts = BitShares::Utility.now_ts
      if now_ts - head_block_ts > 30
        base_expiration_sec = head_block_ts
      else
        base_expiration_sec = now_ts > head_block_ts ? now_ts : head_block_ts
      end

      @expiration = (base_expiration_sec + @client.config.tx_expiration_seconds).to_u32
      @ref_block_num = (data["head_block_number"].as_i & 0xffff).to_u16
      @ref_block_prefix = data["head_block_id"].as_s.hexbytes[4, 4].to_unsafe.as(UInt32*).value

      trx_data = {
        "ref_block_num"    => @ref_block_num,
        "ref_block_prefix" => @ref_block_prefix,
        "expiration"       => @expiration,
        "operations"       => @operations,
        "extensions"       => @extensions,
      }

      return Operations::T_transaction.to_binary(trx_data, @client.graphene_address_prefix)
    end

    private def broadcast_core(transaction_data : Bytes)
      sign_buffer = @client.graphene_chain_id.hexbytes + transaction_data

      @signatures = @client.wallet.sign(BitShares::Utility.sha256(sign_buffer), @sign_keys_hash)

      raise "not signed" if @signatures.empty?
      raise "no operations" if @operations.empty?

      result_channel = Channel(JSON::Any | String | Exception).new(1)
      got_responsed = false

      broadcast_transaction_callback = ->(success : Bool, data : JSON::Any | String) {
        Log.info { "tx broadcast callback invoked, success: #{success}, got_responsed: #{got_responsed}" }

        if !got_responsed
          got_responsed = true
          # TODO: cancel timeout timer?
          result_channel.send data # success?
        end
        # remove broadcast_transaction_with_callback callback
        return true
      }

      # => 超时处理
      if @client.config.tx_expiration_seconds > 0
        BitShares::Utility.delay(@client.config.tx_expiration_seconds) do
          Log.info { "tx broadcast timeout invoked, got_responsed: #{got_responsed}" }
          if !got_responsed
            got_responsed = true
            # TODO: timeout 查询 tx id是否进块，而不是单纯忽略。待处理
            # TODO:cancel callback call
            result_channel.send(TimeoutError.new)
          end
        end
      end

      signed_trx_data = {
        "ref_block_num"    => @ref_block_num,
        "ref_block_prefix" => @ref_block_prefix,
        "expiration"       => @expiration,
        "operations"       => @operations,
        "extensions"       => @extensions,
        "signatures"       => @signatures,
      }

      obj = Operations::T_signed_transaction.to_json(signed_trx_data, @client.graphene_address_prefix)

      # TODO:异常后取消定时器

      @client.call_net("broadcast_transaction_with_callback", [broadcast_transaction_callback, obj])

      resp = result_channel.receive
      case resp
      when String
        Log.info { "tx result, error string: #{resp}" }
        raise resp
      when Exception
        Log.error(exception: resp) { "tx result, exception." }
        raise resp
      else
        return resp.as(JSON::Any)
      end
    end
  end
end
