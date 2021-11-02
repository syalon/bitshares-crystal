require "log"

module BitShares
  # 在纤程模式下运行的任务的抽象基类。
  abstract class Task
    Log = ::Log.for("task")

    getter fiber : Fiber?

    # 任务是否运行结束判断
    def finished?
      return @fiber.try(&.dead?)
    end

    # 获取 `client` 对象。
    def client : Client
      @client ||= Client.new(@config)
    end

    def initialize(config_object : BitShares::Config? = nil)
      @config = config_object
      @client = nil
      @fiber = spawn { run }
    end

    def start
      Fiber.yield
    end

    def stop
    end

    # 异步任务主方法。子类应该重新实现该方法。
    abstract def main

    # 事件 - 每分钟调用。
    def tick_per_minute
      # => ...
    end

    # 事件 - 每天调用。
    def tick_per_day
      # => ...
    end

    def run
      loop do
        begin
          main
          break
        rescue e : Exception
          on_exception(e)
        end
        sleep(3)
      end
    end

    # def on_system_exit
    #   puts "[system] exit."
    # end

    def on_exception(e)
      # TODO:e.detail_message
      Log.error(exception: e) { e.message }
      # # => TODO:
      # puts "catch on_exception on task"
      # pp e
      raise e
      # err = e.detail_message
      # puts '-' * 72
      # print err
      # puts '-' * 72
      # return err
    end
  end

  class BlockWrapperTask < Task
    @blk : Proc(Task, Nil)

    def initialize(config_object : BitShares::Config? = nil, &@blk : Proc(Task, Nil))
      super(config_object)
    end

    def main
      @blk.call(self)
    end
  end
end
