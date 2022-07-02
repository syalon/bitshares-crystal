require "./graphene_serializer"

module Graphene
  # 石墨烯支持的各种操作对象结构定义。
  module Operations
    include Graphene::Serialize
    include BitShares::Blockchain

    # 测试结构体
    graphene_struct T_Test,
      amount : UInt8,
      asset_id : String

    record Fee_parameters_type_default,
      fee : UInt64 do
      include Graphene::Serialize::Composite(self)
    end

    record Fee_parameters_type_empty do
      include Graphene::Serialize::Composite(self)
    end

    record Fee_parameters_type_with_per_kbytes,
      fee : UInt64,
      price_per_kbyte : UInt32 do
      include Graphene::Serialize::Composite(self)
    end

    abstract struct T_unsupported_type_base
      include Graphene::Serialize::Pack(self)

      def pack(io)
        raise "not supported"
      end

      def self.unpack(io) : self
        raise "not supported"
        # => not reached
        return new
      end

      def to_json(json : JSON::Builder) : Nil
        raise "not supported"
        nil.to_json(json)
      end

      # => 实现比较运算。
      def <=>(other)
        raise "not supported"
        return 0
      end
    end

    struct T_unsupported_type_virtual_op < T_unsupported_type_base
      alias Fee_parameters_type = Fee_parameters_type_empty
    end

    #
    # 资产对象
    #
    struct T_asset
      include Graphene::Serialize::Composite(self)

      getter amount : T_share_type
      getter asset_id : Tm_protocol_id_type(ObjectType::Asset)

      def initialize(@amount,
                     @asset_id)
      end
    end

    struct T_memo_data
      include Graphene::Serialize::Composite(self)

      getter from : Secp256k1Zkp::PublicKey
      getter to : Secp256k1Zkp::PublicKey
      getter nonce : UInt64
      getter message : Bytes

      def initialize(@from,
                     @to,
                     @nonce,
                     @message)
      end
    end

    struct OP_transfer
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter from : Tm_protocol_id_type(ObjectType::Account)
      getter to : Tm_protocol_id_type(ObjectType::Account)
      getter amount : T_asset
      getter memo : Tm_optional(T_memo_data)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @from,
                     @to,
                     @amount,
                     @memo,
                     @extensions)
      end
    end

    struct OP_limit_order_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter seller : Tm_protocol_id_type(ObjectType::Account)
      getter amount_to_sell : T_asset
      getter min_to_receive : T_asset
      getter expiration : T_time_point_sec
      getter fill_or_kill : Bool
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @seller,
                     @amount_to_sell,
                     @min_to_receive,
                     @expiration,
                     @fill_or_kill,
                     @extensions)
      end
    end

    struct OP_limit_order_cancel
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter fee_paying_account : Tm_protocol_id_type(ObjectType::Account)
      getter order : Tm_protocol_id_type(ObjectType::Limit_order)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @fee_paying_account,
                     @order,
                     @extensions)
      end
    end

    struct OP_call_order_update
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter target_collateral_ratio : Tm_optional(UInt16)

        def initialize
          @target_collateral_ratio = typeof(@target_collateral_ratio).new
        end
      end

      getter fee : T_asset
      getter funding_account : Tm_protocol_id_type(ObjectType::Account)
      getter delta_collateral : T_asset
      getter delta_debt : T_asset
      getter extensions : Ext

      def initialize(@fee,
                     @funding_account,
                     @delta_collateral,
                     @delta_debt,
                     @extensions)
      end
    end

    # => TODO:OP virtual Fill_order
    alias OP_fill_order = T_unsupported_type_virtual_op

    struct T_authority
      include Graphene::Serialize::Composite(self)

      getter weight_threshold : UInt32
      getter account_auths : Tm_map(Tm_protocol_id_type(ObjectType::Account), UInt16)
      getter key_auths : Tm_map(Secp256k1Zkp::PublicKey, UInt16)
      getter address_auths : Tm_map(Secp256k1Zkp::Address, UInt16)

      def initialize(@weight_threshold,
                     @account_auths,
                     @key_auths,
                     @address_auths)
      end
    end

    struct T_account_options
      include Graphene::Serialize::Composite(self)

      getter memo_key : Secp256k1Zkp::PublicKey
      getter voting_account : Tm_protocol_id_type(ObjectType::Account)
      getter num_witness : UInt16
      getter num_committee : UInt16
      getter votes : Tm_set(T_vote_id)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@memo_key,
                     @voting_account,
                     @num_witness,
                     @num_committee,
                     @votes,
                     @extensions)
      end
    end

    struct T_no_special_authority
      include Graphene::Serialize::Composite(self)
    end

    struct T_top_holders_special_authority
      include Graphene::Serialize::Composite(self)

      getter asset : Tm_protocol_id_type(ObjectType::Asset)
      getter num_top_holders : UInt8

      def initialize(@asset,
                     @num_top_holders)
      end
    end

    alias T_special_authority = Tm_static_variant(T_no_special_authority, T_top_holders_special_authority)

    struct T_buyback_account_options
      include Graphene::Serialize::Composite(self)

      getter asset_to_buy : Tm_protocol_id_type(ObjectType::Asset)
      getter asset_to_buy_issuer : Tm_protocol_id_type(ObjectType::Account)
      getter markets : Tm_set(Tm_protocol_id_type(ObjectType::Asset))

      def initialize(@asset_to_buy,
                     @asset_to_buy_issuer,
                     @markets)
      end
    end

    struct OP_account_create
      record Fee_parameters_type,
        basic_fee : UInt64,
        premium_fee : UInt64,
        price_per_kbyte : UInt32 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter null_ext : Tm_optional(T_void)
        getter owner_special_authority : Tm_optional(T_special_authority)
        getter active_special_authority : Tm_optional(T_special_authority)
        getter buyback_options : Tm_optional(T_buyback_account_options)

        def initialize
          @null_ext = typeof(@null_ext).new
          @owner_special_authority = typeof(@owner_special_authority).new
          @active_special_authority = typeof(@active_special_authority).new
          @buyback_options = typeof(@buyback_options).new
        end
      end

      getter fee : T_asset
      getter registrar : Tm_protocol_id_type(ObjectType::Account)
      getter referrer : Tm_protocol_id_type(ObjectType::Account)
      getter referrer_percent : UInt16
      getter name : String
      getter owner : T_authority
      getter active : T_authority
      getter options : T_account_options
      getter extensions : Ext

      def initialize(@fee,
                     @registrar,
                     @referrer,
                     @referrer_percent,
                     @name,
                     @owner,
                     @active,
                     @options,
                     @extensions)
      end
    end

    struct OP_account_update
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter null_ext : Tm_optional(T_void)
        getter owner_special_authority : Tm_optional(T_special_authority)
        getter active_special_authority : Tm_optional(T_special_authority)

        def initialize
          @null_ext = typeof(@null_ext).new
          @owner_special_authority = typeof(@owner_special_authority).new
          @active_special_authority = typeof(@active_special_authority).new
        end
      end

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter owner : Tm_optional(T_authority)
      getter active : Tm_optional(T_authority)
      getter new_options : Tm_optional(T_account_options)
      getter extensions : Ext

      def initialize(@fee,
                     @account,
                     @owner,
                     @active,
                     @new_options,
                     @extensions)
      end
    end

    struct OP_account_whitelist
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter authorizing_account : Tm_protocol_id_type(ObjectType::Account)
      getter account_to_list : Tm_protocol_id_type(ObjectType::Account)
      getter new_listing : UInt8

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @authorizing_account,
                     @account_to_list,
                     @new_listing,
                     @extensions)
      end
    end

    struct OP_account_upgrade
      record Fee_parameters_type,
        membership_annual_fee : UInt64,
        membership_lifetime_fee : UInt64 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account_to_upgrade : Tm_protocol_id_type(ObjectType::Account)
      getter upgrade_to_lifetime_member : Bool
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account_to_upgrade,
                     @upgrade_to_lifetime_member,
                     @extensions)
      end
    end

    struct OP_account_transfer
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account_id : Tm_protocol_id_type(ObjectType::Account)
      getter new_owner : Tm_protocol_id_type(ObjectType::Account)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account_id,
                     @new_owner,
                     @extensions)
      end
    end

    struct T_asset_options
      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter reward_percent : Tm_optional(UInt16)
        getter whitelist_market_fee_sharing : Tm_optional(Tm_set(Tm_protocol_id_type(ObjectType::Account)))
        getter taker_fee_percent : Tm_optional(UInt16) # => After BSIP81 activation, taker_fee_percent is the taker fee

        def initialize
          @reward_percent = typeof(@reward_percent).new
          @whitelist_market_fee_sharing = typeof(@whitelist_market_fee_sharing).new
          @taker_fee_percent = typeof(@taker_fee_percent).new
        end
      end

      getter max_supply : Int64
      getter market_fee_percent : UInt16
      getter max_market_fee : Int64
      getter issuer_permissions : UInt16
      getter flags : UInt16
      getter core_exchange_rate : T_price
      getter whitelist_authorities : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter blacklist_authorities : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter whitelist_markets : Tm_set(Tm_protocol_id_type(ObjectType::Asset))
      getter blacklist_markets : Tm_set(Tm_protocol_id_type(ObjectType::Asset))
      getter description : String
      getter extensions : Ext

      def initialize(@max_supply,
                     @market_fee_percent,
                     @max_market_fee,
                     @issuer_permissions,
                     @flags,
                     @core_exchange_rate,
                     @whitelist_authorities,
                     @blacklist_authorities,
                     @whitelist_markets,
                     @blacklist_markets,
                     @description,
                     @extensions)
      end
    end

    struct T_bitasset_options
      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter initial_collateral_ratio : Tm_optional(UInt16)     # => BSIP-77
        getter maintenance_collateral_ratio : Tm_optional(UInt16) # => BSIP-75
        getter maximum_short_squeeze_ratio : Tm_optional(UInt16)  # => BSIP-75
        getter margin_call_fee_ratio : Tm_optional(UInt16)        # => BSIP 74
        getter force_settle_fee_percent : Tm_optional(UInt16)     # => BSIP-87
        getter black_swan_response_method : Tm_optional(UInt8)    # => https://github.com/bitshares/bitshares-core/issues/2467

        def initialize
          @initial_collateral_ratio = typeof(@initial_collateral_ratio).new
          @maintenance_collateral_ratio = typeof(@maintenance_collateral_ratio).new
          @maximum_short_squeeze_ratio = typeof(@maximum_short_squeeze_ratio).new
          @margin_call_fee_ratio = typeof(@margin_call_fee_ratio).new
          @force_settle_fee_percent = typeof(@force_settle_fee_percent).new
          @black_swan_response_method = typeof(@black_swan_response_method).new
        end
      end

      getter feed_lifetime_sec : UInt32
      getter minimum_feeds : UInt8
      getter force_settlement_delay_sec : UInt32
      getter force_settlement_offset_percent : UInt16
      getter maximum_force_settlement_volume : UInt16
      getter short_backing_asset : Tm_protocol_id_type(ObjectType::Asset)
      getter extensions : Ext

      def initialize(@feed_lifetime_sec,
                     @minimum_feeds,
                     @force_settlement_delay_sec,
                     @force_settlement_offset_percent,
                     @maximum_force_settlement_volume,
                     @short_backing_asset,
                     @extensions)
      end
    end

    struct T_price
      include Graphene::Serialize::Composite(self)

      getter base : T_asset
      getter quote : T_asset

      def initialize(@base,
                     @quote)
      end
    end

    struct T_price_feed
      include Graphene::Serialize::Composite(self)

      getter settlement_price : T_price
      getter maintenance_collateral_ratio : UInt16
      getter maximum_short_squeeze_ratio : UInt16
      getter core_exchange_rate : T_price

      def initialize(@settlement_price,
                     @maintenance_collateral_ratio,
                     @maximum_short_squeeze_ratio,
                     @core_exchange_rate)
      end
    end

    struct OP_asset_create
      record Fee_parameters_type,
        symbol3 : UInt64,
        symbol4 : UInt64,
        long_symbol : UInt64,
        price_per_kbyte : UInt32 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter symbol : String
      getter precision : UInt8
      getter common_options : T_asset_options
      getter bitasset_opts : Tm_optional(T_bitasset_options)
      getter is_prediction_market : Bool
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @symbol,
                     @precision,
                     @common_options,
                     @bitasset_opts,
                     @is_prediction_market,
                     @extensions)
      end
    end

    struct OP_asset_update
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter new_precision : Tm_optional(UInt8)          # => After BSIP48, the precision of an asset can be updated if no supply is available
        getter skip_core_exchange_rate : Tm_optional(Bool) # => After BSIP48, if this option is set to true, the asset's core_exchange_rate won't be updated.

        def initialize
          @new_precision = typeof(@new_precision).new
          @skip_core_exchange_rate = typeof(@skip_core_exchange_rate).new
        end
      end

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter asset_to_update : Tm_protocol_id_type(ObjectType::Asset)
      getter new_issuer : Tm_optional(Tm_protocol_id_type(ObjectType::Account))
      getter new_options : T_asset_options
      getter extensions : Ext

      def initialize(@fee,
                     @issuer,
                     @asset_to_update,
                     @new_issuer,
                     @new_options,
                     @extensions)
      end
    end

    struct OP_asset_update_bitasset
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter asset_to_update : Tm_protocol_id_type(ObjectType::Asset)
      getter new_options : T_bitasset_options
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @asset_to_update,
                     @new_options,
                     @extensions)
      end
    end

    struct OP_asset_update_feed_producers
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter asset_to_update : Tm_protocol_id_type(ObjectType::Asset)
      getter new_feed_producers : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @asset_to_update,
                     @new_feed_producers,
                     @extensions)
      end
    end

    struct OP_asset_issue
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter asset_to_issue : T_asset
      getter issue_to_account : Tm_protocol_id_type(ObjectType::Account)
      getter memo : Tm_optional(T_memo_data)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @asset_to_issue,
                     @issue_to_account,
                     @memo,
                     @extensions)
      end
    end

    struct OP_asset_reserve
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter payer : Tm_protocol_id_type(ObjectType::Account)
      getter amount_to_reserve : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @payer,
                     @amount_to_reserve,
                     @extensions)
      end
    end

    struct OP_asset_fund_fee_pool
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter from_account : Tm_protocol_id_type(ObjectType::Account)
      getter asset_id : Tm_protocol_id_type(ObjectType::Asset)
      getter amount : T_share_type                          # only core asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @from_account,
                     @asset_id,
                     @amount,
                     @extensions)
      end
    end

    struct OP_asset_settle
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter amount : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @amount,
                     @extensions)
      end
    end

    struct OP_asset_global_settle
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter asset_to_settle : Tm_protocol_id_type(ObjectType::Asset)
      getter settle_price : T_price
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @asset_to_settle,
                     @settle_price,
                     @extensions)
      end
    end

    struct OP_asset_publish_feed
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter initial_collateral_ratio : Tm_optional(UInt16) # => After BSIP77, price feed producers can feed ICR too

        def initialize
          @initial_collateral_ratio = typeof(@initial_collateral_ratio).new
        end
      end

      getter fee : T_asset
      getter publisher : Tm_protocol_id_type(ObjectType::Account)
      getter asset_id : Tm_protocol_id_type(ObjectType::Asset)
      getter feed : T_price_feed
      getter extensions : Ext

      def initialize(@fee,
                     @publisher,
                     @asset_id,
                     @feed,
                     @extensions)
      end
    end

    struct OP_witness_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter witness_account : Tm_protocol_id_type(ObjectType::Account)
      getter url : String
      getter block_signing_key : Secp256k1Zkp::PublicKey

      def initialize(@fee,
                     @witness_account,
                     @url,
                     @block_signing_key)
      end
    end

    struct OP_witness_update
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter witness : Tm_protocol_id_type(ObjectType::Witness)
      getter witness_account : Tm_protocol_id_type(ObjectType::Account)
      getter new_url : Tm_optional(String)
      getter new_signing_key : Tm_optional(Secp256k1Zkp::PublicKey)

      def initialize(@fee,
                     @witness,
                     @witness_account,
                     @new_url,
                     @new_signing_key)
      end
    end

    struct T_op_wrapper
      include Graphene::Serialize::Composite(self)

      getter op : T_operation

      def initialize(@op)
      end
    end

    struct OP_proposal_create
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter fee_paying_account : Tm_protocol_id_type(ObjectType::Account)
      getter expiration_time : T_time_point_sec
      getter proposed_ops : Array(T_op_wrapper)
      getter review_period_seconds : Tm_optional(UInt32)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @fee_paying_account,
                     @expiration_time,
                     @proposed_ops,
                     @review_period_seconds,
                     @extensions)
      end
    end

    struct OP_proposal_update
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter fee_paying_account : Tm_protocol_id_type(ObjectType::Account)
      getter proposal : Tm_protocol_id_type(ObjectType::Proposal)

      getter active_approvals_to_add : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter active_approvals_to_remove : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter owner_approvals_to_add : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter owner_approvals_to_remove : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter key_approvals_to_add : Tm_set(Secp256k1Zkp::PublicKey)
      getter key_approvals_to_remove : Tm_set(Secp256k1Zkp::PublicKey)

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @fee_paying_account,
                     @proposal,
                     @active_approvals_to_add,
                     @active_approvals_to_remove,
                     @owner_approvals_to_add,
                     @owner_approvals_to_remove,
                     @key_approvals_to_add,
                     @key_approvals_to_remove,
                     @extensions)
      end
    end

    struct OP_proposal_delete
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter fee_paying_account : Tm_protocol_id_type(ObjectType::Account)
      getter using_owner_authority : Bool
      getter proposal : Tm_protocol_id_type(ObjectType::Proposal)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @fee_paying_account,
                     @using_owner_authority,
                     @proposal,
                     @extensions)
      end
    end

    struct OP_withdraw_permission_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter withdraw_from_account : Tm_protocol_id_type(ObjectType::Account)
      getter authorized_account : Tm_protocol_id_type(ObjectType::Account)
      getter withdrawal_limit : T_asset
      getter withdrawal_period_sec : UInt32
      getter periods_until_expiration : UInt32
      getter period_start_time : T_time_point_sec

      def initialize(@fee,
                     @withdraw_from_account,
                     @authorized_account,
                     @withdrawal_limit,
                     @withdrawal_period_sec,
                     @periods_until_expiration,
                     @period_start_time)
      end
    end

    struct OP_withdraw_permission_update
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter withdraw_from_account : Tm_protocol_id_type(ObjectType::Account)
      getter authorized_account : Tm_protocol_id_type(ObjectType::Account)
      getter permission_to_update : Tm_protocol_id_type(ObjectType::Withdraw_permission)
      getter withdrawal_limit : T_asset
      getter withdrawal_period_sec : UInt32
      getter period_start_time : T_time_point_sec
      getter periods_until_expiration : UInt32

      def initialize(@fee,
                     @withdraw_from_account,
                     @authorized_account,
                     @permission_to_update,
                     @withdrawal_limit,
                     @withdrawal_period_sec,
                     @period_start_time,
                     @periods_until_expiration)
      end
    end

    struct OP_withdraw_permission_claim
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter withdraw_permission : Tm_protocol_id_type(ObjectType::Withdraw_permission)
      getter withdraw_from_account : Tm_protocol_id_type(ObjectType::Account)
      getter withdraw_to_account : Tm_protocol_id_type(ObjectType::Account)
      getter amount_to_withdraw : T_asset
      getter memo : Tm_optional(T_memo_data)

      def initialize(@fee,
                     @withdraw_permission,
                     @withdraw_from_account,
                     @withdraw_to_account,
                     @amount_to_withdraw,
                     @memo)
      end
    end

    struct OP_withdraw_permission_delete
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter withdraw_from_account : Tm_protocol_id_type(ObjectType::Account)
      getter authorized_account : Tm_protocol_id_type(ObjectType::Account)
      getter withdrawal_permission : Tm_protocol_id_type(ObjectType::Withdraw_permission)

      def initialize(@fee,
                     @withdraw_from_account,
                     @authorized_account,
                     @withdrawal_permission)
      end
    end

    struct OP_committee_member_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter committee_member_account : Tm_protocol_id_type(ObjectType::Account)
      getter url : String

      def initialize(@fee,
                     @committee_member_account,
                     @url)
      end
    end

    struct OP_committee_member_update
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter committee_member : Tm_protocol_id_type(ObjectType::Committee_member)
      getter committee_member_account : Tm_protocol_id_type(ObjectType::Account)
      getter new_url : Tm_optional(String)

      def initialize(@fee,
                     @committee_member,
                     @committee_member_account,
                     @new_url)
      end
    end

    struct T_fee_schedule
      include Graphene::Serialize::Composite(self)

      getter parameters : Tm_set(T_fee_parameter) # => must be sorted by fee_parameters.which() and have no duplicates
      getter scale : UInt32

      def initialize(@parameters,
                     @scale)
      end
    end

    struct T_chain_parameters
      include Graphene::Serialize::Composite(self)

      struct Htlc_options
        include Graphene::Serialize::Composite(self)

        getter max_timeout_secs : UInt32
        getter max_preimage_size : UInt32

        def initialize(@max_timeout_secs,
                       @max_preimage_size)
        end
      end

      struct Custom_authority_options_type
        include Graphene::Serialize::Composite(self)

        getter max_custom_authority_lifetime_seconds : UInt32
        getter max_custom_authorities_per_account : UInt32
        getter max_custom_authorities_per_account_op : UInt32
        getter max_custom_authority_restrictions : UInt32

        def initialize(@max_custom_authority_lifetime_seconds,
                       @max_custom_authorities_per_account,
                       @max_custom_authorities_per_account_op,
                       @max_custom_authority_restrictions)
        end
      end

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter updatable_htlc_options : Tm_optional(Htlc_options)
        getter custom_authority_options : Tm_optional(Custom_authority_options_type)
        getter market_fee_network_percent : Tm_optional(UInt16)
        getter maker_fee_discount_percent : Tm_optional(UInt16)

        def initialize
          @updatable_htlc_options = typeof(@updatable_htlc_options).new
          @custom_authority_options = typeof(@custom_authority_options).new
          @market_fee_network_percent = typeof(@market_fee_network_percent).new
          @maker_fee_discount_percent = typeof(@maker_fee_discount_percent).new
        end
      end

      getter current_fees : T_fee_schedule

      getter block_interval : UInt8
      getter maintenance_interval : UInt32
      getter maintenance_skip_slots : UInt8
      getter committee_proposal_review_period : UInt32
      getter maximum_transaction_size : UInt32
      getter maximum_block_size : UInt32
      getter maximum_time_until_expiration : UInt32
      getter maximum_proposal_lifetime : UInt32
      getter maximum_asset_whitelist_authorities : UInt8
      getter maximum_asset_feed_publishers : UInt8
      getter maximum_witness_count : UInt16
      getter maximum_committee_count : UInt16
      getter maximum_authority_membership : UInt16
      getter reserve_percent_of_fee : UInt16
      getter network_percent_of_fee : UInt16
      getter lifetime_referrer_percent_of_fee : UInt16
      getter cashback_vesting_period_seconds : UInt32
      getter cashback_vesting_threshold : T_share_type
      getter count_non_member_votes : Bool
      getter allow_non_member_whitelists : Bool
      getter witness_pay_per_block : T_share_type
      # getter witness_pay_vesting_seconds : UInt32 # => MARK: 反射漏掉了
      getter worker_budget_per_day : T_share_type
      getter max_predicate_opcode : UInt16
      getter fee_liquidation_threshold : T_share_type
      getter accounts_per_fee_scale : UInt16
      getter account_fee_scale_bitshifts : UInt8
      getter max_authority_depth : UInt8
      getter extensions : Ext

      def initialize(@current_fees,
                     @block_interval,
                     @maintenance_interval,
                     @maintenance_skip_slots,
                     @committee_proposal_review_period,
                     @maximum_transaction_size,
                     @maximum_block_size,
                     @maximum_time_until_expiration,
                     @maximum_proposal_lifetime,
                     @maximum_asset_whitelist_authorities,
                     @maximum_asset_feed_publishers,
                     @maximum_witness_count,
                     @maximum_committee_count,
                     @maximum_authority_membership,
                     @reserve_percent_of_fee,
                     @network_percent_of_fee,
                     @lifetime_referrer_percent_of_fee,
                     @cashback_vesting_period_seconds,
                     @cashback_vesting_threshold,
                     @count_non_member_votes,
                     @allow_non_member_whitelists,
                     @witness_pay_per_block,
                     @worker_budget_per_day,
                     @max_predicate_opcode,
                     @fee_liquidation_threshold,
                     @accounts_per_fee_scale,
                     @account_fee_scale_bitshifts,
                     @max_authority_depth,
                     @extensions)
      end
    end

    struct OP_committee_member_update_global_parameters
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter new_parameters : T_chain_parameters

      def initialize(@fee,
                     @new_parameters)
      end
    end

    struct T_linear_vesting_policy_initializer
      include Graphene::Serialize::Composite(self)

      getter begin_timestamp : T_time_point_sec
      getter vesting_cliff_seconds : UInt32
      getter vesting_duration_seconds : UInt32

      def initialize(@begin_timestamp,
                     @vesting_cliff_seconds,
                     @vesting_duration_seconds)
      end
    end

    struct T_cdd_vesting_policy_initializer
      include Graphene::Serialize::Composite(self)

      getter start_claim : T_time_point_sec
      getter vesting_seconds : UInt32

      def initialize(@start_claim,
                     @vesting_seconds)
      end
    end

    struct T_instant_vesting_policy_initializer
      include Graphene::Serialize::Composite(self)
    end

    alias T_vesting_policy_initializer = Tm_static_variant(T_linear_vesting_policy_initializer, T_cdd_vesting_policy_initializer, T_instant_vesting_policy_initializer)

    struct OP_vesting_balance_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter creator : Tm_protocol_id_type(ObjectType::Account)
      getter owner : Tm_protocol_id_type(ObjectType::Account)
      getter amount : T_asset
      getter policy : T_vesting_policy_initializer

      def initialize(@fee,
                     @creator,
                     @owner,
                     @amount,
                     @policy)
      end
    end

    struct OP_vesting_balance_withdraw
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter vesting_balance : Tm_protocol_id_type(ObjectType::Vesting_balance)
      getter owner : Tm_protocol_id_type(ObjectType::Account)
      getter amount : T_asset

      def initialize(@fee,
                     @vesting_balance,
                     @owner,
                     @amount)
      end
    end

    struct T_vesting_balance_worker_initializer
      include Graphene::Serialize::Composite(self)

      getter pay_vesting_period_days : UInt16

      def initialize(@pay_vesting_period_days)
      end
    end

    struct T_burn_worker_initializer
      include Graphene::Serialize::Composite(self)
    end

    struct T_refund_worker_initializer
      include Graphene::Serialize::Composite(self)
    end

    alias T_worker_initializer = Tm_static_variant(T_refund_worker_initializer, T_vesting_balance_worker_initializer, T_burn_worker_initializer)

    struct OP_worker_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter owner : Tm_protocol_id_type(ObjectType::Account)
      getter work_begin_date : T_time_point_sec
      getter work_end_date : T_time_point_sec
      getter daily_pay : T_share_type
      getter name : String
      getter url : String
      getter initializer : T_worker_initializer

      def initialize(@fee,
                     @owner,
                     @work_begin_date,
                     @work_end_date,
                     @daily_pay,
                     @name,
                     @url,
                     @initializer)
      end
    end

    struct OP_custom
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter payer : Tm_protocol_id_type(ObjectType::Account)
      getter required_auths : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter id : UInt16
      getter data : Bytes

      def initialize(@fee,
                     @payer,
                     @required_auths,
                     @id,
                     @data)
      end
    end

    struct T_account_storage_map
      include Graphene::Serialize::Composite(self)

      getter remove : Bool
      getter catalog : String
      getter key_values : Tm_map(String, Tm_optional(String))

      def initialize(@remove,
                     @catalog,
                     @key_values)
      end
    end

    struct T_custom_plugin_operation
      include Graphene::Serialize::Composite(self)

      getter data : Tm_static_variant(T_account_storage_map)

      def initialize(@data)
      end
    end

    struct T_assert_predicate_account_name_eq_lit
      include Graphene::Serialize::Composite(self)

      getter account_id : Tm_protocol_id_type(ObjectType::Account)
      getter name : String

      def initialize(@account_id,
                     @name)
      end
    end

    struct T_assert_predicate_asset_symbol_eq_lit
      include Graphene::Serialize::Composite(self)

      getter asset_id : Tm_protocol_id_type(ObjectType::Asset)
      getter symbol : String

      def initialize(@asset_id,
                     @symbol)
      end
    end

    struct T_assert_predicate_block_id
      include Graphene::Serialize::Composite(self)

      getter id : T_hash_rmd160 # RMD160

      def initialize(@id)
      end
    end

    alias T_assert_predicate = Tm_static_variant(T_assert_predicate_account_name_eq_lit, T_assert_predicate_asset_symbol_eq_lit, T_assert_predicate_block_id)

    struct OP_assert
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter fee_paying_account : Tm_protocol_id_type(ObjectType::Account)
      getter predicates : Array(T_assert_predicate)
      getter required_auths : Tm_set(Tm_protocol_id_type(ObjectType::Account))
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @fee_paying_account,
                     @predicates,
                     @required_auths,
                     @extensions)
      end
    end

    struct OP_balance_claim
      alias Fee_parameters_type = Fee_parameters_type_empty

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter deposit_to_account : Tm_protocol_id_type(ObjectType::Account)
      getter balance_to_claim : Tm_protocol_id_type(ObjectType::Balance)
      getter balance_owner_key : Secp256k1Zkp::PublicKey
      getter total_claimed : T_asset

      def initialize(@fee,
                     @deposit_to_account,
                     @balance_to_claim,
                     @balance_owner_key,
                     @total_claimed)
      end
    end

    struct OP_override_transfer
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter from : Tm_protocol_id_type(ObjectType::Account)
      getter to : Tm_protocol_id_type(ObjectType::Account)
      getter amount : T_asset
      getter memo : Tm_optional(T_memo_data)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @from,
                     @to,
                     @amount,
                     @memo,
                     @extensions)
      end
    end

    struct T_stealth_confirmation_memo_data
      include Graphene::Serialize::Composite(self)

      getter from : Tm_optional(Secp256k1Zkp::PublicKey)
      getter amount : T_asset
      getter blinding_factor : T_hash_sha256 # blind_factor_type -> SHA256
      getter commitment : FixedBytes(33)
      getter check : UInt32

      def initialize(@from,
                     @amount,
                     @blinding_factor,
                     @commitment,
                     @check)
      end
    end

    struct T_stealth_confirmation
      include Graphene::Serialize::Composite(self)

      getter one_time_key : Secp256k1Zkp::PublicKey
      getter to : Tm_optional(Secp256k1Zkp::PublicKey)
      getter encrypted_memo : Bytes

      def initialize(@one_time_key,
                     @to,
                     @encrypted_memo)
      end
    end

    struct T_blind_input
      include Graphene::Serialize::Composite(self)

      getter commitment : FixedBytes(33)
      getter owner : T_authority

      def initialize(@commitment,
                     @owner)
      end
    end

    struct T_blind_output
      include Graphene::Serialize::Composite(self)

      getter commitment : FixedBytes(33)
      getter range_proof : Bytes # only required if there is more than one blind output
      getter owner : T_authority
      getter stealth_memo : Tm_optional(T_stealth_confirmation)

      def initialize(@commitment,
                     @range_proof,
                     @owner,
                     @stealth_memo)
      end
    end

    struct OP_transfer_to_blind
      record Fee_parameters_type,
        fee : UInt64,
        price_per_output : UInt32 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter amount : T_asset
      getter from : Tm_protocol_id_type(ObjectType::Account)
      getter blinding_factor : T_hash_sha256 # blind_factor_type -> SHA256
      getter outputs : Array(T_blind_output)

      def initialize(@fee,
                     @amount,
                     @from,
                     @blinding_factor,
                     @outputs)
      end
    end

    struct OP_blind_transfer
      record Fee_parameters_type,
        fee : UInt64,
        price_per_output : UInt32 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter inputs : Array(T_blind_input)
      getter outputs : Array(T_blind_output)

      def initialize(@fee,
                     @inputs,
                     @outputs)
      end
    end

    struct OP_transfer_from_blind
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter amount : T_asset
      getter to : Tm_protocol_id_type(ObjectType::Account)
      getter blinding_factor : T_hash_sha256 # blind_factor_type -> SHA256
      getter inputs : Array(T_blind_input)

      def initialize(@fee,
                     @amount,
                     @to,
                     @blinding_factor,
                     @inputs)
      end
    end

    # TODO:OP virtual Asset_settle_cancel
    alias OP_asset_settle_cancel = T_unsupported_type_virtual_op

    struct OP_asset_claim_fees
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter claim_from_asset_id : Tm_optional(Tm_protocol_id_type(ObjectType::Asset))

        def initialize
          @claim_from_asset_id = typeof(@claim_from_asset_id).new
        end
      end

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter amount_to_claim : T_asset # amount_to_claim.asset_id->issuer must == issuer
      getter extensions : Ext

      def initialize(@fee,
                     @issuer,
                     @amount_to_claim,
                     @extensions)
      end
    end

    # TODO:OP virtual Fba_distribute
    alias OP_fba_distribute = T_unsupported_type_virtual_op

    struct OP_bid_collateral
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter bidder : Tm_protocol_id_type(ObjectType::Account)
      getter additional_collateral : T_asset
      getter debt_covered : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @bidder,
                     @additional_collateral,
                     @debt_covered,
                     @extensions)
      end
    end

    # TODO:OP virtual Execute_bid
    alias OP_execute_bid = T_unsupported_type_virtual_op

    struct OP_asset_claim_pool
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter asset_id : Tm_protocol_id_type(ObjectType::Asset)
      getter amount_to_claim : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @asset_id,
                     @amount_to_claim,
                     @extensions)
      end
    end

    struct OP_asset_update_issuer
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter issuer : Tm_protocol_id_type(ObjectType::Account)
      getter asset_to_update : Tm_protocol_id_type(ObjectType::Asset)
      getter new_issuer : Tm_optional(Tm_protocol_id_type(ObjectType::Account))
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @issuer,
                     @asset_to_update,
                     @new_issuer,
                     @extensions)
      end
    end

    alias T_hash_rmd160 = FixedBytes(20)  # => RMD160
    alias T_hash_sha1 = FixedBytes(20)    # => SHA1 or SHA160
    alias T_hash_sha256 = FixedBytes(32)  # => SHA256
    alias T_hash_hash160 = FixedBytes(20) # => HASH160 = RMD160(SHA256(data))
    alias T_htlc_hash = Tm_static_variant(T_hash_rmd160, T_hash_sha1, T_hash_sha256, T_hash_hash160)

    struct OP_htlc_create
      record Fee_parameters_type,
        fee : UInt64,
        fee_per_day : UInt64 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      struct Ext
        include Graphene::Serialize::Extension(self)

        getter memo : Tm_optional(T_memo_data)

        def initialize
          @memo = typeof(@memo).new
        end
      end

      getter fee : T_asset
      getter from : Tm_protocol_id_type(ObjectType::Account)
      getter to : Tm_protocol_id_type(ObjectType::Account)
      getter amount : T_asset
      getter preimage_hash : T_htlc_hash
      getter preimage_size : UInt16
      getter claim_period_seconds : UInt32
      getter extensions : Ext

      def initialize(@fee,
                     @from,
                     @to,
                     @amount,
                     @preimage_hash,
                     @preimage_size,
                     @claim_period_seconds,
                     @extensions)
      end
    end

    struct OP_htlc_redeem
      record Fee_parameters_type,
        fee : UInt64,
        fee_per_kb : UInt64 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter htlc_id : Tm_protocol_id_type(ObjectType::Htlc)
      getter redeemer : Tm_protocol_id_type(ObjectType::Account)
      getter preimage : Bytes
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @htlc_id,
                     @redeemer,
                     @preimage,
                     @extensions)
      end
    end

    # TODO:OP virtual Htlc_redeemed
    alias OP_htlc_redeemed = T_unsupported_type_virtual_op

    struct OP_htlc_extend
      record Fee_parameters_type,
        fee : UInt64,
        fee_per_day : UInt64 do
        include Graphene::Serialize::Composite(self)
      end

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter htlc_id : Tm_protocol_id_type(ObjectType::Htlc)
      getter update_issuer : Tm_protocol_id_type(ObjectType::Account)
      getter seconds_to_add : UInt32
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @htlc_id,
                     @update_issuer,
                     @seconds_to_add,
                     @extensions)
      end
    end

    # TODO:OP virtual Htlc_refund
    alias OP_htlc_refund = T_unsupported_type_virtual_op

    # TODO:OP 3
    # Custom_authority_create                   = 54
    # Custom_authority_update                   = 55
    # Custom_authority_delete                   = 56

    struct T_unsupported_type_custom_authority < T_unsupported_type_base
      record Fee_parameters_type,
        basic_fee : UInt64,
        price_per_byte : UInt64 do
        include Graphene::Serialize::Composite(self)
      end
    end

    alias OP_custom_authority_create = T_unsupported_type_custom_authority
    alias OP_custom_authority_update = T_unsupported_type_custom_authority

    struct OP_custom_authority_delete < T_unsupported_type_base
      alias Fee_parameters_type = Fee_parameters_type_default
    end

    struct OP_ticket_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter target_type : T_varint32 # see struct unsigned_int
      getter amount : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @target_type,
                     @amount,
                     @extensions)
      end
    end

    struct OP_ticket_update
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter ticket : Tm_protocol_id_type(ObjectType::Ticket)
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter target_type : T_varint32 # see struct unsigned_int
      getter amount_for_new_target : Tm_optional(T_asset)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @ticket,
                     @account,
                     @target_type,
                     @amount_for_new_target,
                     @extensions)
      end
    end

    struct OP_liquidity_pool_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter asset_a : Tm_protocol_id_type(ObjectType::Asset)
      getter asset_b : Tm_protocol_id_type(ObjectType::Asset)
      getter share_asset : Tm_protocol_id_type(ObjectType::Asset)
      getter taker_fee_percent : UInt16
      getter withdrawal_fee_percent : UInt16
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @asset_a,
                     @asset_b,
                     @share_asset,
                     @taker_fee_percent,
                     @withdrawal_fee_percent,
                     @extensions)
      end
    end

    struct OP_liquidity_pool_delete
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter pool : Tm_protocol_id_type(ObjectType::Liquidity_pool)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @pool,
                     @extensions)
      end
    end

    struct OP_liquidity_pool_deposit
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter pool : Tm_protocol_id_type(ObjectType::Liquidity_pool)
      getter amount_a : T_asset
      getter amount_b : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @pool,
                     @amount_a,
                     @amount_b,
                     @extensions)
      end
    end

    struct OP_liquidity_pool_withdraw
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter pool : Tm_protocol_id_type(ObjectType::Liquidity_pool)
      getter share_amount : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @pool,
                     @share_amount,
                     @extensions)
      end
    end

    struct OP_liquidity_pool_exchange
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter pool : Tm_protocol_id_type(ObjectType::Liquidity_pool)
      getter amount_to_sell : T_asset
      getter min_to_receive : T_asset
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @pool,
                     @amount_to_sell,
                     @min_to_receive,
                     @extensions)
      end
    end

    struct OP_samet_fund_create
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter owner_account : Tm_protocol_id_type(ObjectType::Account)

      getter asset_type : Tm_protocol_id_type(ObjectType::Asset)
      getter balance : Int64
      getter fee_rate : UInt32

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @owner_account,
                     @asset_type,
                     @balance,
                     @fee_rate,
                     @extensions)
      end
    end

    struct OP_samet_fund_delete
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter owner_account : Tm_protocol_id_type(ObjectType::Account)
      getter fund_id : Tm_protocol_id_type(ObjectType::Samet_fund)

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @owner_account,
                     @fund_id,
                     @extensions)
      end
    end

    struct OP_samet_fund_update
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter owner_account : Tm_protocol_id_type(ObjectType::Account)
      getter fund_id : Tm_protocol_id_type(ObjectType::Samet_fund)

      getter delta_amount : Tm_optional(T_asset)
      getter new_fee_rate : Tm_optional(UInt32)

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @owner_account,
                     @fund_id,
                     @delta_amount,
                     @new_fee_rate,
                     @extensions)
      end
    end

    struct OP_samet_fund_borrow
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter borrower : Tm_protocol_id_type(ObjectType::Account)
      getter fund_id : Tm_protocol_id_type(ObjectType::Samet_fund)

      getter borrow_amount : T_asset

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @borrower,
                     @fund_id,
                     @borrow_amount,
                     @extensions)
      end
    end

    struct OP_samet_fund_repay
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter fund_id : Tm_protocol_id_type(ObjectType::Samet_fund)

      getter repay_amount : T_asset
      getter fund_fee : T_asset

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @fund_id,
                     @repay_amount,
                     @fund_fee,
                     @extensions)
      end
    end

    struct OP_credit_offer_create
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter owner_account : Tm_protocol_id_type(ObjectType::Account)

      getter asset_type : Tm_protocol_id_type(ObjectType::Asset)
      getter balance : Int64
      getter fee_rate : UInt32

      getter max_duration_seconds : UInt32
      getter min_deal_amount : Int64
      getter enabled : Bool
      getter auto_disable_time : T_time_point_sec

      getter acceptable_collateral : Tm_map(Tm_protocol_id_type(ObjectType::Asset), T_price)
      getter acceptable_borrowers : Tm_map(Tm_protocol_id_type(ObjectType::Account), Int64)

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @owner_account,
                     @asset_type,
                     @balance,
                     @fee_rate,
                     @max_duration_seconds,
                     @min_deal_amount,
                     @enabled,
                     @auto_disable_time,
                     @acceptable_collateral,
                     @acceptable_borrowers,
                     @extensions)
      end
    end

    struct OP_credit_offer_delete
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter owner_account : Tm_protocol_id_type(ObjectType::Account)
      getter offer_id : Tm_protocol_id_type(ObjectType::Credit_offer)

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @owner_account,
                     @offer_id,
                     @extensions)
      end
    end

    struct OP_credit_offer_update
      alias Fee_parameters_type = Fee_parameters_type_with_per_kbytes

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter owner_account : Tm_protocol_id_type(ObjectType::Account)
      getter offer_id : Tm_protocol_id_type(ObjectType::Credit_offer)

      getter delta_amount : Tm_optional(T_asset)
      getter fee_rate : Tm_optional(UInt32)
      getter max_duration_seconds : Tm_optional(UInt32)
      getter min_deal_amount : Tm_optional(Int64)
      getter enabled : Tm_optional(Bool)
      getter auto_disable_time : Tm_optional(T_time_point_sec)
      getter acceptable_collateral : Tm_optional(Tm_map(Tm_protocol_id_type(ObjectType::Asset), T_price))
      getter acceptable_borrowers : Tm_optional(Tm_map(Tm_protocol_id_type(ObjectType::Account), Int64))

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @owner_account,
                     @offer_id,
                     @delta_amount,
                     @fee_rate,
                     @max_duration_seconds,
                     @min_deal_amount,
                     @enabled,
                     @auto_disable_time,
                     @acceptable_collateral,
                     @acceptable_borrowers,
                     @extensions)
      end
    end

    struct OP_credit_offer_accept
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter borrower : Tm_protocol_id_type(ObjectType::Account)
      getter offer_id : Tm_protocol_id_type(ObjectType::Credit_offer)

      getter borrow_amount : T_asset
      getter collateral : T_asset
      getter max_fee_rate : UInt32
      getter min_duration_seconds : UInt32

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @borrower,
                     @offer_id,
                     @borrow_amount,
                     @collateral,
                     @max_fee_rate,
                     @min_duration_seconds,
                     @extensions)
      end
    end

    struct OP_credit_deal_repay
      alias Fee_parameters_type = Fee_parameters_type_default

      include Graphene::Serialize::Composite(self)

      getter fee : T_asset
      getter account : Tm_protocol_id_type(ObjectType::Account)
      getter deal_id : Tm_protocol_id_type(ObjectType::Credit_deal)

      getter repay_amount : T_asset
      getter credit_fee : T_asset

      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@fee,
                     @account,
                     @deal_id,
                     @repay_amount,
                     @credit_fee,
                     @extensions)
      end
    end

    # TODO:OP virtual Credit_deal_expired
    alias OP_credit_deal_expired = T_unsupported_type_virtual_op

    abstract struct T_transaction_virtual
      getter ref_block_num : UInt16
      getter ref_block_prefix : UInt32
      getter expiration : T_time_point_sec
      getter operations : Array(T_operation)
      getter extensions : Tm_empty_set(T_future_extensions) # => 预留：空集合，未来扩展。

      def initialize(@ref_block_num,
                     @ref_block_prefix,
                     @expiration,
                     @operations)
        @extensions = typeof(@extensions).new
      end
    end

    struct T_transaction < T_transaction_virtual
      include Graphene::Serialize::Composite(self)
    end

    abstract struct T_signed_transaction_virtual < T_transaction_virtual
      getter signatures : Array(FixedBytes(65))

      def initialize(@ref_block_num,
                     @ref_block_prefix,
                     @expiration,
                     @operations,
                     @signatures)
        @extensions = typeof(@extensions).new
      end

      def initialize(other : T_transaction_virtual)
        @ref_block_num = other.ref_block_num
        @ref_block_prefix = other.ref_block_prefix
        @expiration = other.expiration
        @operations = other.operations
        @extensions = other.extensions

        @signatures = typeof(@signatures).new
      end
    end

    struct T_signed_transaction < T_signed_transaction_virtual
      include Graphene::Serialize::Composite(self)
    end

    # 定义 T_operation 类型
    {% begin %}
      alias T_operation = Graphene::Serialize::Tm_static_variant(
          {% for member in ::BitShares::Blockchain::Operations.constants %}
            {{ "OP_#{member.downcase}".id }},
          {% end %}
        )

      alias T_fee_parameter = Graphene::Serialize::Tm_static_variant(
          {% for member in ::BitShares::Blockchain::Operations.constants %}
            {{ "OP_#{member.downcase}".id }}::Fee_parameters_type,
          {% end %}
        )
    {% end %}
  end
end
