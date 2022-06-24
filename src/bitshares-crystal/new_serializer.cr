require "json" # TODO:remove?
require "crystal-secp256k1-zkp"
require "./define"

module Graphene
  module Serialize
    # :nodoc:
    module Varint
      alias VarintIntType = UInt32 | UInt16 | UInt8 | Int32 | Int16 | Int8

      def self.encode(value : VarintIntType) : Array(UInt8)
        result = [] of UInt8
        encode_core(value.to_u64) { |byte| result << byte }
        return result
      end

      def self.encode(value : VarintIntType, &block : UInt8 -> _)
        encode_core(value.to_u64, &block)
      end

      def self.encode(value : VarintIntType, io : IO::Memory)
        encode_core(value.to_u64) { |byte| io.write_byte(byte) }
      end

      private def self.encode_core(int_val : UInt64, &block : UInt8 -> _)
        loop do
          byte = int_val & 0x7F
          int_val >>= 7
          if int_val == 0
            block.call(0x00_u8 | byte)
            break
          else
            block.call(0x80_u8 | byte)
          end
        end
      end

      def self.decode(bytes : Array(UInt8))
        decode(Slice.new(bytes.to_unsafe, bytes.size))
      end

      def self.decode(io : IO::Memory) : UInt64
        int_val = 0_u64
        shift = 0

        while byte = io.read_byte
          int_val |= (byte & 0x7F).to_u64 << shift
          shift += 7
          break if byte & 0x80 == 0
        end

        return int_val
      end

      def self.decode(bytes : Bytes)
        int_val = 0_u64
        shift = 0
        bytes.each do |byte|
          raise "too many bytes when decoding varint" if shift >= 64
          int_val |= (byte & 0x7F).to_u64 << shift
          shift += 7
          return int_val if byte & 0x80 == 0
        end

        return int_val
      end
    end

    # :nodoc:
    class BinaryIO < IO::Memory
      # :nodoc:
      def write_varint32(value : Varint::VarintIntType)
        Varint.encode(value, self)
      end

      def write_object_id(value : String, required_object_type : Blockchain::ObjectType)
        # => convert 1.2.n into just n
        if /^[\d]+\.([\d]+)\.([\d]+)$/ =~ value
          found_object_type = $1.to_i8
          raise "Invalid object id, object type is: #{Blockchain::ObjectType.new(found_object_type)}, required: #{required_object_type}." if found_object_type != required_object_type.value
          write_varint32($2.to_i)
        else
          raise "Invalid object id: #{value}"
        end
      end

      def read_varint32
        return Varint.decode(self)
      end

      def read_n_bytes(size : UInt32)
        return Bytes.new(size).tap { |slice| read(slice) }
      end

      def read_string(size : UInt32)
        return "" if size == 0
        return String.new(read_n_bytes(size))
      end

      # def w_object_id(io, args, value, object_type_symbol)
      # end
    end

    # :nodoc:
    struct Arguments
      getter graphene_address_prefix : String

      def initialize(@graphene_address_prefix : String)
      end
    end

    # :nodoc:
    module Pack(T)
      def pack(graphene_address_prefix : String = "")
        BinaryIO.new.tap { |io| pack(io, Arguments.new(graphene_address_prefix)) }.to_slice
      end

      def self.unpack(data : Bytes, graphene_address_prefix : String = "")
        return T.unpack(BinaryIO.new(data), Arguments.new(graphene_address_prefix))
      end
    end

    # :nodoc:
    module Composite(T)
      include Pack(T)

      def pack(io, args : Arguments)
        {% for ivar in @type.instance_vars %}
          @{{ ivar.id }}.pack(io, args)
        {% end %}
      end

      def __unpack_all_instance_vars(io, args : Arguments)
        {% for ivar in @type.instance_vars %}
          @{{ ivar.id }} = {{ ivar.type.id }}.unpack(io, args)
        {% end %}
      end

      macro included

        def self.unpack(io, args : Graphene::Serialize::Arguments) : self
          target = uninitialized T
          target.__unpack_all_instance_vars(io, args)
          return target
        end

      end
    end

    # :nodoc:
    module Extension(T)
      include Pack(T)

      def pack(io, args : Arguments)
        # => 统计出现的扩展字段数量
        field_count = 0

        {% for ivar in @type.instance_vars %}
          if @{{ ivar.id }}.as(Tm_optional).is_valid?
            field_count += 1
          end
        {% end %}

        # => 写入扩展字段数量
        io.write_varint32(field_count)

        # => 写入扩展字段的值
        if field_count > 0
          {% for ivar, idx in @type.instance_vars %}
            # => Tm_optional 类型有值才写入，无值不写入。不用写 flags 标记。
            optional_value = @{{ ivar.id }}.as(Tm_optional)
            if optional_value.is_valid?
              io.write_varint32({{ idx }})
              optional_value.value.not_nil!.pack(io, args)
            end
          {% end %}
        end
      end

      def __unpack_all_instance_vars(io, args : Arguments)
        len = io.read_varint32
        return if len <= 0

        {% begin %}
          {% all_ivars = @type.instance_vars %}
          raise "Too many fields" if len > {{ all_ivars.size }}

          # => 循环读取有值的字段
          len.times do 
            idx = io.read_varint32
            raise "Index out of range" if idx >= {{ all_ivars.size }}

            case idx
            {% for i in 0...all_ivars.size %}
              when {{i}}
                @{{ all_ivars[i].id }}.value = typeof(@{{ all_ivars[i].id }}.value.not_nil!).unpack(io, args)
            {% end %}
            end
            
          end
        {% end %}
      end

      macro included

        def self.unpack(io, args : Graphene::Serialize::Arguments) : self
          target = T.new
          target.__unpack_all_instance_vars(io, args)
          return target
        end

      end
    end # => Extension

    struct Tm_protocol_id_type(ReqObjectType)
      getter instance : UInt64

      # REMARK: 这里存在一个语言BUG
      # => 如果 Tm_protocol_id_type(XXX) 在其他结构体进行了声明，则泛型的类型为 Int8，如果未声明类型为 Enum。
      private def __generics_type_helper : BitShares::Blockchain::ObjectType
        if ReqObjectType.is_a?(Enum)
          return ReqObjectType.as(BitShares::Blockchain::ObjectType)
        else
          return BitShares::Blockchain::ObjectType.new(ReqObjectType)
        end
      end

      def to_s : String
        "1.#{__generics_type_helper.value}.#{@instance}"
      end

      def initialize(@instance = 0_u64)
      end

      def initialize(oid : String)
        # => convert 1.2.n into just n
        if /^[\d]+\.([\d]+)\.([\d]+)$/ =~ oid
          found_object_type = $1.to_i8
          raise "Invalid object id, object type is: #{BitShares::Blockchain::ObjectType.new(found_object_type)}, required: #{__generics_type_helper}." if found_object_type != __generics_type_helper.value
          @instance = $2.to_u64
        else
          raise "Invalid object id: #{oid}"
        end
      end

      def pack(io, args : Graphene::Serialize::Arguments)
        io.write_varint32(@instance.to_u32)
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        return new(io.read_varint32)
      end
    end

    # :nodoc:
    struct Tm_optional(T)
      property value : T?

      # 是否有效判断 REMARK: 不直接用 value 判断，那样对于 false 的值会判断错误。e.g.: Tm_optional(bool) 值为 false 时候 if value 会误认为字段不存在。
      def is_valid?
        return @value != nil
      end

      def initialize(@value : T? = nil)
      end

      def pack(io, args : Graphene::Serialize::Arguments)
        if v = @value
          io.write_byte(1_u8)
          v.pack(io, args)
        else
          io.write_byte(0_u8)
        end
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        value = if io.read_byte.not_nil! == 0
                  nil
                else
                  T.unpack(io, args)
                end
        return new(value)
      end
    end # => end Tm_optional

    # :nodoc:
    struct Tm_static_variant(*T)
      getter index : Int32 = 0
      property value : Union(*T)

      def initialize(@value)
        {% begin %}
          case @value
          {% for i in 0...T.size %}
            when T[{{i}}]
              @index = {{i}}
          {% end %}
          end
        {% end %}
      end

      private def self.index_to_optype(index)
        {% begin %}
          case index
          {% for i in 0...T.size %}
            when {{i}}
              return T[{{i}}]
          {% end %}
          end
        {% end %}
        return nil
      end

      def pack(io, args : Graphene::Serialize::Arguments)
        # => 1、write index
        io.write_varint32(@index)

        # => 2、write opdata
        {% begin %}
          case @value
          {% for i in 0...T.size %}
            when T[{{i}}]
              T[{{i}}].cast(@value).pack(io, args)
          {% end %}
          else
            raise "unknown type"
          end
        {% end %}
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        index = io.read_varint32
        optype = index_to_optype(index)
        raise "invalid type id: #{index}" if optype.nil?

        return new(optype.unpack(io, args))
      end

      # def self.to_object(args : Arguments, opdata : Raw?) : Raw?
      #   opdata = opdata.not_nil!.as_a
      #   assert(opdata.size == 2)
      #   type_id = opdata[0].as_i.to_i32

      #   optype = type_id_to_optype(type_id)
      #   raise "invalid type id: #{type_id}" if optype.nil?

      #   return Raw.new([Raw.new(type_id), optype.to_object(args, opdata.last).not_nil!])
      # end

      # 该类型不需要排序
      def nosort
        true # => TODO:ing sort 待处理
      end
    end # => end Tm_static_variant

    struct Tm_map(KeyT, ValueT)
      getter value = Hash(KeyT, ValueT).new

      def initialize
      end

      def pack(io, args : Graphene::Serialize::Arguments)
        io.write_varint32(@value.size)
        # => TODO:sort
        @value.to_a.each do |tuple|
          tuple[0].pack(io, args)
          tuple[1].pack(io, args)
        end
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        result = new

        len = io.read_varint32
        len.times do
          result.value[KeyT.unpack(io, args)] = ValueT.unpack(io, args)
        end

        return result
      end
    end
  end

  module Type
    alias T_share_type = Int64

    # => TODO:u32 or u64
    struct T_varint32
      include Graphene::Serialize::Pack(self)

      getter value : UInt32

      def initialize(@value)
      end

      def pack(io, args : Graphene::Serialize::Arguments)
        io.write_bytes(@value)
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        return new(io.read_varint32.to_u32)
      end
    end

    struct T_void
      include Graphene::Serialize::Pack(self)

      def pack(io, args : Graphene::Serialize::Arguments)
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        return new
      end
    end

    alias T_future_extensions = T_void

    struct T_vote_id
      include Graphene::Serialize::Pack(self)

      @instance : UInt32

      def to_s : String
        id = (@instance & 0xffffff00) >> 8
        type = @instance & 0xff
        return "#{type}:#{id}"
      end

      def initialize(@instance : UInt32)
      end

      def initialize(value : String)
        if /^[0-9]+:[0-9]+$/ =~ value
          type, id = value.split(":").map &.to_i
          @instance = ((id << 8) | type).to_u32
        else
          raise "Invalid vote id: #{value}"
        end
      end

      def pack(io, args : Graphene::Serialize::Arguments)
        io.write_bytes(@instance)
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        return new(io.read_bytes(UInt32))
      end
    end

    struct T_time_point_sec
      include Graphene::Serialize::Pack(self)

      getter value : UInt32

      def to_s : String
        # => 格式：2018-06-04T13:03:57
        return Time.unix(@value.to_i64).to_utc.to_s("%Y-%m-%dT%H:%M:%S")
      end

      def initialize(@value : UInt32)
      end

      def initialize(value : String)
        @value = BitShares::Utility.parse_time_string_i64(value).to_u32
      end

      def pack(io, args : Graphene::Serialize::Arguments)
        @value.pack(io, args)
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        return new(UInt32.unpack(io, args))
      end
    end
  end
