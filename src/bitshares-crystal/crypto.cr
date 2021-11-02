module BitShares
  module Crypto
    class Aes256
      @key : Bytes
      @iv : Bytes
      @cipher : OpenSSL::Cipher?

      def initialize(key : Bytes, iv : Bytes, padding = false, name = "aes-256-cbc")
        @name = name
        @key = key[0, 32]
        @iv = iv[0, 16]
        @padding = padding
        @cipher = nil
      end

      def decrypt(data)
        if @cipher.nil?
          @cipher = OpenSSL::Cipher.new(@name).tap do |c|
            c.decrypt
            c.key = @key
            c.iv = @iv
            c.padding = @padding
          end
        end
        if @padding
          return @cipher.not_nil!.update(data) + @cipher.not_nil!.final
        else
          return @cipher.not_nil!.update(data)
        end
      end

      def encrypt(data)
        if @cipher.nil?
          @cipher = OpenSSL::Cipher.new(@name).tap do |c|
            c.encrypt
            c.key = @key
            c.iv = @iv
            c.padding = @padding
          end
        end
        if @padding
          return @cipher.not_nil!.update(data) + @cipher.not_nil!.final
        else
          return @cipher.not_nil!.update(data)
        end
      end

      # => 根据 seed 构造 Aes 对象
      def self.fromSeed(seed)
        return self.fromSha512(BitShares::Utility.sha512_hex(seed))
      end

      # => 根据摘要构造 Aes 对象
      # => hash512hex - SHA512的16进制摘要（128字节）
      def self.fromSha512(hash512hex)
        key = BitShares::Utility.hex_decode(hash512hex[0, 64])
        iv = BitShares::Utility.hex_decode(hash512hex[64, 32])
        return Aes256.new(key, iv, true)
      end
    end

    extend self

    # 获取 u64 类型随机数
    def nonce_u64 : UInt64
      byte8 = Bytes.new(8)
      Random::Secure.random_bytes(byte8)
      # => 1..0xffffffffffffffff
      return (byte8.to_unsafe.as(UInt64*).value % 0xffffffffffffffff) + 1
    end

    # 辅助生成转账备注对象。
    def gen_memo_object(memo, from_private_key, to_public_key, public_key_prefix, custom_nonce = nil)
      nonce = custom_nonce || nonce_u64
      secret = from_private_key.shared_secret(to_public_key)
      nonce_plus_secret = nonce.to_s + BitShares::Utility.hex_encode(secret)
      aes = Crypto::Aes256.fromSeed(nonce_plus_secret)
      return {
        :from    => from_private_key.to_public_key.to_wif(public_key_prefix),
        :to      => to_public_key.to_wif(public_key_prefix),
        :nonce   => nonce,
        :message => aes.encrypt(BitShares::Utility.sha256(memo)[0, 4] + memo.to_slice),
      }
    end
  end
end
