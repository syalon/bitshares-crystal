module BitShares
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
    alias FieldType = T_Base.class | Tm_Base

    # :nodoc:
    struct Raw
      alias SubscribeCallbackType = (Bool, JSON::Any | String) -> Bool

      alias PrimitiveType = Bool | Int8 | Int16 | Int32 | Int64 | UInt8 | UInt16 | UInt32 | UInt64 | Float32 | Float64 | String | Bytes | SubscribeCallbackType
      alias ArrayType = Array(self)
      alias HashType = Hash(String, self)
      alias ValueType = PrimitiveType | ArrayType | HashType

      property value : ValueType

      def as_b : Bool
        @value.as(Bool)
      end

      def as_b? : Bool?
        as_b if @value.is_a?(Bool)
      end

      def as_i : Int
        @value.as(Int)
      end

      def as_i? : Int?
        as_i if @value.is_a?(Int)
      end

      def as_s : String
        @value.as(String)
      end

      def as_s? : String?
        as_s if @value.is_a?(String)
      end

      def as_h : HashType
        @value.as(Hash)
      end

      def as_h? : HashType?
        as_h if @value.is_a?(Hash)
      end

      def as_a : ArrayType
        @value.as(Array)
      end

      def as_a? : ArrayType?
        as_a if @value.is_a?(Array)
      end

      def as_bytes : Bytes
        @value.as(Bytes)
      end

      def as_bytes? : Bytes?
        as_bytes if @value.is_a?(Bytes)
      end

      def as_callback : SubscribeCallbackType
        @value.as(SubscribeCallbackType)
      end

      def as_callback? : SubscribeCallbackType?
        as_callback if @value.is_a?(SubscribeCallbackType)
      end

      def to_json(json : JSON::Builder) : Nil
        v = @value
        raise "unsupported json value: #{v}" if v.is_a?(Bytes)
        raise "unsupported json value: #{v}" if v.is_a?(SubscribeCallbackType)
        v.to_json(json)
      end

      def to_i32 : Int32
        return as_s.to_i32 if @value.is_a?(String)
        return as_i.to_i32
      end

      def to_u32 : UInt32
        return as_s.to_u32 if @value.is_a?(String)
        return as_i.to_u32
      end

      def to_i64 : Int64
        return as_s.to_i64 if @value.is_a?(String)
        return as_i.to_i64
      end

      def to_u64 : UInt64
        return as_s.to_u64 if @value.is_a?(String)
        return as_i.to_u64
      end

      def inspect(io : IO) : Nil
        @value.inspect(io)
      end

      def to_s(io : IO) : Nil
        @value.to_s(io)
      end

      def initialize(@value)
      end

      def self.new(value : ValueType) : self
        instance = allocate
        instance.initialize(value)
        instance
      end

      def self.new(value) : self
        case value
        when Hash, NamedTuple
          return new(Hash(String, self).new.tap { |result| value.each { |k, v| result[k.to_s] = new(v) unless v.nil? } })
        when Array, Tuple
          return new(Array(self).new.tap { |result| value.each { |v| result << new(v) unless v.nil? } })
        when Raw
          return value
        when JSON::Any
          # All possible JSON types.
          # alias Type = Nil | Bool | Int64 | Float64 | String | Array(Any) | Hash(String, Any)
          case v = value.raw
          when Bool
            return new(v.as(Bool))
          when Int
            return new(v.as(Int).to_i64)
          when Float
            return new(v.as(Float64))
          when String
            return new(v.as(String))
          when Array
            return new(v.as(Array))
          when Hash
            return new(v.as(Hash))
          else
            raise "Invalid JSON::Any value `#{v}`"
          end
        when PrimitiveType
          return new(value)
        else
          raise "Unsupported type: #{typeof(value)} value: #{value}"
        end
      end
    end

    # :nodoc:
    struct Field
      getter symbol : Symbol
      getter type : FieldType
      getter name : String

      def self.[](symbol : Symbol, type : FieldType)
        return Field.new(symbol, type)
      end

      def initialize(@symbol : Symbol, @type : FieldType)
        @name = @symbol.to_s
      end

      def inspect(io : IO) : Nil
        # {name : type}
        io << "{"
        io << @name
        io << " : "
        io << @type
        io << "}"
      end
    end

    # :nodoc:
    struct Arguments
      getter graphene_address_prefix : String

      def initialize(@graphene_address_prefix : String)
      end
    end

    # :nodoc:
    class T_Base
      #
      # (public) 编码为二进制流
      #
      def self.to_binary(opdata, graphene_address_prefix = "")
        return BinaryIO.new.tap { |io| to_byte_buffer(io, Arguments.new(graphene_address_prefix), Raw.new(opdata)) }.to_slice
      end

      #
      # (public) 序列化为 json 对象。这里新返回的 json 对象和原参数的 opdata 差别不大，主要是一些 NSData 等二进制流会转换为 16 进制编码。
      #
      def self.to_json(opdata, graphene_address_prefix = "") : Raw
        return to_object(Arguments.new(graphene_address_prefix), Raw.new(opdata))
      end

      #
      # (public) 反序列化，解析二进制流为 opdata 对象。
      #
      def self.parse(data : Bytes, graphene_address_prefix = "") : Raw?
        if (result = from_byte_buffer(BinaryIO.new(data), Arguments.new(graphene_address_prefix))) != nil # REMARK: false is valid value
          Raw.new(result)
        else
          nil
        end
      end

      def self.to_byte_buffer(io, args : Arguments, opdata : Raw?)
        raise "unsupported value '#{opdata}' (#{opdata.class}) for '#{self.name}'." # only for compiler
      end

      def self.from_byte_buffer(io, args : Arguments)
        return nil
      end

      def self.to_object(args : Arguments, opdata : Raw?) : Raw?
        return opdata
      end

      # 排序：部分类型序列化需要排序。各种类型可以通过实现：sort_by 方法自定义排序。
      def self.sort_opdata_array(args : Arguments, array : Array(Raw), sort_by_optype : FieldType)
        # => no need to sort
        return array if array.size <= 1

        # => no sort
        return array if sort_by_optype.responds_to?(:nosort) && sort_by_optype.nosort

        # => sort using custom compare func
        if sort_by_optype.responds_to?(:sort_by)
          return array.sort { |obj1, obj2|
            ary1 = obj1.as_a?
            ary2 = obj2.as_a?
            a = ary1 ? ary1.first : obj1
            b = ary2 ? ary2.first : obj2
            sort_by_optype.sort_by(args, a, b).as(Int32)
          }
        end

        # # => sort use default compare func
        # return array.sort

        # TODO:不排序
        return array
      end
    end

    class T_composite < T_Base
      @@_fields = [] of Field

      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        if !@@_fields.empty?
          h = opdata.as_h
          @@_fields.each { |field| field.type.to_byte_buffer(io, args, h[field.name]? || h[field.symbol]?) }
        end
      end

      def self.from_byte_buffer(io, args : Arguments)
        if @@_fields.empty?
          nil
        else
          result = Raw::HashType.new
          @@_fields.each do |field|
            if (value = field.type.from_byte_buffer(io, args)) != nil # REMARK: false is valid value
              result[field.name] = Raw.new(value)
            end
          end
          return result
        end
      end

      def self.to_object(args : Arguments, opdata : Raw) : Raw?
        if @@_fields.empty?
          return opdata
        else
          h = opdata.as_h
          result = Hash(String, Raw).new
          @@_fields.each do |field|
            obj = field.type.to_object(args, h[field.name]? || h[field.symbol]?)
            if obj
              result[field.name] = obj
            else
              BitShares::Serialize::Tm_optional(BitShares::Operations::T_memo_data)
              raise "the '#{field.name}' field is missing. #{field.type}" unless field.type.is_a?(T_Base.class) && field.type.as(T_Base.class) < Tm_optional
            end
          end
          return Raw.new(result)
        end
      end

      # :nodoc:
      macro define(name, type)
        add_field(:{{ name.id }}, {{ type }})
      end

      private def self.add_field(symbol : Symbol, type : FieldType)
        @@_fields << Field.new(symbol, type)
      end

      # REMARK: 自动继承父类的字段定义
      def self.get_all_fields
        @@_fields
      end

      def self.inherited_fields(super_class)
        @@_fields.concat(super_class.get_all_fields)
      end

      macro inherited
        {{ @type }}.inherited_fields({{ @type.superclass }})
      end
    end

    class T_uint8 < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_byte(opdata.as_i.to_u8)
      end

      def self.from_byte_buffer(io, args : Arguments)
        return io.read_byte.not_nil!
      end
    end

    class T_uint16 < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_bytes(opdata.as_i.to_u16)
      end

      def self.from_byte_buffer(io, args : Arguments)
        io.read_bytes(UInt16)
      end
    end

    class T_uint32 < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_bytes(opdata.as_i.to_u32)
      end

      def self.from_byte_buffer(io, args : Arguments)
        io.read_bytes(UInt32)
      end
    end

    class T_uint64 < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_bytes(opdata.to_u64)
      end

      def self.from_byte_buffer(io, args : Arguments)
        io.read_bytes(UInt64)
      end
    end

    class T_int64 < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_bytes(opdata.to_i64)
      end

      def self.from_byte_buffer(io, args : Arguments)
        io.read_bytes(Int64)
      end
    end

    class T_share_type < T_int64
    end

    class T_varint32 < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_varint32(opdata.as_i.to_u32)
      end

      def self.from_byte_buffer(io, args : Arguments)
        io.read_varint32
      end
    end

    class T_string < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        opdata = opdata.as_s

        io.write_varint32(opdata.bytesize)
        io.write(opdata.to_slice)
      end

      def self.from_byte_buffer(io, args : Arguments)
        io.read_string(io.read_varint32)
      end
    end

    class T_bool < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_byte(opdata.as_b ? 1_u8 : 0_u8)
      end

      def self.from_byte_buffer(io, args : Arguments)
        return io.read_byte.not_nil! != 0
      end
    end

    class T_void < T_Base
    end

    class T_future_extensions < T_Base
    end

    # TODO:
    # @interface T_object_id_type : T_Base
    # @end

    class T_vote_id < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        opdata = opdata.as_s

        if /^[0-9]+:[0-9]+$/ =~ opdata
          type, id = opdata.split(":").map &.to_i
          # TODO:check
          # v.require_range(0, 0xff, type, `vote type ${object}`);
          # v.require_range(0, 0xffffff, id, `vote id ${object}`);
          io.write_bytes(((id << 8) | type).to_u32)
        else
          raise "Invalid vote id: #{opdata}"
        end
      end

      def self.from_byte_buffer(io, args : Arguments)
        value = io.read_bytes(UInt32)

        id = (value & 0xffffff00) >> 8
        type = value & 0xff
        return "#{type}:#{id}"
      end

      def self.sort_by(args : Arguments, a : Raw, b : Raw)
        return a.as_s.split(':').last.to_i <=> b.as_s.split(':').last.to_i
      end
    end

    class T_public_key < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        opdata = opdata.as_s

        io.write(Secp256k1Zkp::PublicKey.from_wif(opdata, args.graphene_address_prefix).bytes)
      end

      def self.from_byte_buffer(io, args : Arguments)
        return Secp256k1Zkp::PublicKey.new(io.read_n_bytes(33)).to_wif(args.graphene_address_prefix)
      end

      def self.sort_by(args : Arguments, a : Raw, b : Raw)
        return Secp256k1Zkp::PublicKey.from_wif(a.as_s, args.graphene_address_prefix).to_address.bytes <=> Secp256k1Zkp::PublicKey.from_wif(b.as_s, args.graphene_address_prefix).to_address.bytes
      end
    end

    class T_address < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        raise "not supported"
      end

      def self.from_byte_buffer(io)
        raise "not supported"
      end
    end

    class T_time_point_sec < T_uint32
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        case var = opdata.value
        when String
          io.write_bytes(BitShares::Utility.parse_time_string_i64(var).to_u32)
        else
          super(io, args, opdata)
        end
      end

      def self.to_object(args : Arguments, opdata : Raw) : Raw?
        # => 格式：2018-06-04T13:03:57
        return Raw.new(Time.unix(opdata.as_i.to_i64).to_utc.to_s("%Y-%m-%dT%H:%M:%S"))
      end
    end

    #
    # 动态扩展类型，部分类型采用 Generics 泛型特性处理，对于不支持的常量参数类型，则采用 Tm_Base 子类实现。
    #
    # Generics支持的常量参数类型有限。
    # to_object
    abstract class Tm_Base < T_Base
      def self.[](only_one_arg)
        new(only_one_arg)
      end

      def self.[](first, seconds, *others)
        new([first, seconds, *others]) # Tuple to Array
      end

      abstract def to_byte_buffer(io, args : Arguments, opdata : Raw?)
      abstract def from_byte_buffer(io, args : Arguments)
      abstract def to_object(args : Arguments, opdata : Raw?) : Raw?
    end

    class Tm_protocol_id_type(ReqObjectType) < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        io.write_object_id(opdata.as_s, ReqObjectType)
      end

      def self.from_byte_buffer(io, args : Arguments)
        "1.#{ReqObjectType.value}.#{io.read_varint32}"
      end

      def self.to_object(args : Arguments, opdata : Raw?) : Raw?
        return opdata
      end

      def self.sort_by(args : Arguments, a : Raw, b : Raw)
        return a.as_s.split(".").last.to_i <=> b.as_s.split(".").last.to_i
      end
    end

    class Tm_extension < Tm_Base
      @fields_defs = [] of Field

      def initialize(fields_defs : Field | Array(Field))
        if fields_defs.is_a?(Field)
          @fields_defs << fields_defs
        else
          fields_defs.each { |f| @fields_defs << f }
        end
      end

      def to_byte_buffer(io, args : Arguments, opdata : Raw?)
        opdata = opdata.try(&.as_h?)

        # 统计出现的扩展字段数量
        field_count = 0
        @fields_defs.each { |fields| field_count += 1 if opdata.has_key?(fields.name) } if opdata

        # 写入扩展字段数量
        io.write_varint32(field_count)

        # 写入扩展字段的值
        if opdata && field_count > 0
          @fields_defs.each_with_index do |fields, idx|
            obj = opdata[fields.name]?
            if obj
              io.write_varint32(idx)
              fields.type.to_byte_buffer(io, args, obj)
            end
          end
        end
      end

      def from_byte_buffer(io, args : Arguments)
        len = io.read_varint32
        raise "Too many fields" if len > @fields_defs.size
        return nil if len == 0

        result = Raw::HashType.new
        len.times do |i|
          idx = io.read_varint32
          raise "Index out of range" if idx >= @fields_defs.size
          field = @fields_defs[idx]
          if (value = field.type.from_byte_buffer(io, args)) != nil # REMARK: false is valid value
            result[field.name] = Raw.new(value)
          end
        end
        return result
      end

      def to_object(args : Arguments, opdata : Raw?) : Raw?
        result = Hash(String, Raw).new

        opdata = opdata.try(&.as_h?)
        if opdata
          @fields_defs.each do |fields|
            obj = opdata[fields.name]?
            result[fields.name] = fields.type.to_object(args, obj).not_nil! if obj
          end
        end

        return Raw.new(result)
      end
    end

    class Tm_array < Tm_Base
      def initialize(@optype : FieldType)
      end

      def to_byte_buffer(io, args : Arguments, opdata : Raw?)
        opdata = opdata.not_nil!.as_a
        io.write_varint32(opdata.size)
        opdata.each { |sub_opdata| @optype.to_byte_buffer(io, args, sub_opdata) }
      end

      def from_byte_buffer(io, args : Arguments)
        len = io.read_varint32

        result = Raw::ArrayType.new
        if len > 0
          len.times do
            # => REMARK：数组不应该返回 null
            result << Raw.new(@optype.from_byte_buffer(io, args).not_nil!)
          end
        end

        return result
      end

      def to_object(args : Arguments, opdata : Raw?) : Raw?
        opdata = opdata.try(&.as_a).not_nil!

        ary = [] of Raw
        opdata.each { |sub_opdata| ary << @optype.to_object(args, sub_opdata).not_nil! }

        return Raw.new(ary)
      end
    end

    class Tm_map(KeyT, ValueT) < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        opdata = sort_opdata_array(args, opdata.as_a, KeyT)

        io.write_varint32(opdata.size)
        opdata.each do |subvalue|
          pair = subvalue.as_a
          assert(pair.size == 2)
          KeyT.to_byte_buffer(io, args, pair[0])
          ValueT.to_byte_buffer(io, args, pair[1])
        end
      end

      def self.from_byte_buffer(io, args : Arguments)
        len = io.read_varint32

        result = Raw::ArrayType.new

        len.times do
          # TODO: result is nil?
          result << Raw.new([KeyT.from_byte_buffer(io, args).not_nil!, ValueT.from_byte_buffer(io, args).not_nil!])
        end

        return result
      end

      def self.to_object(args : Arguments, opdata : Raw) : Raw?
        ary = [] of Raw

        sort_opdata_array(args, opdata.as_a, KeyT).each do |subvalue|
          pair = subvalue.as_a
          assert(pair.size == 2)
          ary << Raw.new([KeyT.to_object(args, pair[0]).not_nil!, ValueT.to_object(args, pair[1]).not_nil!])
        end

        return Raw.new(ary)
      end
    end

    # 不可重复的元素 *有序* 集合
    # ```
    # [1, 2, 3]
    # ```
    class Tm_set(T) < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw?)
        opdata = opdata.try(&.as_a?) || [] of Raw

        opdata = sort_opdata_array(args, opdata, T)

        io.write_varint32(opdata.size)
        opdata.each { |sub_opdata| T.to_byte_buffer(io, args, sub_opdata) }
      end

      def self.from_byte_buffer(io, args : Arguments)
        len = io.read_varint32

        result = Raw::ArrayType.new
        if len > 0
          len.times do
            # => REMARK：数组不应该返回 null
            result << Raw.new(T.from_byte_buffer(io, args).not_nil!)
          end
        end

        return result
      end

      def self.to_object(args : Arguments, opdata : Raw?) : Raw?
        opdata = opdata.try(&.as_a?)

        ary = [] of Raw

        sort_opdata_array(args, opdata, T).each { |sub_opdata| ary << T.to_object(args, sub_opdata).not_nil! } if opdata

        return Raw.new(ary)
      end
    end

    class Tm_bytes(Size) < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw)
        opdata = case var = opdata.value
                 when String
                   var.hexbytes
                 else
                   opdata.as_bytes
                 end

        if Size == Nil
          io.write_varint32(opdata.size)
        else
          assert(opdata.size == Size)
        end
        io.write(opdata)
      end

      def self.from_byte_buffer(io, args : Arguments)
        slice = if Size == Nil
                  Bytes.new(io.read_varint32)
                else
                  Bytes.new(Size.as?(Int32).not_nil!)
                end

        io.read(slice)
        return slice
      end

      def self.to_object(args : Arguments, opdata : Raw) : Raw?
        bytes = opdata.as_bytes
        assert(Size == Nil || bytes.size == Size)
        return Raw.new(bytes.hexstring)
      end
    end

    class Tm_optional(T) < T_Base
      def self.to_byte_buffer(io, args : Arguments, opdata : Raw?)
        if opdata.nil?
          io.write_byte(0_u8)
        else
          io.write_byte(1_u8)
          T.to_byte_buffer(io, args, opdata)
        end
      end

      def self.from_byte_buffer(io, args : Arguments)
        if io.read_byte.not_nil! == 0
          nil
        else
          T.from_byte_buffer(io, args)
        end
      end

      def self.to_object(args : Arguments, opdata : Raw?) : Raw?
        return T.to_object(args, opdata) if opdata
        return nil
      end
    end

    class Tm_static_variant < Tm_Base
      @optype_array = [] of FieldType

      def initialize(optype_array : FieldType | Array(FieldType))
        if optype_array.is_a?(FieldType)
          @optype_array << optype_array
        else
          optype_array.each { |v| @optype_array << v }
        end
      end

      def to_byte_buffer(io, args : Arguments, opdata : Raw?)
        opdata = opdata.not_nil!.as_a

        assert(opdata.size == 2)
        type_id = opdata[0].as_i.to_i32
        optype = @optype_array[type_id]
        # => 1、write typeid  2、write opdata
        io.write_varint32(type_id)
        optype.to_byte_buffer(io, args, opdata.last)
      end

      def from_byte_buffer(io, args : Arguments)
        type_id = io.read_varint32
        optype = @optype_array[type_id]

        result = Raw::ArrayType.new
        result << Raw.new(type_id)
        result << Raw.new(optype.from_byte_buffer(io, args).not_nil!)
        return result
      end

      def to_object(args : Arguments, opdata : Raw?) : Raw?
        opdata = opdata.not_nil!.as_a

        assert(opdata.size == 2)
        type_id = opdata[0].as_i.to_i32
        optype = @optype_array[type_id]

        return Raw.new([Raw.new(type_id), optype.to_object(args, opdata.last).not_nil!])
      end

      # 该类型不需要排序
      def nosort
        true
      end
    end
  end

  # 石墨烯支持的各种操作对象结构定义。
  module Operations
    include Serialize
    include Blockchain

    class T_Test < T_composite
      add_field :amount, T_uint8
      add_field :amount_array, Tm_array[T_uint8]
    end

    class T_operation < T_composite
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
    class T_asset < T_composite
      add_field :amount, T_share_type
      add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
    end

    class T_memo_data < T_composite
      add_field :from, T_public_key
      add_field :to, T_public_key
      add_field :nonce, T_uint64
      add_field :message, Tm_bytes(Nil)
    end

    class OP_transfer < T_composite
      add_field :fee, T_asset
      add_field :from, Tm_protocol_id_type(ObjectType::Account)
      add_field :to, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount, T_asset
      add_field :memo, Tm_optional(T_memo_data)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_limit_order_create < T_composite
      add_field :fee, T_asset
      add_field :seller, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount_to_sell, T_asset
      add_field :min_to_receive, T_asset
      add_field :expiration, T_time_point_sec
      add_field :fill_or_kill, T_bool
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_limit_order_cancel < T_composite
      add_field :fee, T_asset
      add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :order, Tm_protocol_id_type(ObjectType::Limit_order)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_call_order_update < T_composite
      add_field :fee, T_asset
      add_field :funding_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :delta_collateral, T_asset
      add_field :delta_debt, T_asset
      add_field :extensions, Tm_extension[
        Field[:target_collateral_ratio, T_uint16],
      ]
    end

    # TODO:OP virtual Fill_order

    class T_authority < T_composite
      add_field :weight_threshold, T_uint32
      add_field :account_auths, Tm_map(Tm_protocol_id_type(ObjectType::Account), T_uint16)
      add_field :key_auths, Tm_map(T_public_key, T_uint16)
      add_field :address_auths, Tm_map(T_address, T_uint16)
    end

    class T_account_options < T_composite
      add_field :memo_key, T_public_key
      add_field :voting_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :num_witness, T_uint16
      add_field :num_committee, T_uint16
      add_field :votes, Tm_set(T_vote_id)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_account_create < T_composite
      add_field :fee, T_asset
      add_field :registrar, Tm_protocol_id_type(ObjectType::Account)
      add_field :referrer, Tm_protocol_id_type(ObjectType::Account)
      add_field :referrer_percent, T_uint16
      add_field :name, T_string
      add_field :owner, T_authority
      add_field :active, T_authority
      add_field :options, T_account_options
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_account_update < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :owner, Tm_optional(T_authority)
      add_field :active, Tm_optional(T_authority)
      add_field :new_options, Tm_optional(T_account_options)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_account_whitelist < T_composite
      add_field :fee, T_asset
      add_field :authorizing_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :account_to_list, Tm_protocol_id_type(ObjectType::Account)
      add_field :new_listing, T_uint8

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_account_upgrade < T_composite
      add_field :fee, T_asset
      add_field :account_to_upgrade, Tm_protocol_id_type(ObjectType::Account)
      add_field :upgrade_to_lifetime_member, T_bool
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_account_transfer < T_composite
      add_field :fee, T_asset
      add_field :account_id, Tm_protocol_id_type(ObjectType::Account)
      add_field :new_owner, Tm_protocol_id_type(ObjectType::Account)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class T_asset_options < T_composite
      add_field :max_supply, T_int64
      add_field :market_fee_percent, T_uint16
      add_field :max_market_fee, T_int64
      add_field :issuer_permissions, T_uint16
      add_field :flags, T_uint16
      add_field :core_exchange_rate, T_price
      add_field :whitelist_authorities, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :blacklist_authorities, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :whitelist_markets, Tm_set(Tm_protocol_id_type(ObjectType::Asset))
      add_field :blacklist_markets, Tm_set(Tm_protocol_id_type(ObjectType::Asset))
      add_field :description, T_string
      add_field :extensions, Tm_extension[
        Field[:reward_percent, T_uint16],
        Field[:whitelist_market_fee_sharing, Tm_set(Tm_protocol_id_type(ObjectType::Account))],
      ]
    end

    class T_bitasset_options < T_composite
      add_field :feed_lifetime_sec, T_uint32
      add_field :minimum_feeds, T_uint8
      add_field :force_settlement_delay_sec, T_uint32
      add_field :force_settlement_offset_percent, T_uint16
      add_field :maximum_force_settlement_volume, T_uint16
      add_field :short_backing_asset, Tm_set(Tm_protocol_id_type(ObjectType::Asset))
      add_field :extensions, Tm_extension[
        # BSIP-77
        Field[:initial_collateral_ratio, T_uint16],
        # BSIP-75
        Field[:maintenance_collateral_ratio, T_uint16],
        # BSIP-75
        Field[:maximum_short_squeeze_ratio, T_uint16],
        # BSIP 74
        Field[:margin_call_fee_ratio, T_uint16],
        # BSIP-87
        Field[:force_settle_fee_percent, T_uint16],
        # https://github.com/bitshares/bitshares-core/issues/2467
        Field[:black_swan_response_method, T_uint8],
      ]
    end

    class T_price < T_composite
      add_field :base, T_asset
      add_field :quote, T_asset
    end

    class T_price_feed < T_composite
      add_field :settlement_price, T_price
      add_field :maintenance_collateral_ratio, T_uint16
      add_field :maximum_short_squeeze_ratio, T_uint16
      add_field :core_exchange_rate, T_price
    end

    class OP_asset_create < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :symbol, T_string
      add_field :precision, T_uint8
      add_field :common_options, T_asset_options
      add_field :bitasset_opts, Tm_optional(T_bitasset_options)
      add_field :is_prediction_market, T_bool
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_update < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
      add_field :new_issuer, Tm_optional(Tm_protocol_id_type(ObjectType::Account))
      add_field :new_options, T_asset_options
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_update_bitasset < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
      add_field :new_options, T_bitasset_options
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_update_feed_producers < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
      add_field :new_feed_producers, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_issue < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_to_issue, T_asset
      add_field :issue_to_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :memo, Tm_optional(T_memo_data)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_reserve < T_composite
      add_field :fee, T_asset
      add_field :payer, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount_to_reserve, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_fund_fee_pool < T_composite
      add_field :fee, T_asset
      add_field :from_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
      add_field :amount, T_share_type # only core asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_settle < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_global_settle < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_to_settle, Tm_protocol_id_type(ObjectType::Asset)
      add_field :settle_price, T_price
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_publish_feed < T_composite
      add_field :fee, T_asset
      add_field :publisher, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
      add_field :feed, T_price_feed
      add_field :extensions, Tm_extension[
        Field[:initial_collateral_ratio, T_uint16],
      ]
    end

    class OP_witness_create < T_composite
      add_field :fee, T_asset
      add_field :witness_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :url, T_string
      add_field :block_signing_key, T_public_key
    end

    class OP_witness_update < T_composite
      add_field :fee, T_asset
      add_field :witness, Tm_protocol_id_type(ObjectType::Witness)
      add_field :witness_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :new_url, Tm_optional(T_string)
      add_field :new_signing_key, Tm_optional(T_public_key)
    end

    class T_op_wrapper < T_composite
      add_field :op, T_operation
    end

    class OP_proposal_create < T_composite
      add_field :fee, T_asset
      add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :expiration_time, T_time_point_sec
      add_field :proposed_ops, Tm_array[T_op_wrapper]
      add_field :review_period_seconds, Tm_optional(T_uint32)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_proposal_update < T_composite
      add_field :fee, T_asset
      add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :proposal, Tm_protocol_id_type(ObjectType::Proposal)

      add_field :active_approvals_to_add, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :active_approvals_to_remove, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :owner_approvals_to_add, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :owner_approvals_to_remove, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :key_approvals_to_add, Tm_set(T_public_key)
      add_field :key_approvals_to_remove, Tm_set(T_public_key)

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_proposal_delete < T_composite
      add_field :fee, T_asset
      add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :using_owner_authority, T_bool
      add_field :proposal, Tm_protocol_id_type(ObjectType::Proposal)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_withdraw_permission_create < T_composite
      add_field :fee, T_asset
      add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :authorized_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :withdrawal_limit, T_asset
      add_field :withdrawal_period_sec, T_uint32
      add_field :periods_until_expiration, T_uint32
      add_field :period_start_time, T_time_point_sec
    end

    class OP_withdraw_permission_update < T_composite
      add_field :fee, T_asset
      add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :authorized_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :permission_to_update, Tm_protocol_id_type(ObjectType::Withdraw_permission)
      add_field :withdrawal_limit, T_asset
      add_field :withdrawal_period_sec, T_uint32
      add_field :period_start_time, T_time_point_sec
      add_field :periods_until_expiration, T_uint32
    end

    class OP_withdraw_permission_claim < T_composite
      add_field :fee, T_asset
      add_field :withdraw_permission, Tm_protocol_id_type(ObjectType::Withdraw_permission)
      add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :withdraw_to_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount_to_withdraw, T_asset
      add_field :memo, Tm_optional(T_memo_data)
    end

    class OP_withdraw_permission_delete < T_composite
      add_field :fee, T_asset
      add_field :withdraw_from_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :authorized_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :withdrawal_permission, Tm_protocol_id_type(ObjectType::Withdraw_permission)
    end

    class OP_committee_member_create < T_composite
      add_field :fee, T_asset
      add_field :committee_member_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :url, T_string
    end

    class OP_committee_member_update < T_composite
      add_field :fee, T_asset
      add_field :committee_member, Tm_protocol_id_type(ObjectType::Committee_member)
      add_field :committee_member_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :new_url, Tm_optional(T_string)
    end

    # TODO:OP Committee_member_update_global_parameters = 31

    class T_linear_vesting_policy_initializer < T_composite
      add_field :begin_timestamp, T_time_point_sec
      add_field :vesting_cliff_seconds, T_uint32
      add_field :vesting_duration_seconds, T_uint32
    end

    class T_cdd_vesting_policy_initializer < T_composite
      add_field :start_claim, T_time_point_sec
      add_field :vesting_seconds, T_uint32
    end

    class OP_vesting_balance_create < T_composite
      add_field :fee, T_asset
      add_field :creator, Tm_protocol_id_type(ObjectType::Account)
      add_field :owner, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount, T_asset
      add_field :policy, Tm_static_variant[
        T_linear_vesting_policy_initializer,
        T_cdd_vesting_policy_initializer,
      ]
    end

    class OP_vesting_balance_withdraw < T_composite
      add_field :fee, T_asset
      add_field :vesting_balance, Tm_protocol_id_type(ObjectType::Vesting_balance)
      add_field :owner, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount, T_asset
    end

    class T_vesting_balance_worker_initializer < T_composite
      add_field :pay_vesting_period_days, T_uint16
    end

    class T_burn_worker_initializer < T_composite
    end

    class T_refund_worker_initializer < T_composite
    end

    class OP_worker_create < T_composite
      add_field :fee, T_asset
      add_field :owner, Tm_protocol_id_type(ObjectType::Account)
      add_field :work_begin_date, T_time_point_sec
      add_field :work_end_date, T_time_point_sec
      add_field :daily_pay, T_share_type
      add_field :name, T_string
      add_field :url, T_string

      add_field :initializer, Tm_static_variant[
        T_refund_worker_initializer,
        T_vesting_balance_worker_initializer,
        T_burn_worker_initializer,
      ]
    end

    class OP_custom < T_composite
      add_field :fee, T_asset
      add_field :payer, Tm_protocol_id_type(ObjectType::Account)
      add_field :required_auths, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :id, T_uint16
      add_field :data, Tm_bytes(Nil)
    end

    class T_account_storage_map < T_composite
      add_field :remove, T_bool
      add_field :catalog, T_string
      add_field :key_values, Tm_map(T_string, Tm_optional(T_string))
    end

    class T_custom_plugin_operation < T_composite
      add_field :data, Tm_static_variant[T_account_storage_map]
    end

    class T_assert_predicate_account_name_eq_lit < T_composite
      add_field :account_id, Tm_protocol_id_type(ObjectType::Account)
      add_field :name, T_string
    end

    class T_assert_predicate_asset_symbol_eq_lit < T_composite
      add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
      add_field :symbol, T_string
    end

    class T_assert_predicate_block_id < T_composite
      add_field :id, Tm_bytes(20) # RMD160
    end

    class OP_assert < T_composite
      add_field :fee, T_asset
      add_field :fee_paying_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :predicates, Tm_array[Tm_static_variant[
        T_assert_predicate_account_name_eq_lit,
        T_assert_predicate_asset_symbol_eq_lit,
        T_assert_predicate_block_id,
      ]]
      add_field :required_auths, Tm_set(Tm_protocol_id_type(ObjectType::Account))
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_balance_claim < T_composite
      add_field :fee, T_asset
      add_field :deposit_to_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :balance_to_claim, Tm_protocol_id_type(ObjectType::Balance)
      add_field :balance_owner_key, T_public_key
      add_field :total_claimed, T_asset
    end

    class OP_override_transfer < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :from, Tm_protocol_id_type(ObjectType::Account)
      add_field :to, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount, T_asset
      add_field :memo, Tm_optional(T_memo_data)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class T_stealth_confirmation_memo_data < T_composite
      add_field :from, Tm_optional(T_public_key)
      add_field :amount, T_asset
      add_field :blinding_factor, Tm_bytes(32) # blind_factor_type -> SHA256
      add_field :commitment, Tm_bytes(33)
      add_field :check, T_uint32
    end

    class T_stealth_confirmation < T_composite
      add_field :one_time_key, T_public_key
      add_field :to, Tm_optional(T_public_key)
      add_field :encrypted_memo, Tm_bytes(Nil)
    end

    class T_blind_input < T_composite
      add_field :commitment, Tm_bytes(33)
      add_field :owner, T_authority
    end

    class T_blind_output < T_composite
      add_field :commitment, Tm_bytes(33)
      add_field :range_proof, Tm_bytes(Nil) # only required if there is more than one blind output
      add_field :owner, T_authority
      add_field :stealth_memo, Tm_optional(T_stealth_confirmation)
    end

    class OP_transfer_to_blind < T_composite
      add_field :fee, T_asset
      add_field :amount, T_asset
      add_field :from, Tm_protocol_id_type(ObjectType::Account)
      add_field :blinding_factor, Tm_bytes(32) # blind_factor_type -> SHA256
      add_field :outputs, Tm_array[T_blind_output]
    end

    class OP_blind_transfer < T_composite
      add_field :fee, T_asset
      add_field :inputs, Tm_array[T_blind_input]
      add_field :outputs, Tm_array[T_blind_output]
    end

    class OP_transfer_from_blind < T_composite
      add_field :fee, T_asset
      add_field :amount, T_asset
      add_field :to, Tm_protocol_id_type(ObjectType::Account)
      add_field :blinding_factor, Tm_bytes(32) # blind_factor_type -> SHA256
      add_field :inputs, Tm_array[T_blind_input]
    end

    # TODO:OP virtual Asset_settle_cancel

    class OP_asset_claim_fees < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount_to_claim, T_asset # amount_to_claim.asset_id->issuer must == issuer
      add_field :extensions, Tm_extension[Field[:claim_from_asset_id, Tm_protocol_id_type(ObjectType::Asset)]]
    end

    # TODO:OP virtual Fba_distribute

    class OP_bid_collateral < T_composite
      add_field :fee, T_asset
      add_field :bidder, Tm_protocol_id_type(ObjectType::Account)
      add_field :additional_collateral, T_asset
      add_field :debt_covered, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    # TODO:OP virtual Execute_bid

    class OP_asset_claim_pool < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_id, Tm_protocol_id_type(ObjectType::Asset)
      add_field :amount_to_claim, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_asset_update_issuer < T_composite
      add_field :fee, T_asset
      add_field :issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_to_update, Tm_protocol_id_type(ObjectType::Asset)
      add_field :new_issuer, Tm_optional(Tm_protocol_id_type(ObjectType::Account))
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_htlc_create < T_composite
      add_field :fee, T_asset
      add_field :from, Tm_protocol_id_type(ObjectType::Account)
      add_field :to, Tm_protocol_id_type(ObjectType::Account)
      add_field :amount, T_asset
      add_field :preimage_hash, Tm_static_variant[
        Tm_bytes(20), # RMD160
        Tm_bytes(20), # SHA1 or SHA160
        Tm_bytes(32), # SHA256
      ]
      add_field :preimage_size, T_uint16
      add_field :claim_period_seconds, T_uint32
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_htlc_redeem < T_composite
      add_field :fee, T_asset
      add_field :htlc_id, Tm_protocol_id_type(ObjectType::Htlc)
      add_field :redeemer, Tm_protocol_id_type(ObjectType::Account)
      add_field :preimage, Tm_bytes(Nil)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    # TODO:OP virtual Htlc_redeemed

    class OP_htlc_extend < T_composite
      add_field :fee, T_asset
      add_field :htlc_id, Tm_protocol_id_type(ObjectType::Htlc)
      add_field :update_issuer, Tm_protocol_id_type(ObjectType::Account)
      add_field :seconds_to_add, T_uint32
      add_field :extensions, Tm_set(T_future_extensions)
    end

    # TODO:OP virtual Htlc_refund

    # TODO:OP 3
    # Custom_authority_create                   = 54
    # Custom_authority_update                   = 55
    # Custom_authority_delete                   = 56

    class OP_ticket_create < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :target_type, T_varint32 # see struct unsigned_int
      add_field :amount, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_ticket_update < T_composite
      add_field :fee, T_asset
      add_field :ticket, Tm_protocol_id_type(ObjectType::Ticket)
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :target_type, T_varint32 # see struct unsigned_int
      add_field :amount_for_new_target, Tm_optional(T_asset)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_liquidity_pool_create < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :asset_a, Tm_protocol_id_type(ObjectType::Asset)
      add_field :asset_b, Tm_protocol_id_type(ObjectType::Asset)
      add_field :share_asset, Tm_protocol_id_type(ObjectType::Asset)
      add_field :taker_fee_percent, T_uint16
      add_field :withdrawal_fee_percent, T_uint16
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_liquidity_pool_delete < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_liquidity_pool_deposit < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
      add_field :amount_a, T_asset
      add_field :amount_b, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_liquidity_pool_withdraw < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
      add_field :share_amount, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_liquidity_pool_exchange < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :pool, Tm_protocol_id_type(ObjectType::Liquidity_pool)
      add_field :amount_to_sell, T_asset
      add_field :min_to_receive, T_asset
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_samet_fund_create < T_composite
      add_field :fee, T_asset
      add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)

      add_field :asset_type, Tm_protocol_id_type(ObjectType::Asset)
      add_field :balance, T_int64
      add_field :fee_rate, T_uint32

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_samet_fund_delete < T_composite
      add_field :fee, T_asset
      add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_samet_fund_update < T_composite
      add_field :fee, T_asset
      add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

      add_field :delta_amount, Tm_optional(T_asset)
      add_field :new_fee_rate, Tm_optional(T_uint32)

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_samet_fund_borrow < T_composite
      add_field :fee, T_asset
      add_field :borrower, Tm_protocol_id_type(ObjectType::Account)
      add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

      add_field :borrow_amount, T_asset

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_samet_fund_repay < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :fund_id, Tm_protocol_id_type(ObjectType::Samet_fund)

      add_field :repay_amount, T_asset
      add_field :fund_fee, T_asset

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_credit_offer_create < T_composite
      add_field :fee, T_asset
      add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)

      add_field :asset_type, Tm_protocol_id_type(ObjectType::Asset)
      add_field :balance, T_int64
      add_field :fee_rate, T_uint32

      add_field :max_duration_seconds, T_uint32
      add_field :min_deal_amount, T_int64
      add_field :enabled, T_bool
      add_field :auto_disable_time, T_time_point_sec

      add_field :acceptable_collateral, Tm_map(Tm_protocol_id_type(ObjectType::Asset), T_price)
      add_field :acceptable_borrowers, Tm_map(Tm_protocol_id_type(ObjectType::Account), T_int64)

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_credit_offer_delete < T_composite
      add_field :fee, T_asset
      add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :offer_id, Tm_protocol_id_type(ObjectType::Credit_offer)

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_credit_offer_update < T_composite
      add_field :fee, T_asset
      add_field :owner_account, Tm_protocol_id_type(ObjectType::Account)
      add_field :offer_id, Tm_protocol_id_type(ObjectType::Credit_offer)

      add_field :delta_amount, Tm_optional(T_asset)
      add_field :fee_rate, Tm_optional(T_uint32)
      add_field :max_duration_seconds, Tm_optional(T_uint32)
      add_field :min_deal_amount, Tm_optional(T_int64)
      add_field :enabled, Tm_optional(T_bool)
      add_field :auto_disable_time, Tm_optional(T_time_point_sec)
      add_field :acceptable_collateral, Tm_optional(Tm_map(Tm_protocol_id_type(ObjectType::Asset), T_price))
      add_field :acceptable_borrowers, Tm_optional(Tm_map(Tm_protocol_id_type(ObjectType::Account), T_int64))

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_credit_offer_accept < T_composite
      add_field :fee, T_asset
      add_field :borrower, Tm_protocol_id_type(ObjectType::Account)
      add_field :offer_id, Tm_protocol_id_type(ObjectType::Credit_offer)

      add_field :borrow_amount, T_asset
      add_field :collateral, T_asset
      add_field :max_fee_rate, T_uint32
      add_field :min_duration_seconds, T_uint32

      add_field :extensions, Tm_set(T_future_extensions)
    end

    class OP_credit_deal_repay < T_composite
      add_field :fee, T_asset
      add_field :account, Tm_protocol_id_type(ObjectType::Account)
      add_field :deal_id, Tm_protocol_id_type(ObjectType::Credit_deal)

      add_field :repay_amount, T_asset
      add_field :credit_fee, T_asset

      add_field :extensions, Tm_set(T_future_extensions)
    end

    # TODO:OP virtual Credit_deal_expired

    class T_transaction < T_composite
      add_field :ref_block_num, T_uint16
      add_field :ref_block_prefix, T_uint32
      add_field :expiration, T_time_point_sec
      add_field :operations, Tm_array[T_operation]
      add_field :extensions, Tm_set(T_future_extensions)
    end

    class T_signed_transaction < T_transaction
      add_field :signatures, Tm_array[Tm_bytes(65)]
    end

    # => 把所有的 operations 的序列化对象和 opcode 关联。
    Opcode2optype = Hash(Int8, FieldType).new
    {% for optype_klass in @type.constants %}
      {% if optype_klass.id =~ /^OP_/ %}
        %enum_field = Blockchain::Operations.parse?("{{ optype_klass.downcase }}".gsub(/op_/, "").capitalize)
        Opcode2optype[%enum_field.value] = {{ optype_klass.id }} if %enum_field
      {% end %}
    {% end %}
  end
end

# test_value = 165545333
# BitShares::Varint.encode(test_value) { |v| p! v }
# p! IO::Memory.new.tap { |io| BitShares::Varint.encode(test_value, io) }.to_slice
# result = BitShares::Varint.encode(test_value)
# p! BitShares::Varint.decode(result) == test_value
# exit
