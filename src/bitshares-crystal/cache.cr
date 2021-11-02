# TODO: 未完成

module BitShares
  class Cache
    getter client : Client

    def initialize(client)
      @client = client
      @oid_cache = {} of String => JSON::Any     # => oid -> obj
      @symbol_cache = {} of String => JSON::Any  # => asset_symbol -> asset obj
      @name_cache = {} of String => JSON::Any    # => account_name -> account obj
      @witness_cache = {} of String => JSON::Any # => witness_account_id -> witness obj
    end

    def clear
      @oid_cache.clear
      @symbol_cache.clear
      @name_cache.clear
      @witness_cache.clear
    end

    def get_by_id(oid)
      @oid_cache[oid]
    end

    def get_by_name(account_name)
      @name_cache[account_name]
    end

    def get_by_symbol(asset_symbol)
      @symbol_cache[asset_symbol]
    end

    # TODO:

    # #--------------------------------------------------------------------------
    # # ● API：获取单个任意对象信息
    # #--------------------------------------------------------------------------
    # def get_object(oid)
    #   return @client.async_call_db("get_objects", [[oid]]).then{|data_array| data_array[0]}
    # end

    # #--------------------------------------------------------------------------
    # # ● API：获取指定资产信息
    # #--------------------------------------------------------------------------
    # def get_asset(asset_id)
    #   return get_object(asset_id)
    # end

    # #--------------------------------------------------------------------------
    # # ● API：获取指定账号信息
    # #--------------------------------------------------------------------------
    # def get_full_accounts(account_name_or_id)
    #   return @client.async_call_db("get_full_accounts", [[account_name_or_id], false]).then{|data|
    #     if !data || data.empty?
    #       nil
    #     else
    #       data[0][1]
    #     end
    #   }
    # end
    # => if (std::isdigit(name_or_id[0]))

    def query_objects(object_id_or_id_array : String | Array(String))
      result = {} of String => JSON::Any

      object_id_array = if object_id_or_id_array.is_a?(String)
                          [object_id_or_id_array]
                        else
                          object_id_or_id_array.as(Array)
                        end
      # => 空
      return result if object_id_array.empty?

      # => 检索缓存
      query_arr = [] of String
      object_id_array.each do |oid|
        obj = @oid_cache[oid]?
        if obj
          result[oid] = obj
        else
          query_arr << oid # 未命中缓存，添加到查询列表。
        end
      end

      # => 全部命中缓存
      return result if query_arr.empty?

      # => 查询
      @client.query_objects(query_arr).each { |oid, obj| result[oid] = append_to_cache(obj) }

      return result
    end

    def query_one_object(oid)
      obj = @oid_cache[oid]?
      return obj if obj
      return append_to_cache(@client.query_one_object(oid))
    end

    def query_account(account_name_or_id)
      account = @name_cache[account_name_or_id]? || @oid_cache[account_name_or_id]?
      return account if account
      return append_to_cache(@client.query_account(account_name_or_id))
    end

    def query_asset(asset_symbol_or_id)
      asset = @symbol_cache[asset_symbol_or_id]? || @oid_cache[asset_symbol_or_id]?
      return asset if asset
      return append_to_cache(@client.query_asset(asset_symbol_or_id))
    end

    def query_witness_by_id(witness_account_id)
      witness = @witness_cache[witness_account_id]?
      return witness if witness
      return append_to_cache(@client.query_witness_by_id(witness_account_id))
    end

    def query_witness(witness_account_name_or_id)
      account = query_account(witness_account_name_or_id)
      return query_witness_by_id(account.not_nil!["id"].as_s)
    end

    private def append_to_cache(obj : JSON::Any?)
      return obj if obj.nil?

      case obj.raw
      when Array
        obj.as_a.each { |item| append_to_cache(item) }
      when Hash
        oid = obj["id"]?.try(&.as_s)
        if oid && oid =~ /^\d+\.(\d+)\.\d+$/
          object_type = $1.to_i
          @oid_cache[oid] = obj
          case object_type
          when Blockchain::ObjectType::Account.value
            @name_cache[obj["name"].as_s] = obj
          when Blockchain::ObjectType::Asset.value
            @symbol_cache[obj["symbol"].as_s] = obj
          when Blockchain::ObjectType::Witness.value
            @witness_cache[obj["witness_account"].as_s] = obj
          else
            # => TODO:
            puts "unknown object type: #{object_type}"
          end
        end
      end
      return obj
    end
  end
end
