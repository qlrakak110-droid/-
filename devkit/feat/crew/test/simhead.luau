-- virtual-time scheduler for the crew brain tests: task.wait yields, os.clock / server time are virtual
SIM = { t = 0, sleeping = {}, errors = 0 }
local SIMT = SIM
local realOs = os
os = setmetatable({ clock = function() return SIMT.t end, time = function() return 1792200000 + math.floor(SIMT.t) end }, { __index = realOs })
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		SIMT.errors += 1
		print("[SIM ERROR] " .. tostring(err) .. "\n" .. debug.traceback(co))
	end
end
task = {
	wait = function(t)
		local co = coroutine.running()
		table.insert(SIMT.sleeping, { co = co, t = SIMT.t + (t or 0.03) })
		coroutine.yield()
		return t or 0.03
	end,
	spawn = function(f, ...)
		local co = if type(f) == "thread" then f else coroutine.create(f)
		resume(co, ...)
		return co
	end,
	delay = function(t, f, ...)
		local args = table.pack(...)
		table.insert(SIMT.sleeping, { fn = f, args = args, t = SIMT.t + (t or 0) })
	end,
	defer = function(f, ...)
		local args = table.pack(...)
		table.insert(SIMT.sleeping, { fn = f, args = args, t = SIMT.t })
	end,
	cancel = function() end,
}
function SIM.step(dt)
	SIMT.t += dt
	local due = {}
	for i = #SIMT.sleeping, 1, -1 do
		if SIMT.sleeping[i].t <= SIMT.t then
			table.insert(due, table.remove(SIMT.sleeping, i))
		end
	end
	table.sort(due, function(a, b) return a.t < b.t end)
	for _, d in due do
		if d.co then
			resume(d.co)
		else
			resume(coroutine.create(d.fn), table.unpack(d.args, 1, d.args.n))
		end
	end
end
workspace.GetServerTimeNow = function() return SIMT.t end
SIM.task = task
