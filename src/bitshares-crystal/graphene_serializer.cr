require "crystal-secp256k1-zkp" # => for Secp256k1Zkp
require "./define"              # => for Tm_protocol_id_type

module Graphene
  module Serialize
    # :nodoc:
    private module Varint
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
    private class BinaryIO < IO::Memory
      # :nodoc:
      def write_varint32(value : Varint::VarintIntType)
        Varint.encode(value, self)
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
    end

    # :nodoc:
    module Pack(T)
      def pack
        BinaryIO.new.tap { |io| pack(io) }.to_slice
      end

      def self.unpack(data : Bytes)
        return T.unpack(BinaryIO.new(data))
      end
    end

    # :nodoc:
    module Composite(T)
      include Pack(T)

      def pack(io)
        {% for ivar in @type.instance_vars %}
          {% if ivar.has_default_value? %}
            raise Unsupported_default_value.new("Composite(T) do not support default values. please use the initialize method.")
          {% end %}
          @{{ ivar.id }}.pack(io)
        {% end %}
      end

      def __unpack_all_instance_vars(io)
        {% for ivar in @type.instance_vars %}
          {% if ivar.has_default_value? %}
            raise Unsupported_default_value.new("Composite(T) do not support default values. please use the initialize method.")
          {% end %}
          @{{ ivar.id }} = {{ ivar.type.id }}.unpack(io)
        {% end %}
      end

      macro included

        def self.unpack(io) : self

          {% if @type.struct? %}
            target = uninitialized T
          {% else %}
            target = T.new
          {% end %}

          target.__unpack_all_instance_vars(io)
          return target
        end

      end
    end

    # :nodoc:
    module Extension(T)
      include Pack(T)

      def pack(io)
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
              optional_value.value.not_nil!.pack(io)
            end
          {% end %}
        end
      end

      def __unpack_all_instance_vars(io)
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
                @{{ all_ivars[i].id }}.value = typeof(@{{ all_ivars[i].id }}.value.not_nil!).unpack(io)
            {% end %}
            end
            
          end
        {% end %}
      end

      macro included

        def self.unpack(io) : self
          target = T.new
          target.__unpack_all_instance_vars(io)
          return target
        end

      end
    end

    # :nodoc:
    struct Tm_protocol_id_type(ReqObjectType)
      private RegProtocalIdFormat = /^[\d]+\.([\d]+)\.([\d]+)$/

      include Comparable(self)                # => 支持比较运算，需要实现 <=> 方法。
      include Graphene::Serialize::Pack(self) # => 支持石墨烯序列化

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
        if RegProtocalIdFormat =~ oid
          found_object_type = $1.to_i8
          raise "Invalid object id, object type is: #{BitShares::Blockchain::ObjectType.new(found_object_type)}, required: #{__generics_type_helper}." if found_object_type != __generics_type_helper.value
          @instance = $2.to_u64
        else
          raise "Invalid object id: #{oid}"
        end
      end

      def pack(io)
        io.write_varint32(@instance.to_u32)
      end

      def self.unpack(io) : self
        return new(io.read_varint32)
      end

      # => 实现比较运算。
      def <=>(other)
        return @instance <=> other.instance
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

      def pack(io)
        if v = @value
          io.write_byte(1_u8)
          v.pack(io)
        else
          io.write_byte(0_u8)
        end
      end

      def self.unpack(io) : self
        value = if io.read_byte.not_nil! == 0
                  nil
                else
                  T.unpack(io)
                end
        return new(value)
      end
    end

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

      def pack(io)
        # => 1、write index
        io.write_varint32(@index)

        # => 2、write opdata
        {% begin %}
          case @value
          {% for i in 0...T.size %}
            when T[{{i}}]
              T[{{i}}].cast(@value).pack(io)
          {% end %}
          else
            raise "unknown type"
          end
        {% end %}
      end

      def self.unpack(io) : self
        index = io.read_varint32
        optype = index_to_optype(index)
        raise "invalid type id: #{index}" if optype.nil?

        return new(optype.unpack(io))
      end

      # def self.to_object(opdata : Raw?) : Raw?
      #   opdata = opdata.not_nil!.as_a
      #   assert(opdata.size == 2)
      #   type_id = opdata[0].as_i.to_i32

      #   optype = type_id_to_optype(type_id)
      #   raise "invalid type id: #{type_id}" if optype.nil?

      #   return Raw.new([Raw.new(type_id), optype.to_object(opdata.last).not_nil!])
      # end

    end

    # :nodoc:
    #
    #  [{Key1, Value1}, {Key2, Value2}, ...]
    struct Tm_map(KeyT, ValueT)
      @flat_list = Array(Tuple(KeyT, ValueT)).new

      def add(item : Tuple(KeyT, ValueT))
        @flat_list << item
      end

      def each(&blk : Tuple(KeyT, ValueT) -> _)
        @flat_list.each(&blk)
      end

      def pack(io)
        io.write_varint32(@flat_list.size)

        sort_data.each do |tuple|
          tuple[0].pack(io)
          tuple[1].pack(io)
        end
      end

      def self.unpack(io) : self
        result = new

        len = io.read_varint32
        len.times do
          result.add({KeyT.unpack(io), ValueT.unpack(io)})
        end

        return result
      end

      def sort_data
        # => TODO: nosort
        # => TODO: sort by
        return @flat_list if @flat_list.size <= 1
        return @flat_list.sort { |a, b| a[0] <=> b[0] }
      end
    end

    # => TODO:元素不可重复？限制...
    struct Tm_set(T)
      @flat_list = Array(T).new

      def add(item : T)
        @flat_list << item
      end

      def each(&blk : T -> _)
        @flat_list.each(&blk)
      end

      def pack(io)
        io.write_varint32(@flat_list.size)
        sort_data.each &.pack(io)
      end

      def self.unpack(io) : self
        len = io.read_varint32

        result = new(len)

        len.times { result.add(T.unpack(io)) }

        return result
      end

      def sort_data
        # => TODO: nosort
        # => TODO: sort by
        return @flat_list if @flat_list.size <= 1
        return @flat_list.sort { |a, b| a <=> b }
      end
    end

    # 空集合，用于代替 Set(T_future_extensions) 类型，提高效率。避免 Set 分配堆内存。
    struct Tm_empty_set(T)
      include Graphene::Serialize::Pack(self)

      def pack(io)
        io.write_varint32(0)
      end

      def self.unpack(io) : self
        len = io.read_varint32

        raise "Empty set size must be zero." if len != 0

        return new
      end
    end

    alias T_share_type = Int64

    # => TODO:u32 or u64
    struct T_varint32
      include Graphene::Serialize::Pack(self)

      getter value : UInt32

      def initialize(@value)
      end

      def pack(io)
        io.write_bytes(@value)
      end

      def self.unpack(io) : self
        return new(io.read_varint32.to_u32)
      end
    end

    struct T_void
      include Graphene::Serialize::Pack(self)

      def pack(io)
      end

      def self.unpack(io) : self
        return new
      end
    end

    alias T_future_extensions = T_void

    struct T_vote_id
      private RegVoteIdFormat = /^([0-9]+):([0-9]+)$/

      include Comparable(self)                # => 支持比较运算，需要实现 <=> 方法。
      include Graphene::Serialize::Pack(self) # => 支持石墨烯序列化。

      @content : UInt32 = 0 # => 低 8 位是 vote type，高 24 位是 instance id。

      def vote_type : UInt8
        (@content & 0xff).to_u8
      end

      def vote_instance_id : UInt32
        @content >> 8
      end

      def to_s : String
        return "#{vote_type}:#{vote_instance_id}"
      end

      def initialize(@content : UInt32)
      end

      def initialize(value : String)
        if RegVoteIdFormat =~ value
          type = $1.to_u8
          instance_id = $2.to_u32
          @content = (instance_id << 8) | type
        else
          raise "Invalid vote id: #{value}"
        end
      end

      def pack(io)
        io.write_bytes(@content)
      end

      def self.unpack(io) : self
        return new(io.read_bytes(UInt32))
      end

      # => 实现比较运算。
      def <=>(other)
        return vote_instance_id <=> other.vote_instance_id
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

      def pack(io)
        @value.pack(io)
      end

      def self.unpack(io) : self
        return new(UInt32.unpack(io))
      end
    end
  end
