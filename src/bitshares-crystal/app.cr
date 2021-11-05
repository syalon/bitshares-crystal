require "./task"

module BitShares
  class App
    Log = ::Log.for("app")

    def self.instance
      @@__instance ||= new
      @@__instance.not_nil!
    end

    # --------------------------------------------------------------------------
    # ● (public) 以带块的方式启动APP。
    # --------------------------------------------------------------------------
    def self.start
      instance.mainloop { |app| with itself yield app }
    end

    # --------------------------------------------------------------------------
    # ● (public) 直接启动APP，并自动启动单个异步任务。REMARK：不支持启动多个异步任务，如需启动多个请使用 start 方法。
    # --------------------------------------------------------------------------
    def self.run_task(task_class : Task? = nil, config : Config? = nil, &blk : Task -> _)
      start { itself.run_task(config, &blk) }
    end

    def self.run_task(task_class : Class, config : Config? = nil)
      start { itself.run_task(task_class, config) }
    end

    getter task_list : Array(Task)

    # attr_reader   :task_list
    # attr_reader   :log

    def initialize
      # @last_tick_time = nil
      @task_list = [] of Task
      # @log = Logger.new(STDOUT)
    end

    # --------------------------------------------------------------------------
    # ● (public) 查找指定类型的 task 对象。
    # --------------------------------------------------------------------------
    def find_task(task_class : T.class) : Task? forall T
      return @task_list.find { |task| task.is_a?(T) }
    end

    # --------------------------------------------------------------------------
    # ● (public) 启动异步任务。可通过 Task 启动或者传递块启动。
    # => config - 通过该命名参数可指定配置信息。
    # --------------------------------------------------------------------------
    def run_task(config : Config? = nil, &blk : Task -> _)
      BlockWrapperTask.new(config) { |task| blk.call(task) }.tap { |t| @task_list << t }.start
    end

    def run_task(task_class : Task.class, config : Config? = nil)
      task_class.new(config).tap { |t| @task_list << t }.start
    end

    private def on_stop
      # => TODO:
    end

    private def on_error(e)
      # => TODO:
      raise e
    end

    private def tick_per_day
      @task_list.each { |t| t.tick_per_day }
    end

    private def tick_per_minute
      # TODO:ing
      # @task_list.each{|t| t.tick_per_minute}
      # @last_tick_time = Time.now.tap{|t| tick_per_day if @last_tick_time && @last_tick_time.day != t.day}
    end

    protected def mainloop
      # => 执行初始化逻辑
      with self yield self

      # => 主循环
      timespan = Time::Span.new(nanoseconds: 1000_000)
      loop do
        # => 检测任务是否结束，所有任务结束之后退出程序。
        @task_list.dup.each { |t| @task_list.delete(t) if t.finished? }
        break if @task_list.empty?
        # => 休眠
        sleep(timespan)
        # => TODO:处理一些每分 每小时 每日事件
        tick_per_minute
      end
    end
  end
end
