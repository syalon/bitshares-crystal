def assert(cond)
  raise "assert failed." unless cond
end

def assert(cond, &blk : -> String)
  raise blk.call unless cond
end

require "./bitshares-crystal/**"
