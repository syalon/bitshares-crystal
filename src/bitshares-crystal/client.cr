require "./connection"

module BitShares
  class Client < GrapheneConnection
    @wallet : Wallet? = nil
    @cache : Cache? = nil

    # 获取关联的 `wallet` 对象。
    def wallet : Wallet
      @wallet.not_nil!
    end

    # 获取关联的 `cache` 对象。
    def cache : Cache
      @cache.not_nil!
    end

    def initialize(config_object : BitShares::Config? = nil)
      @cache = Cache.new(self)
      @wallet = Wallet.new(self)
      super(config_object || BitShares::Config.new)
    end

    # API - 根据对象ID或者ID数组查询对象。
    def query_objects(object_id_or_id_array : String | Array(String)) : Hash(String, JSON::Any)
      object_id_array = if object_id_or_id_array.is_a?(String)
                          [object_id_or_id_array]
                        else
                          object_id_or_id_array.as(Array)
                        end

      result = {} of String => JSON::Any
      return result if object_id_array.empty?

      call_db("get_objects", [object_id_array]).as_a.each { |obj| result[obj["id"].as_s] = obj if obj && obj.raw }

      return result
    end

    # API - 根据对象ID查询对象。
    #
    # DEPRECATED: Use `query_one_object?`
    def query_one_object(oid : String) : JSON::Any?
      return query_one_object?(oid)
    end

    def query_one_object?(oid : String) : JSON::Any?
      return query_objects(oid)[oid]?
    end

    def query_one_object!(oid : String) : JSON::Any
      return query_one_object?(oid).not_nil!
    end

    # API - 查询账号信息。
    #
    # DEPRECATED: Use `query_account?`
    def query_account(account_name_or_id : String) : JSON::Any?
      return query_account?(account_name_or_id)
    end

    def query_account?(account_name_or_id : String) : JSON::Any?
      data = call_db("get_accounts", [[account_name_or_id, false]]).as_a?
      if data && !data.empty?
        return data.first
      else
        return nil
      end
    end

    def query_account!(account_name_or_id : String) : JSON::Any?
      return query_account?(account_name_or_id).not_nil!
    end

    # API - 查询资产信息。
    #
    # DEPRECATED: Use `query_asset?`
    def query_asset(asset_symbol_or_id : String) : JSON::Any?
      return query_asset?(asset_symbol_or_id)
    end

    def query_asset?(asset_symbol_or_id : String) : JSON::Any?
      data = call_db("get_assets", [[asset_symbol_or_id, false]]).as_a?
      if data && !data.empty?
        return data.first
      else
        return nil
      end
    end

    def query_asset!(asset_symbol_or_id : String) : JSON::Any?
      return query_asset?(asset_symbol_or_id).not_nil!
    end

    # API - 根据见证人账号ID查询见证人信息
    def query_witness_by_id(witness_account_id : String) : JSON::Any?
      call_db("get_witness_by_account", [witness_account_id])
    end

    # API - 查询见证人信息
    def query_witness(witness_account_name_or_id)
      account = cache.query_account(witness_account_name_or_id)
      return query_witness_by_id(account.not_nil!["id"].as_s)
    end

    # :nodoc:
    # #--------------------------------------------------------------------------
    # # ● (public) 构造并广播交易。
    # #--------------------------------------------------------------------------
    # def build(opname = nil, opdata = nil)
    #   tx = Transaction.new(self)
    #   if opname and opdata
    #     opdata[:fee] ||= default_fee
    #     tx.add_operation opname, opdata
    #   end
    #   yield tx if defined?(yield)
    #   return tx.broadcast
    # end
    def build(opname : Blockchain::Operations? = nil, opdata = nil)
      # tx = T1.new(nil)
      # yield tx

      tx = Transaction.new(self)
      if opname && opdata
        # TODO:
        tx.add_operation opname, opdata
      end
      yield tx
      return tx.broadcast
      # return true
    end

    # OP - 转账操作
    # *from* 付款账号
    # *to* 收款账号
    # *asset_amount* 转账数量
    # *asset_id* 转账资产名称或ID。
    # *memo* 转账备注
    def do_transfer(from, to, asset_amount, asset_id, memo = nil)
      from_data = cache.query_account(from).not_nil!
      to_data = cache.query_account(to).not_nil!
      asset_data = cache.query_asset(asset_id).not_nil!

      build { |tx|
        tx.add_operation :transfer,
          {
            :fee    => default_fee,
            :from   => from_data["id"].as_s,
            :to     => to_data["id"].as_s,
            :amount => {:amount => (asset_amount.to_f64 * (10 ** asset_data["precision"].as_i)).to_i64, :asset_id => asset_id},
            :memo   => if memo
              memo_private_key = wallet.get_private_key?(from_data.dig("options", "memo_key").as_s).not_nil!
              to_pubkey = Secp256k1Zkp::PublicKey.from_wif(to_data.dig("options", "memo_key").as_s, @graphene_address_prefix)
              BitShares::Crypto.gen_memo_object(memo, memo_private_key, to_pubkey, @graphene_address_prefix)
            end,
          }
      }
    end

    # OP - 创建账号
    def do_account_create(registrar, referrer, referrer_percent, voting_account, name, owner_public_key, active_public_key, memo_public_key = nil)
      op_data = {
        :fee              => default_fee,
        :registrar        => registrar,
        :referrer         => referrer,
        :referrer_percent => referrer_percent,
        :name             => name,
        :owner            => {
          :weight_threshold => 1,
          :account_auths    => [] of Array(String | Int32),
          :key_auths        => [[owner_public_key, 1]],
          :address_auths    => [] of Array(String | Int32),
        },
        :active => {
          :weight_threshold => 1,
          :account_auths    => [] of Array(String | Int32),
          :key_auths        => [[active_public_key, 1]],
          :address_auths    => [] of Array(String | Int32),
        },
        :options => {
          :memo_key       => memo_public_key || active_public_key,
          :voting_account => voting_account,
          :num_witness    => 0,
          :num_committee  => 0,
          :votes          => [] of String, # TODO:
        },
      }

      build { |tx| tx.add_operation Blockchain::Operations::Account_create, op_data }
    end

    # OP - 更新见证人
    def do_witness_update(witness_account_name_or_id, new_url = nil, new_signing_key = nil)
      witness = cache.query_witness(witness_account_name_or_id).not_nil!

      opdata = {
        :fee             => default_fee,
        :witness         => witness["id"].as_s,
        :witness_account => witness["witness_account"].as_s,

        :new_url => if new_url && !new_url.empty?
          new_url
        end,

        :new_signing_key => if new_signing_key && !new_signing_key.empty?
          new_signing_key
        end,
      }

      build { |tx| tx.add_operation :witness_update, opdata }
    end

    # OP - 发布喂价 TODO:ing
    def do_asset_publish_feed(publisher_id, core_asset, feeds)
      build { |tx|
        feeds.each do |feed_info|
          asset = feed_info[:asset]
          short_backing_asset = feed_info[:short_backing_asset]

          settlement_price = feed_info[:settlement_price]     # => ASSET / BACKASSET
          core_exchange_rate = feed_info[:core_exchange_rate] # => ASSET / COREASSET

          # => REMARK：小数精度
          decimal_precision = 8

          base_amount = (settlement_price * 10**decimal_precision).round
          quote_amount = (10**(decimal_precision - asset["precision"].as_i + short_backing_asset["precision"].as_i)).ceil
          rat_price = nil # Rational(base_amount, quote_amount) # TODO:ing

          base_amount = (core_exchange_rate * 10**decimal_precision).round
          quote_amount = (10**(decimal_precision - asset["precision"].as_i + core_asset["precision"].as_i)).ceil
          rat_cer = nil # Rational(base_amount, quote_amount)# TODO:ing

          # => 防止溢出
          max_value = 2**63
          raise "Invalid amount value" if rat_price.denominator >= max_value
          raise "Invalid amount value" if rat_price.numerator >= max_value
          raise "Invalid amount value" if rat_cer.denominator >= max_value
          raise "Invalid amount value" if rat_cer.numerator >= max_value

          op = {
            :fee       => default_fee,
            :publisher => publisher_id,
            :asset_id  => asset["id"].as_s,
            :feed      => {
              :settlement_price => {
                :base  => {:asset_id => asset["id"].as_s, :amount => rat_price.numerator},
                :quote => {:asset_id => short_backing_asset["id"].as_s, :amount => rat_price.denominator},
              },
              :maintenance_collateral_ratio => feed_info[:maintenance_collateral_ratio],
              :maximum_short_squeeze_ratio  => feed_info[:maximum_short_squeeze_ratio],
              :core_exchange_rate           => {
                :base  => {:asset_id => asset["id"].as_s, :amount => rat_cer.numerator},
                :quote => {:asset_id => core_asset["id"].as_s, :amount => rat_cer.denominator}, # => REMARK:CER的quote必须是CORE核心资产。
              },
            },
            # => TODO:not supported
            # => extensions initial_collateral_ratio
          }

          tx.add_operation :asset_publish_feed, op
        end
      }
    end

    # OP - 存储账号自定义数据（REMARK：在 custom OP 的 data 字段中存储数据）
    def do_account_storage_map_core(account, account_storage_map_opdata)
      op_custom = {
        :fee   => default_fee,
        :payer => to_account_id(account),
        :id    => 0,
        :data  => Operations::T_custom_plugin_operation.to_binary({:data => [0, account_storage_map_opdata]}, @graphene_address_prefix),
      }

      build { |tx| tx.add_operation :custom, op_custom }
    end

    def do_account_storage_map(account, remove, catalog, key_values)
      op_account_storage_map = {
        :remove     => remove,
        :catalog    => catalog,
        :key_values => key_values,
      }
      return do_account_storage_map_core(account, op_account_storage_map)
    end

    def make_samet_fund_create(account, asset_id_or_symbol, balance, fee_rate)
      asset_data = cache.query_asset(asset_id_or_symbol).not_nil!
      opdata = {
        :fee           => default_fee,
        :owner_account => to_account_id(account),
        :asset_type    => asset_data["id"].as_s,
        :balance       => (balance.to_f64 * (10 ** asset_data["precision"].as_i)).to_i64,
        :fee_rate      => (fee_rate * 1000000).to_u32,
      }
      return opdata
    end

    def do_samet_fund_create(account, asset_id_or_symbol, balance, fee_rate)
      build { |tx| tx.add_operation :samet_fund_create, make_samet_fund_create(account, asset_id_or_symbol, balance, fee_rate) }
    end

    def make_samet_fund_delete(account, fund : JSON::Any | String)
      fund_id = if fund.is_a?(String)
                  fund
                else
                  fund["id"].as_s
                end
      opdata = {
        :fee           => default_fee,
        :owner_account => to_account_id(account),
        :fund_id       => fund_id,
      }
      return opdata
    end

    def do_samet_fund_delete(account, fund : JSON::Any | String)
      build { |tx| tx.add_operation :samet_fund_delete, make_samet_fund_delete(account, fund) }
    end

    # TODO:
    #   class OP_samet_fund_update < T_composite
    #     add_field :fee, T_asset
    #     add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
    #     add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

    #     add_field :delta_amount, Tm_optional(T_asset)
    #     add_field :new_fee_rate, Tm_optional(T_uint32)

    #     add_field :extensions, Tm_set(T_future_extensions)
    #   end

    def make_samet_fund_borrow(borrower, fund : JSON::Any | String, borrow_asset_id_or_symbol, borrow_amount)
      asset_data = cache.query_asset(borrow_asset_id_or_symbol).not_nil!
      fund_id = if fund.is_a?(String)
                  fund
                else
                  fund["id"].as_s
                end

      opdata = {
        :fee           => default_fee,
        :borrower      => to_account_id(borrower),
        :fund_id       => fund_id,
        :borrow_amount => {:amount => (borrow_amount.to_f64 * (10 ** asset_data["precision"].as_i)).to_i64, :asset_id => asset_data["id"].as_s},
      }
      return opdata
    end

    def do_samet_fund_borrow(borrower, fund : JSON::Any | String, borrow_asset_id_or_symbol, borrow_amount)
      build { |tx| tx.add_operation :samet_fund_borrow, make_samet_fund_borrow(borrower, fund, borrow_asset_id_or_symbol, borrow_amount) }
    end

    def make_samet_fund_repay(borrower, fund : JSON::Any | String, asset_id_or_symbol, repay_amount, fee_amount)
      asset_data = cache.query_asset(asset_id_or_symbol).not_nil!
      precision = asset_data["precision"].as_i
      asset_id = asset_data["id"].as_s

      fund_id = if fund.is_a?(String)
                  fund
                else
                  fund["id"].as_s
                end

      opdata = {
        :fee          => default_fee,
        :account      => to_account_id(borrower),
        :fund_id      => fund_id,
        :repay_amount => {:amount => (repay_amount.to_f64 * (10 ** precision)).to_i64, :asset_id => asset_id},
        :fund_fee     => {:amount => (fee_amount.to_f64 * (10 ** precision)).to_i64, :asset_id => asset_id},
      }
      return opdata
    end

    def do_samet_fund_repay(borrower, fund : JSON::Any | String, asset_id_or_symbol, repay_amount, fee_amount)
      build { |tx| tx.add_operation :samet_fund_repay, make_samet_fund_repay(borrower, fund, asset_id_or_symbol, repay_amount, fee_amount) }
    end

    private def to_account_id(account : JSON::Any | String) : String
      oid = if account.is_a?(String)
              cache.query_account(account).not_nil!["id"].as_s
            else
              account["id"].as_s
            end
      return oid
    end

    private def default_fee
      return {:amount => 0, :asset_id => "1.3.0"}
    end
  end
end