end

struct Bool
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    io.write_byte(self ? 1_u8 : 0_u8)
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    io.read_byte.not_nil! != 0
  end
end

struct UInt8
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    io.write_byte(self)
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    io.read_byte.not_nil!
  end
end

{% begin %}

  {% for int in %w(UInt16 UInt32 UInt64 Int64) %}
    struct {{int.id}}

      include Graphene::Serialize::Pack(self)

      def pack(io, args : Graphene::Serialize::Arguments)
        io.write_bytes(self)
      end

      def self.unpack(io, args : Graphene::Serialize::Arguments) : self
        io.read_bytes({{int.id}})
      end
    end
  {% end %}

{% end %}

class String
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    io.write_varint32(self.bytesize)
    io.write(self.to_slice)
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    io.read_string(io.read_varint32)
  end
end

class Array(T)
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    io.write_varint32(self.size)
    each(&.pack(io, args))
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    return new(io.read_varint32) { T.unpack(io, args) }
  end
end

struct Set(T)
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    # => TODO:sort
    io.write_varint32(self.size)
    each(&.pack(io, args))
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    len = io.read_varint32

    result = new(len)

    len.times { result.add(T.unpack(io, args)) }

    return result
  end
end

# => aka Bytes
struct Slice(T)
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    {% if T == UInt8 %}
      io.write_varint32(self.size)
      io.write(self)
    {% else %}
      raise "unsupported type."
    {% end %}
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    {% if T == UInt8 %}
      slice = Bytes.new(io.read_varint32)
      io.read(slice)
      return slice
    {% else %}
      raise "unsupported type."
    {% end %}
  end
