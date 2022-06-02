require "log"

class FileBackend < Log::IOBackend
  def initialize(file_name : String, mode : String = "a", *, formatter : Log::Formatter = Log::ShortFormat)
    super File.new(file_name, mode), formatter: formatter
  end

  def initialize(file : File, *, formatter : Log::Formatter = Log::ShortFormat)
    super file, formatter: formatter
  end

  def close
    @io.close
    super
  end
end
