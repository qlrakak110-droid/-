local ok, e = pcall(function() os.clock = function() return 42 end end)
print(ok, e, os.clock())