end

struct FixedBytes(Size)
  getter value : StaticArray(UInt8, Size)

  def initialize(bytes : Bytes)
    raise "size error." if bytes.size != Size
    @value = StaticArray(UInt8, Size).new { |i| bytes[i] }
  end

  def pack(io, args : Graphene::Serialize::Arguments)
    io.write(@value.to_slice)
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    target = uninitialized self

    io.read(target.value.to_slice)

    return target
  end
end

class Secp256k1Zkp::PublicKey
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    io.write(self.bytes)
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    return new(io.read_n_bytes(33))
  end
end

class Secp256k1Zkp::Address
  include Graphene::Serialize::Pack(self)

  def pack(io, args : Graphene::Serialize::Arguments)
    raise "not supported"
  end

  def self.unpack(io, args : Graphene::Serialize::Arguments) : self
    raise "not supported"
  end
end

module Graphene
  # 石墨烯支持的各种操作对象结构定义。
  module Operations
    include Serialize
    include Type
    include BitShares::Blockchain

    struct T_Test
      include Composite(self)

      getter value : T_share_type
      getter amount : Graphene::Serialize::Tm_protocol_id_type(ObjectType::Asset)

      def initialize(@value, @amount)
      end
    end

    class T_operation # < T_composite
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw?)
        opdata = opdata.not_nil!.as_a
        assert(opdata.size == 2)

        opcode = opdata[0].as_i.to_i8
        opdata = opdata[1]

        optype = BitShares::Operations::Opcode2optype[opcode]

        # 1、write opcode    2、write opdata
        io.write_varint32(opcode)
        optype.to_byte_buffer(io, args, opdata)
      end

      def self.from_byte_buffer(io, args : Arguments)
        opcode = io.read_varint32
        optype = BitShares::Operations::Opcode2optype[opcode]

        result = Raw::ArrayType.new
        result << Raw.new(opcode)
        result << Raw.new(optype.from_byte_buffer(io, args).not_nil!)
        return result
      end

      def self.to_object(args : Arguments, opdata : Raw?) : Raw?
        opdata = opdata.not_nil!.as_a
        assert(opdata.size == 2)

        opcode = opdata[0]
        optype = BitShares::Operations::Opcode2optype[opcode.as_i.to_i8]

        return Raw.new([opcode, optype.to_object(args, opdata[1])])
      end
    end

    #
    # 资产对象
    #
    struct T_asset
      include Composite(self)

      getter amount : T_share_type
      getter asset_id : Tm_protocol_id_type(ObjectType::Asset)

      def initialize
        @amount = 0
        @asset_id = typeof(@asset_id).new
      end

      def initialize(@amount, @asset_id)
      end

      def initialize(amount, asset_id_instance : String)
        initialize(amount, typeof(@asset_id).new(asset_id_instance))
      end

      def initialize(amount, asset_id : UInt64)
        initialize(amount, typeof(@asset_id).new(asset_id))
      end
    end

    struct T_memo_data
      include Composite(self)

      getter from : Secp256k1Zkp::PublicKey
      getter to : Secp256k1Zkp::PublicKey
      getter nonce : UInt64
      getter message : Bytes

      def initialize(@from, @to, @nonce, @message)
      end
    end

    struct OP_transfer
      include Composite(self)

      property fee = T_asset.new
      property from = Tm_protocol_id_type(ObjectType::Account).new
      property to = Tm_protocol_id_type(ObjectType::Account).new
      property amount = T_asset.new
      property memo = Tm_optional(T_memo_data).new
      # property extensions = Set(T_future_extensions).new # TODO:memory? 默认nil？大部分都睡空，不分配内存？
    end

    # class OP_limit_order_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :seller, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount_to_sell, T_asset
    #   add_field :min_to_receive, T_asset
    #   add_field :expiration, T_time_point_sec
    #   add_field :fill_or_kill, T_bool
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_limit_order_cancel # < T_composite
    #   add_field :fee, T_asset
    #   add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :order, Tm_protocol_id_type(ObjectType::Limit_order)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_call_order_update # < T_composite
    #   class Ext                # < Tm_extension
    #     add_field :target_collateral_ratio, T_uint16
    #   end

    #   add_field :fee, T_asset
    #   add_field :funding_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :delta_collateral, T_asset
    #   add_field :delta_debt, T_asset
    #   add_field :extensions, Ext
    # end

    # # TODO:OP virtual Fill_order

    # class T_authority # < T_composite
    #   add_field :weight_threshold, T_uint32
    #   add_field :account_auths, Tm_map(Tm_protocol_id_type(ObjectType::Account), T_uint16)
    #   add_field :key_auths, Tm_map(Secp256k1Zkp::PublicKey, T_uint16)
    #   add_field :address_auths, Tm_map(T_address, T_uint16)
    # end

    # class T_account_options # < T_composite
    #   add_field :memo_key, Secp256k1Zkp::PublicKey
    #   add_field :voting_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :num_witness, T_uint16
    #   add_field :num_committee, T_uint16
    #   add_field :votes, Tm_set(T_vote_id)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class T_no_special_authority # < T_composite
    # end

    # class T_top_holders_special_authority # < T_composite
    #   add_field :asset, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :num_top_holders, T_uint8
    # end

    # alias T_special_authority = Tm_static_variant(T_no_special_authority, T_top_holders_special_authority)

    # class T_buyback_account_options # < T_composite
    #   add_field :asset_to_buy, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :asset_to_buy_issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :markets, Tm_set(Tm_protocol_id_type(ObjectType::Asset))
    # end

    # class OP_account_create # < T_composite
    #   class Ext             # < Tm_extension
    #     add_field :null_ext, T_void
    #     add_field :owner_special_authority, T_special_authority
    #     add_field :active_special_authority, T_special_authority
    #     add_field :buyback_options, T_buyback_account_options
    #   end

    #   add_field :fee, T_asset
    #   add_field :registrar, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :referrer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :referrer_percent, T_uint16
    #   add_field :name, T_string
    #   add_field :owner, T_authority
    #   add_field :active, T_authority
    #   add_field :options, T_account_options
    #   add_field :extensions, Ext
    # end

    # class OP_account_update # < T_composite
    #   class Ext             # < Tm_extension
    #     add_field :null_ext, T_void
    #     add_field :owner_special_authority, T_special_authority
    #     add_field :active_special_authority, T_special_authority
    #   end

    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :owner, Tm_optional(T_authority)
    #   add_field :active, Tm_optional(T_authority)
    #   add_field :new_options, Tm_optional(T_account_options)
    #   add_field :extensions, Ext
    # end

    # class OP_account_whitelist # < T_composite
    #   add_field :fee, T_asset
    #   add_field :authorizing_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :account_to_list, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :new_listing, T_uint8

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_account_upgrade # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account_to_upgrade, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :upgrade_to_lifetime_member, T_bool
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_account_transfer # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account_id, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :new_owner, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class T_asset_options # < T_composite
    #   class Ext           # < Tm_extension
    #     add_field :reward_percent, T_uint16
    #     add_field :whitelist_market_fee_sharing, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #     add_field :taker_fee_percent, T_uint16 # => After BSIP81 activation, taker_fee_percent is the taker fee
    #   end

    #   add_field :max_supply, T_int64
    #   add_field :market_fee_percent, T_uint16
    #   add_field :max_market_fee, T_int64
    #   add_field :issuer_permissions, T_uint16
    #   add_field :flags, T_uint16
    #   add_field :core_exchange_rate, T_price
    #   add_field :whitelist_authorities, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :blacklist_authorities, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :whitelist_markets, Tm_set(Tm_protocol_id_type(ObjectType::Asset))
    #   add_field :blacklist_markets, Tm_set(Tm_protocol_id_type(ObjectType::Asset))
    #   add_field :description, T_string
    #   add_field :extensions, Ext
    # end

    # class T_bitasset_options                              # < T_composite
    #   class Ext                                           # < Tm_extension
    #     add_field :initial_collateral_ratio, T_uint16     # => BSIP-77
    #     add_field :maintenance_collateral_ratio, T_uint16 # => BSIP-75
    #     add_field :maximum_short_squeeze_ratio, T_uint16  # => BSIP-75
    #     add_field :margin_call_fee_ratio, T_uint16        # => BSIP 74
    #     add_field :force_settle_fee_percent, T_uint16     # => BSIP-87
    #     add_field :black_swan_response_method, T_uint8    # => https://github.com/bitshares/bitshares-core/issues/2467
    #   end

    #   add_field :feed_lifetime_sec, T_uint32
    #   add_field :minimum_feeds, T_uint8
    #   add_field :force_settlement_delay_sec, T_uint32
    #   add_field :force_settlement_offset_percent, T_uint16
    #   add_field :maximum_force_settlement_volume, T_uint16
    #   add_field :short_backing_asset, Tm_set(Tm_protocol_id_type(ObjectType::Asset))
    #   add_field :extensions, Ext
    # end

    # class T_price # < T_composite
    #   add_field :base, T_asset
    #   add_field :quote, T_asset
    # end

    # class T_price_feed # < T_composite
    #   add_field :settlement_price, T_price
    #   add_field :maintenance_collateral_ratio, T_uint16
    #   add_field :maximum_short_squeeze_ratio, T_uint16
    #   add_field :core_exchange_rate, T_price
    # end

    # class OP_asset_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :symbol, T_string
    #   add_field :precision, T_uint8
    #   add_field :common_options, T_asset_options
    #   add_field :bitasset_opts, Tm_optional(T_bitasset_options)
    #   add_field :is_prediction_market, T_bool
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_update                          # < T_composite
    #   class Ext                                    # < Tm_extension
    #     add_field :new_precision, T_uint8          # => After BSIP48, the precision of an asset can be updated if no supply is available
    #     add_field :skip_core_exchange_rate, T_bool # => After BSIP48, if this option is set to true, the asset's core_exchange_rate won't be updated.
    #   end

    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :new_issuer, Tm_optional(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :new_options, T_asset_options
    #   add_field :extensions, Ext
    # end

    # class OP_asset_update_bitasset # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :new_options, T_bitasset_options
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_update_feed_producers # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :new_feed_producers, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_issue # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_to_issue, T_asset
    #   add_field :issue_to_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :memo, Tm_optional(T_memo_data)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_reserve # < T_composite
    #   add_field :fee, T_asset
    #   add_field :payer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount_to_reserve, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_fund_fee_pool # < T_composite
    #   add_field :fee, T_asset
    #   add_field :from_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :amount, T_share_type # only core asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_settle # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_global_settle # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_to_settle, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :settle_price, T_price
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_publish_feed                       # < T_composite
    #   class Ext                                       # < Tm_extension
    #     add_field :initial_collateral_ratio, T_uint16 # => After BSIP77, price feed producers can feed ICR too
    #   end

    #   add_field :fee, T_asset
    #   add_field :publisher, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :feed, T_price_feed
    #   add_field :extensions, Ext
    # end

    # class OP_witness_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :witness_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :url, T_string
    #   add_field :block_signing_key, Secp256k1Zkp::PublicKey
    # end

    # class OP_witness_update # < T_composite
    #   add_field :fee, T_asset
    #   add_field :witness, Tm_protocol_id_type(ObjectType::Witness)
    #   add_field :witness_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :new_url, Tm_optional(T_string)
    #   add_field :new_signing_key, Tm_optional(Secp256k1Zkp::PublicKey)
    # end

    # class T_op_wrapper # < T_composite
    #   add_field :op, T_operation
    # end

    # class OP_proposal_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :expiration_time, T_time_point_sec
    #   add_field :proposed_ops, Tm_array(T_op_wrapper)
    #   add_field :review_period_seconds, Tm_optional(T_uint32)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_proposal_update # < T_composite
    #   add_field :fee, T_asset
    #   add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :proposal, Tm_protocol_id_type(ObjectType::Proposal)

    #   add_field :active_approvals_to_add, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :active_approvals_to_remove, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :owner_approvals_to_add, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :owner_approvals_to_remove, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :key_approvals_to_add, Tm_set(Secp256k1Zkp::PublicKey)
    #   add_field :key_approvals_to_remove, Tm_set(Secp256k1Zkp::PublicKey)

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_proposal_delete # < T_composite
    #   add_field :fee, T_asset
    #   add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :using_owner_authority, T_bool
    #   add_field :proposal, Tm_protocol_id_type(ObjectType::Proposal)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_withdraw_permission_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :authorized_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :withdrawal_limit, T_asset
    #   add_field :withdrawal_period_sec, T_uint32
    #   add_field :periods_until_expiration, T_uint32
    #   add_field :period_start_time, T_time_point_sec
    # end

    # class OP_withdraw_permission_update # < T_composite
    #   add_field :fee, T_asset
    #   add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :authorized_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :permission_to_update, Tm_protocol_id_type(ObjectType::Withdraw_permission)
    #   add_field :withdrawal_limit, T_asset
    #   add_field :withdrawal_period_sec, T_uint32
    #   add_field :period_start_time, T_time_point_sec
    #   add_field :periods_until_expiration, T_uint32
    # end

    # class OP_withdraw_permission_claim # < T_composite
    #   add_field :fee, T_asset
    #   add_field :withdraw_permission, Tm_protocol_id_type(ObjectType::Withdraw_permission)
    #   add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :withdraw_to_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount_to_withdraw, T_asset
    #   add_field :memo, Tm_optional(T_memo_data)
    # end

    # class OP_withdraw_permission_delete # < T_composite
    #   add_field :fee, T_asset
    #   add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :authorized_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :withdrawal_permission, Tm_protocol_id_type(ObjectType::Withdraw_permission)
    # end

    # class OP_committee_member_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :committee_member_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :url, T_string
    # end

    # class OP_committee_member_update # < T_composite
    #   add_field :fee, T_asset
    #   add_field :committee_member, Tm_protocol_id_type(ObjectType::Committee_member)
    #   add_field :committee_member_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :new_url, Tm_optional(T_string)
    # end

    # # TODO:OP Committee_member_update_global_parameters = 31

    # class T_linear_vesting_policy_initializer # < T_composite
    #   add_field :begin_timestamp, T_time_point_sec
    #   add_field :vesting_cliff_seconds, T_uint32
    #   add_field :vesting_duration_seconds, T_uint32
    # end

    # class T_cdd_vesting_policy_initializer # < T_composite
    #   add_field :start_claim, T_time_point_sec
    #   add_field :vesting_seconds, T_uint32
    # end

    # class T_instant_vesting_policy_initializer # < T_composite
    # end

    # alias T_vesting_policy_initializer = Tm_static_variant(T_linear_vesting_policy_initializer, T_cdd_vesting_policy_initializer, T_instant_vesting_policy_initializer)

    # class OP_vesting_balance_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :creator, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :owner, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount, T_asset
    #   add_field :policy, T_vesting_policy_initializer
    # end

    # class OP_vesting_balance_withdraw # < T_composite
    #   add_field :fee, T_asset
    #   add_field :vesting_balance, Tm_protocol_id_type(ObjectType::Vesting_balance)
    #   add_field :owner, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount, T_asset
    # end

    # class T_vesting_balance_worker_initializer # < T_composite
    #   add_field :pay_vesting_period_days, T_uint16
    # end

    # class T_burn_worker_initializer # < T_composite
    # end

    # class T_refund_worker_initializer # < T_composite
    # end

    # alias T_worker_initializer = Tm_static_variant(T_refund_worker_initializer, T_vesting_balance_worker_initializer, T_burn_worker_initializer)

    # class OP_worker_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :owner, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :work_begin_date, T_time_point_sec
    #   add_field :work_end_date, T_time_point_sec
    #   add_field :daily_pay, T_share_type
    #   add_field :name, T_string
    #   add_field :url, T_string

    #   add_field :initializer, T_worker_initializer
    # end

    # class OP_custom # < T_composite
    #   add_field :fee, T_asset
    #   add_field :payer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :required_auths, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :id, T_uint16
    #   add_field :data, Bytes
    # end

    # class T_account_storage_map # < T_composite
    #   add_field :remove, T_bool
    #   add_field :catalog, T_string
    #   add_field :key_values, Tm_map(T_string, Tm_optional(T_string))
    # end

    # class T_custom_plugin_operation # < T_composite
    #   add_field :data, Tm_static_variant(T_account_storage_map)
    # end

    # class T_assert_predicate_account_name_eq_lit # < T_composite
    #   add_field :account_id, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :name, T_string
    # end

    # class T_assert_predicate_asset_symbol_eq_lit # < T_composite
    #   add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :symbol, T_string
    # end

    # class T_assert_predicate_block_id # < T_composite
    #   add_field :id, FixedBytes(20)   # RMD160
    # end

    # alias T_assert_predicate = Tm_static_variant(T_assert_predicate_account_name_eq_lit, T_assert_predicate_asset_symbol_eq_lit, T_assert_predicate_block_id)

    # class OP_assert # < T_composite
    #   add_field :fee, T_asset
    #   add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :predicates, Tm_array(T_assert_predicate)
    #   add_field :required_auths, Tm_set(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_balance_claim # < T_composite
    #   add_field :fee, T_asset
    #   add_field :deposit_to_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :balance_to_claim, Tm_protocol_id_type(ObjectType::Balance)
    #   add_field :balance_owner_key, Secp256k1Zkp::PublicKey
    #   add_field :total_claimed, T_asset
    # end

    # class OP_override_transfer # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :from, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :to, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount, T_asset
    #   add_field :memo, Tm_optional(T_memo_data)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class T_stealth_confirmation_memo_data # < T_composite
    #   add_field :from, Tm_optional(Secp256k1Zkp::PublicKey)
    #   add_field :amount, T_asset
    #   add_field :blinding_factor, FixedBytes(32) # blind_factor_type -> SHA256
    #   add_field :commitment, FixedBytes(33)
    #   add_field :check, T_uint32
    # end

    # class T_stealth_confirmation # < T_composite
    #   add_field :one_time_key, Secp256k1Zkp::PublicKey
    #   add_field :to, Tm_optional(Secp256k1Zkp::PublicKey)
    #   add_field :encrypted_memo, Bytes
    # end

    # class T_blind_input # < T_composite
    #   add_field :commitment, FixedBytes(33)
    #   add_field :owner, T_authority
    # end

    # class T_blind_output # < T_composite
    #   add_field :commitment, FixedBytes(33)
    #   add_field :range_proof, Bytes # only required if there is more than one blind output
    #   add_field :owner, T_authority
    #   add_field :stealth_memo, Tm_optional(T_stealth_confirmation)
    # end

    # class OP_transfer_to_blind # < T_composite
    #   add_field :fee, T_asset
    #   add_field :amount, T_asset
    #   add_field :from, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :blinding_factor, FixedBytes(32) # blind_factor_type -> SHA256
    #   add_field :outputs, Tm_array(T_blind_output)
    # end

    # class OP_blind_transfer # < T_composite
    #   add_field :fee, T_asset
    #   add_field :inputs, Tm_array(T_blind_input)
    #   add_field :outputs, Tm_array(T_blind_output)
    # end

    # class OP_transfer_from_blind # < T_composite
    #   add_field :fee, T_asset
    #   add_field :amount, T_asset
    #   add_field :to, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :blinding_factor, FixedBytes(32) # blind_factor_type -> SHA256
    #   add_field :inputs, Tm_array(T_blind_input)
    # end

    # # TODO:OP virtual Asset_settle_cancel

    # class OP_asset_claim_fees # < T_composite
    #   class Ext               # < Tm_extension
    #     add_field :claim_from_asset_id, Tm_protocol_id_type(ObjectType::Asset)
    #   end

    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount_to_claim, T_asset # amount_to_claim.asset_id->issuer must == issuer
    #   add_field :extensions, Ext
    # end

    # # TODO:OP virtual Fba_distribute

    # class OP_bid_collateral # < T_composite
    #   add_field :fee, T_asset
    #   add_field :bidder, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :additional_collateral, T_asset
    #   add_field :debt_covered, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # # TODO:OP virtual Execute_bid

    # class OP_asset_claim_pool # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :amount_to_claim, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_asset_update_issuer # < T_composite
    #   add_field :fee, T_asset
    #   add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :new_issuer, Tm_optional(Tm_protocol_id_type(ObjectType::Account))
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # alias T_hash_rmd160 = FixedBytes(20)  # => RMD160
    # alias T_hash_sha1 = FixedBytes(20)    # => SHA1 or SHA160
    # alias T_hash_sha256 = FixedBytes(32)  # => SHA256
    # alias T_hash_hash160 = FixedBytes(20) # => HASH160 = RMD160(SHA256(data))
    # alias T_htlc_hash = Tm_static_variant(T_hash_rmd160, T_hash_sha1, T_hash_sha256, T_hash_hash160)

    # class OP_htlc_create # < T_composite
    #   class Ext          # < Tm_extension
    #     add_field :memo, T_memo_data
    #   end

    #   add_field :fee, T_asset
    #   add_field :from, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :to, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :amount, T_asset
    #   add_field :preimage_hash, T_htlc_hash
    #   add_field :preimage_size, T_uint16
    #   add_field :claim_period_seconds, T_uint32
    #   add_field :extensions, Ext
    # end

    # class OP_htlc_redeem # < T_composite
    #   add_field :fee, T_asset
    #   add_field :htlc_id, Tm_protocol_id_type(ObjectType::Htlc)
    #   add_field :redeemer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :preimage, Bytes
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # # TODO:OP virtual Htlc_redeemed

    # class OP_htlc_extend # < T_composite
    #   add_field :fee, T_asset
    #   add_field :htlc_id, Tm_protocol_id_type(ObjectType::Htlc)
    #   add_field :update_issuer, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :seconds_to_add, T_uint32
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # # TODO:OP virtual Htlc_refund

    # # TODO:OP 3
    # # Custom_authority_create                   = 54
    # # Custom_authority_update                   = 55
    # # Custom_authority_delete                   = 56

    # class OP_ticket_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :target_type, T_varint32 # see struct unsigned_int
    #   add_field :amount, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_ticket_update # < T_composite
    #   add_field :fee, T_asset
    #   add_field :ticket, Tm_protocol_id_type(ObjectType::Ticket)
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :target_type, T_varint32 # see struct unsigned_int
    #   add_field :amount_for_new_target, Tm_optional(T_asset)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_liquidity_pool_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :asset_a, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :asset_b, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :share_asset, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :taker_fee_percent, T_uint16
    #   add_field :withdrawal_fee_percent, T_uint16
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_liquidity_pool_delete # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_liquidity_pool_deposit # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
    #   add_field :amount_a, T_asset
    #   add_field :amount_b, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_liquidity_pool_withdraw # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
    #   add_field :share_amount, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_liquidity_pool_exchange # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
    #   add_field :amount_to_sell, T_asset
    #   add_field :min_to_receive, T_asset
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_samet_fund_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)

    #   add_field :asset_type, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :balance, T_int64
    #   add_field :fee_rate, T_uint32

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_samet_fund_delete # < T_composite
    #   add_field :fee, T_asset
    #   add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_samet_fund_update # < T_composite
    #   add_field :fee, T_asset
    #   add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

    #   add_field :delta_amount, Tm_optional(T_asset)
    #   add_field :new_fee_rate, Tm_optional(T_uint32)

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_samet_fund_borrow # < T_composite
    #   add_field :fee, T_asset
    #   add_field :borrower, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

    #   add_field :borrow_amount, T_asset

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_samet_fund_repay # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

    #   add_field :repay_amount, T_asset
    #   add_field :fund_fee, T_asset

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_credit_offer_create # < T_composite
    #   add_field :fee, T_asset
    #   add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)

    #   add_field :asset_type, Tm_protocol_id_type(ObjectType::Asset)
    #   add_field :balance, T_int64
    #   add_field :fee_rate, T_uint32

    #   add_field :max_duration_seconds, T_uint32
    #   add_field :min_deal_amount, T_int64
    #   add_field :enabled, T_bool
    #   add_field :auto_disable_time, T_time_point_sec

    #   add_field :acceptable_collateral, Tm_map(Tm_protocol_id_type(ObjectType::Asset), T_price)
    #   add_field :acceptable_borrowers, Tm_map(Tm_protocol_id_type(ObjectType::Account), T_int64)

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_credit_offer_delete # < T_composite
    #   add_field :fee, T_asset
    #   add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :offer_id, Tm_protocol_id_type(ObjectType::Credit_offer)

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_credit_offer_update # < T_composite
    #   add_field :fee, T_asset
    #   add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :offer_id, Tm_protocol_id_type(ObjectType::Credit_offer)

    #   add_field :delta_amount, Tm_optional(T_asset)
    #   add_field :fee_rate, Tm_optional(T_uint32)
    #   add_field :max_duration_seconds, Tm_optional(T_uint32)
    #   add_field :min_deal_amount, Tm_optional(T_int64)
    #   add_field :enabled, Tm_optional(T_bool)
    #   add_field :auto_disable_time, Tm_optional(T_time_point_sec)
    #   add_field :acceptable_collateral, Tm_optional(Tm_map(Tm_protocol_id_type(ObjectType::Asset), T_price))
    #   add_field :acceptable_borrowers, Tm_optional(Tm_map(Tm_protocol_id_type(ObjectType::Account), T_int64))

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_credit_offer_accept # < T_composite
    #   add_field :fee, T_asset
    #   add_field :borrower, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :offer_id, Tm_protocol_id_type(ObjectType::Credit_offer)

    #   add_field :borrow_amount, T_asset
    #   add_field :collateral, T_asset
    #   add_field :max_fee_rate, T_uint32
    #   add_field :min_duration_seconds, T_uint32

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class OP_credit_deal_repay # < T_composite
    #   add_field :fee, T_asset
    #   add_field :account, Tm_protocol_id_type(ObjectType::Account)
    #   add_field :deal_id, Tm_protocol_id_type(ObjectType::Credit_deal)

    #   add_field :repay_amount, T_asset
    #   add_field :credit_fee, T_asset

    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # # TODO:OP virtual Credit_deal_expired

    # class T_transaction # < T_composite
    #   add_field :ref_block_num, T_uint16
    #   add_field :ref_block_prefix, T_uint32
    #   add_field :expiration, T_time_point_sec
    #   add_field :operations, Tm_array(T_operation)
    #   add_field :extensions, Tm_set(T_future_extensions)
    # end

    # class T_signed_transaction < T_transaction
    #   add_field :signatures, Tm_array(FixedBytes(65))
    # end

    # # => 把所有的 operations 的序列化对象和 opcode 关联。
    # Opcode2optype = Hash(Int8, FieldType).new
    # {% for optype_klass in @type.constants %}
    #   {% if optype_klass.id =~ /^OP_/ %}
    #     %enum_field = Blockchain::Operations.parse?("{{ optype_klass.downcase }}".gsub(/op_/, "").capitalize)
    #     Opcode2optype[%enum_field.value] = {{ optype_klass.id }} if %enum_field
    #   {% end %}
    # {% end %}
  end
end

# => TODO:test
include Graphene::Operations
require "benchmark"

struct Test05
  @amount = 3
end

result = Benchmark.memory do
  1000.times {
    # Test05.new
    # Tm_protocol_id_type(ObjectType::Account).new(3_u64)
    op = OP_transfer.new
    op.from = Tm_protocol_id_type(ObjectType::Account).new(1_u64)
    op.to = Tm_protocol_id_type(ObjectType::Account).new(2_u64)
    op.amount = T_asset.new(101_i64, 3_u64)
    # op.pack
    # Graphene::Serialize::Pack(OP_transfer).unpack(op.pack)
  }
end
p! result
