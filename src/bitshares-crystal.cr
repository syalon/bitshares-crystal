def assert(cond)
  raise "assert failed." unless cond
end

def assert(cond, &blk)
  raise blk.call unless cond
end

require "./bitshares-crystal/**"