end

# 全局宏
#
# 定义可以序列化的结构体。
# 参考 record 宏。
macro graphene_struct(name, *properties)
  struct {{name.id}}
    
    include Graphene::Serialize::Composite(self)

    {% for property in properties %}
      {% if property.is_a?(TypeDeclaration) %}
        getter {{property}}
      {% else %}
        getter :{{property.id}}
      {% end %}
    {% end %}

    def initialize({{
                     *properties.map do |field|
                       "@#{field.id}".id
                     end
                   }})
    end

    {{yield}}
    
  end
end

struct Bool
  include Graphene::Serialize::Pack(self)

  def pack(io)
    io.write_byte(self ? 1_u8 : 0_u8)
  end

  def self.unpack(io) : self
    io.read_byte.not_nil! != 0
  end
end

struct UInt8
  include Graphene::Serialize::Pack(self)

  def pack(io)
    io.write_byte(self)
  end

  def self.unpack(io) : self
    io.read_byte.not_nil!
  end
end

{% begin %}

  {% for int in %w(UInt16 UInt32 UInt64 Int64) %}
    struct {{int.id}}

      include Graphene::Serialize::Pack(self)

      def pack(io)
        io.write_bytes(self)
      end

      def self.unpack(io) : self
        io.read_bytes({{int.id}})
      end
    end
  {% end %}

