class Exception
  # 获取异常详细信息。
  # 例：
  # ```
  # 215 line of script 'any.cr' has occurred Exception.

  # test error...

  # Stack:
  # /usr/local/Cellar/crystal/1.2.0/src/json/any.cr:215:3 in 'main'
  # lib/game/task.cr:49:11 in 'run'
  # lib/game/task.cr:23:24 in '->'
  # /usr/local/Cellar/crystal/1.2.0/src/primitives.cr:266:3 in 'run'
  # ```
  def detail_message
    back = self.backtrace? || [] of String

    matchstr = back.first.to_s
    if matchstr =~ /(.*):([0-9]+):/
      file, line = $1.to_s, $2.to_i
      file = File.basename(file)
    else
      file = "unknown"
      line = 0
    end

    return "#{line} line of script '#{file}' has occurred #{self.class.name}. \n\n#{self.message}\n\nStack:\n#{back.join("\n")}\n"
  end
end
