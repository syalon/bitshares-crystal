require "crystal-secp256k1-zkp"

module BitShares
  module Utility
    extend Secp256k1Zkp::Utility
    extend self

    # 解析石墨烯API返回的日期字符串
    def parse_time_string(time_string : String)
      time_string += "Z" unless time_string =~ /.*Z$/
      # format: 2021-10-26T09:16:06Z
      return Time.parse(time_string, "%Y-%m-%dT%H:%M:%S", Time::Location::UTC)
    end

    # :ditto:
    def parse_time_string_i64(time_string : String)
      parse_time_string(time_string).to_unix
    end

    # 获取当前时间戳
    def now_ts
      Time.utc.to_unix
    end

    # 延迟执行代码
    def delay(seconds : Int | Time::Span, &blk)
      timeout = if seconds.is_a?(Int)
                  Time::Span.new(seconds: seconds)
                else
                  seconds.as(Time::Span)
                end
      spawn do
        sleep(timeout)
        blk.call
      end
    end

    # 迭代 json 或者 hash 对象中的所有 oid 字符串。
    def iterate_oid_string(obj)
      return Hash(String, Int8).new.tap { |result| iterate_string(obj) { |value| result[value] = $1.to_i8 if value =~ /^\d+\.(\d+)\.\d+$/i } }
    end

    private def iterate_string(obj, &blk : String -> _)
      case obj
      when Array, Tuple
        obj.each { |v| iterate_string(v, &blk) }
      when Hash
        obj.each { |k, v|
          iterate_string(k, &blk)
          iterate_string(v, &blk)
        }
      when NamedTuple
        obj.each { |k, v|
          iterate_string(k.to_s, &blk)
          iterate_string(v, &blk)
        }
      when String
        yield obj
      when JSON::Any
        iterate_string(obj.raw, &blk)
      end
    end

    # 遍历目录树
    def scan_dir(rootdir, &blk : String, String -> _)
      scan_dir_core(rootdir, "", blk)
    end

    private def scan_dir_core(rootdir, relativedir, blk)
      fulldirname = File.join(rootdir, relativedir)
      Dir.each_child(fulldirname) do |s|
        next if s == "." || s == ".."
        next if File.symlink?(fulldirname + s)
        if File.directory?(fulldirname + s)
          scan_dir_core(rootdir, relativedir + s + "/", blk)
        else
          blk.call(relativedir, s)
        end
      end
    end

    # 遍历目录下所有文件，支持正则匹配。返回文件相对路径列表。
    def scan_all_files(rootdir, suffix_filter : Regex)
      files = [] of String
      scan_dir(rootdir) do |relativedir, s|
        next unless s =~ suffix_filter
        next if s =~ /^\._/i # => skip macos cache file
        files << relativedir + s
      end
      return files
    end
  end
end