{% end %}

struct Enum
  include Graphene::Serialize::Pack(self)

  def pack(io)
    self.value.pack(io)
  end

  def self.unpack(io) : self
    return new(typeof(self.values.first.value).unpack(io))
  end
end

class String
  include Graphene::Serialize::Pack(self)

  def pack(io)
    io.write_varint32(self.bytesize)
    io.write(self.to_slice)
  end

  def self.unpack(io) : self
    io.read_string(io.read_varint32)
  end
end

class Array(T)
  include Graphene::Serialize::Pack(self)

  def pack(io)
    io.write_varint32(self.size)
    each(&.pack(io))
  end

  def self.unpack(io) : self
    return new(io.read_varint32) { T.unpack(io) }
  end
end

# => aka Bytes
struct Slice(T)
  include Graphene::Serialize::Pack(self)

  def pack(io)
    {% if T == UInt8 %}
      io.write_varint32(self.size)
      io.write(self)
    {% else %}
      raise "unsupported type."
    {% end %}
  end

  def self.unpack(io) : self
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
  include Graphene::Serialize::Pack(self)

  getter value : Bytes

  def initialize(bytes : Bytes)
    raise "size error." if bytes.size != Size
    @value = bytes
  end

  def pack(io)
    io.write(@value)
  end

  def self.unpack(io) : self
    slice = Bytes.new(Size.as?(Int32).not_nil!)
    io.read(slice)
    return new(slice)
  end
end

struct StaticFixedBytes(Size)
  include Graphene::Serialize::Pack(self)

  getter unsafe_value : StaticArray(UInt8, Size)

  def initialize(bytes : Bytes)
    raise "size error." if bytes.size != Size
    @unsafe_value = StaticArray(UInt8, Size).new { |i| bytes[i] }
  end

  def pack(io)
    io.write(@unsafe_value.to_slice)
  end

  def self.unpack(io) : self
    target = uninitialized self

    io.read(target.unsafe_value.to_slice)

    return target
  end
end

class Secp256k1Zkp::PublicKey
  include Comparable(self)                # => 支持比较运算，需要实现 <=> 方法。
  include Graphene::Serialize::Pack(self) # => 支持石墨烯序列化

  def pack(io)
    io.write(self.bytes)
  end

  def self.unpack(io) : self
    return new(io.read_n_bytes(33))
  end

  # => 实现比较运算。
  def <=>(other)
    return self.to_address.bytes <=> other.to_address.bytes
  end
end

class Secp256k1Zkp::Address
  include Graphene::Serialize::Pack(self)

  def pack(io)
    raise "not supported"
  end

  def self.unpack(io) : self
    raise "not supported"
  end
end
