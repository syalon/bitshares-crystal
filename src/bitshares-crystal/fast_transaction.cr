# TODO:未完成
require "log"

# => 快速交易构造器
# => 目的：减少网络交互，尽快广播。
# => 和普通的区别
# => 1、不会设置 fee
# => 2、会查询 head block info
# => 3、不会等待 callback
class BitShares::FastTransaction
  Log = ::Log.for("fast.tx")

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

  # 广播到链上。广播成功返回 txid，失败抛出异常。
  # dynamic_global_properties - 即：2.1.0 对象
  def broadcast(data_dynamic_global_properties) : Bytes
    return broadcast_core(tx_finalize(data_dynamic_global_properties))
  end

  private def operations_to_object
    return @operations.map { |ops| Operations::T_operation.to_json(ops, @client.graphene_address_prefix) }
  end

  private def tx_finalize(data_dynamic_global_properties)
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

    head_block_ts = BitShares::Utility.parse_time_string_i64(data_dynamic_global_properties["time"].as_s)
    now_ts = BitShares::Utility.now_ts
    if now_ts - head_block_ts > 30
      base_expiration_sec = head_block_ts
    else
      base_expiration_sec = now_ts > head_block_ts ? now_ts : head_block_ts
    end

    @expiration = (base_expiration_sec + @client.config.tx_expiration_seconds).to_u32
    @ref_block_num = (data_dynamic_global_properties["head_block_number"].as_i & 0xffff).to_u16
    @ref_block_prefix = data_dynamic_global_properties["head_block_id"].as_s.hexbytes[4, 4].to_unsafe.as(UInt32*).value

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
    txid = BitShares::Utility.sha256(transaction_data)[0, 20]

    sign_buffer = @client.graphene_chain_id.hexbytes + transaction_data

    @signatures = @client.wallet.sign(BitShares::Utility.sha256(sign_buffer), @sign_keys_hash)

    raise "not signed" if @signatures.empty?
    raise "no operations" if @operations.empty?

    signed_trx_data = {
      "ref_block_num"    => @ref_block_num,
      "ref_block_prefix" => @ref_block_prefix,
      "expiration"       => @expiration,
      "operations"       => @operations,
      "extensions"       => @extensions,
      "signatures"       => @signatures,
    }

    obj = Operations::T_signed_transaction.to_json(signed_trx_data, @client.graphene_address_prefix)

    # => 广播成功无返回值，广播失败抛出异常。
    @client.call_net("broadcast_transaction", [obj])

    return txid
  end
end
