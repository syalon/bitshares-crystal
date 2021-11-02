# TODO:未完成
require "crystal-secp256k1-zkp"

module BitShares
  # 内存钱包对象，用于管理各种私钥匙。
  class Wallet
    # :nodoc:
    getter client : Client

    def initialize(client)
      @client = client
      @private_keys_hash = Hash(String, Secp256k1Zkp::PrivateKey).new
    end

    # 清空钱包内存中保存的所有私钥。
    def clear
      @private_keys_hash.clear
    end

    # 根据公钥 WIF 格式字符串获取对应的私钥信息，不存在则返回 `nil`。
    def get_private_key?(public_key : String) : Secp256k1Zkp::PrivateKey?
      @private_keys_hash[public_key]?
    end

    # 是否存在指定公钥的私钥对象。
    def have_private_key?(pubkey)
      @private_keys_hash.has_key?(pubkey)
    end

    # 导入 WIF 格式的私钥到钱包文件中。
    def import_key(private_wif)
      import_key_core(Secp256k1Zkp::PrivateKey.from_wif(private_wif))
    end

    # 通过账号密码导入私钥。
    def import_password(account, password, role = "active")
      import_key_core(Secp256k1Zkp::PrivateKey.from_account_and_password(account, password, role))
    end

    # 根据手续费支付账号获取本地钱包中需要参与签名的公钥列表。
    def get_sign_keys_from_fee_paying_account(fee_paying_account, require_owner_permission = false)
      return get_sign_keys(fee_paying_account[require_owner_permission ? "owner" : "active"])
    end

    # 获取钱包中需要参与签名的公钥列表。
    def get_sign_keys(raw_permission_json)
      result = {} of String => Secp256k1Zkp::PrivateKey

      weight_threshold = raw_permission_json["weight_threshold"].as_i
      curr_weights = 0
      key_auths = raw_permission_json["key_auths"].as_a

      if key_auths && key_auths.size > 0
        key_auths.each do |value|
          pair = value.as_a
          pubkey = pair[0].as_s
          weight = pair[1].as_i
          private_key = @private_keys_hash[pubkey]?
          if private_key
            result[pubkey] = private_key
            curr_weights += weight
            break if curr_weights >= weight_threshold
          end
        end
      end

      return result
    end

    # 签名。如果未指定签名私钥，则使用钱包中默认私钥。
    def sign(sign_message_digest : Bytes, sign_keys_hash : Hash(String, Secp256k1Zkp::PrivateKey)? = nil) : Array(Bytes)
      result = [] of Bytes

      sign_context = Secp256k1Zkp::Context.default

      sign_keys_hash = @private_keys_hash if sign_keys_hash.nil? || sign_keys_hash.empty?
      sign_keys_hash.each do |pubkey, private_key|
        signature = sign_context.sign_compact(sign_message_digest, private_key) rescue nil
        raise "Sign failed" if signature.nil?
        result << signature
      end

      return result
    end

    private def import_key_core(private_key : Secp256k1Zkp::PrivateKey)
      @private_keys_hash[private_key.to_public_key.to_wif(@client.graphene_address_prefix)] = private_key
    end
  end
end
