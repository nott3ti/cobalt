local function CreateLookupTable(table)
	local LookupTable = {}
	for _, Method in next, table do
		LookupTable[Method] = true
	end
	return LookupTable
end

local NamecallMethods = CreateLookupTable({
	"FireServer",
	"InvokeServer",
	"Fire",
	"Invoke",
	"fireServer",
	"invokeServer",
	"fire",
	"invoke",
})
local AllowedClassNames = CreateLookupTable({ "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BindableEvent", "BindableFunction" })

--[[
	Returns the calling function via `debug.info`

	@return `function | nil` The calling function or nil if not found.
]]
local function getcallingfunction()
	local BaseLevel = if wax.shared.ExecutorSupport["oth"].IsWorking then 2 else 4

	for i = BaseLevel, 10 do
		local Function, Source = debug.info(i, "fs")
		if not Function or not Source then
			break
		end

		if Source == "[C]" then
			continue
		end

		return Function
	end

	return debug.info(BaseLevel, "f")
end

--[[
	Returns the calling line of the script that called the function via `debug.info`

	@return number Returns the line number of the calling script.
]]
local function getcallingline()
	local BaseLevel = if wax.shared.ExecutorSupport["oth"].IsWorking then 2 else 4

	for i = BaseLevel, 10 do
		local Source, Line = debug.info(i, "sl")
		if not Source then
			break
		end

		if Source == "[C]" then
			continue
		end

		return Line
	end

	return debug.info(BaseLevel, "l")
end

--[[
	Returns the calling source of the script that called the function via `debug.info`

	@return string Returns the source of the calling script.
]]
local function getcallingsource()
	local BaseLevel = if wax.shared.ExecutorSupport["oth"].IsWorking then 2 else 4

	for i = BaseLevel, 10 do
		local Source = debug.info(i, "s")
		if not Source then
			break
		end

		if Source == "[C]" then
			continue
		end

		return Source
	end

	return debug.info(BaseLevel, "s")
end

-- metamethod hooks
wax.shared.NamecallHook = wax.shared.Hooking.HookMetaMethod(game, "__namecall", function(...)
	local self = ...
	local Method = getnamecallmethod()

	if
		wax.shared.RemoteSpyEnabled
		and typeof(self) == "Instance"
		and AllowedClassNames[self.ClassName]
		and not rawequal(self, wax.shared.Communicator)
		and not rawequal(self, wax.shared.ActorCommunicator)
		and NamecallMethods[Method]
	then
		-- Drop known high-frequency sync payloads before any expensive work.
		if wax.shared.ShouldSkipRemoteArgs(select(2, ...)) then
			return wax.shared.NamecallHook(...)
		end

		local Log = wax.shared.Logs.Outgoing[self]
		if not Log then
			Log = wax.shared.NewLog(self, "Outgoing", Method, nil)
		end

		if Log.Blocked then
			return
		elseif not Log.Ignored then
			-- Cheap spam gate before debug.info / DeepClone / UI notify.
			if Log:IsOverSpamThreshold() then
				return wax.shared.NamecallHook(...)
			end

			local Origin = getcallingscript()
			if wax.shared.ShouldIgnore(self, Origin) then
				return wax.shared.NamecallHook(...)
			end

			local Info = {
				Arguments = table.pack(select(2, ...)),
				Origin = Origin,
				Function = getcallingfunction(),
				Line = getcallingline(),
				Source = getcallingsource(),
				IsExecutor = checkcaller(),
				SpamChecked = true,
			}
			Log:Call(Info)
			-- For RemoteFunction return value (ex: local result = RemoteFunction:InvokeServer())
			if self.ClassName == "RemoteFunction" and (Method == "InvokeServer" or Method == "invokeServer") then
				Log = wax.shared.Logs.Incoming[self]
				if not Log then
					Log = wax.shared.NewLog(self, "Incoming", Method, Origin)
				end

				if Log.Blocked then
					return
				end

				local Result = table.pack(wax.shared.NamecallHook(...))
				if not Log.Ignored and not Log:IsOverSpamThreshold() then
					local RFResultInfo = {
						Arguments = Result,
						Origin = Origin,
						Function = getcallingfunction(),
						Line = getcallingline(),
						Source = getcallingsource(),
						IsExecutor = checkcaller(),
						OriginalInvokeArgs = table.pack(select(2, ...)),
						SpamChecked = true,
					}
					Log:Call(RFResultInfo)
				end

				return table.unpack(Result, 1, Result.n)
			end
		end
	end

	return wax.shared.NamecallHook(...)
end)

-- function hooks
local FunctionsToHook
do
	local BindableFunction = Instance.new("BindableFunction")
	local BindableEvent = Instance.new("BindableEvent")

	local RemoteFunction = Instance.new("RemoteFunction")
	local RemoteEvent = Instance.new("RemoteEvent")
	local UnreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")

	FunctionsToHook = {
		BindableFunction.Invoke,
		BindableEvent.Fire,

		RemoteFunction.InvokeServer,
		RemoteEvent.FireServer,
		UnreliableRemoteEvent.FireServer,
	}

	BindableFunction:Destroy()
	BindableEvent:Destroy()

	RemoteFunction:Destroy()
	RemoteEvent:Destroy()
	UnreliableRemoteEvent:Destroy()
end

for _, Function in next, FunctionsToHook do
	local Method = debug.info(Function, "n")

	wax.shared.Hooks[Function] = wax.shared.Hooking.HookFunction(Function, function(...)
		local self = ...

		if
			wax.shared.RemoteSpyEnabled
			and typeof(self) == "Instance"
			and AllowedClassNames[self.ClassName]
			and not rawequal(self, wax.shared.Communicator)
		then
			if wax.shared.ShouldSkipRemoteArgs(select(2, ...)) then
				return wax.shared.Hooks[Function](...)
			end

			local Log = wax.shared.Logs.Outgoing[self]
			if not Log then
				Log = wax.shared.NewLog(self, "Outgoing", Method, nil)
			end

			if Log.Blocked then
				return
			elseif not Log.Ignored then
				if Log:IsOverSpamThreshold() then
					return wax.shared.Hooks[Function](...)
				end

				local Origin = getcallingscript()
				if wax.shared.ShouldIgnore(self, Origin) then
					return wax.shared.Hooks[Function](...)
				end

				local Info = {
					Arguments = table.pack(select(2, ...)),
					Origin = Origin,
					Function = getcallingfunction(),
					Line = getcallingline(),
					Source = getcallingsource(),
					IsExecutor = checkcaller(),
					SpamChecked = true,
				}
				Log:Call(Info)
				-- For RemoteFunction return value (ex: local result = RemoteFunction:InvokeServer())
				if self.ClassName == "RemoteFunction" and (Method == "InvokeServer" or Method == "invokeServer") then
					Log = wax.shared.Logs.Incoming[self]
					if not Log then
						Log = wax.shared.NewLog(self, "Incoming", Method, Origin)
					end

					if Log.Blocked then
						return
					end

					local Result = table.pack(wax.shared.Hooks[Function](...))
					if not Log.Ignored and not Log:IsOverSpamThreshold() then
						local RFResultInfo = {
							Arguments = Result,
							Origin = Origin,
							Function = getcallingfunction(),
							Line = getcallingline(),
							Source = getcallingsource(),
							IsExecutor = checkcaller(),
							OriginalInvokeArgs = table.pack(select(2, ...)),
							SpamChecked = true,
						}
						Log:Call(RFResultInfo)
					end

					return table.unpack(Result, 1, Result.n)
				end
			end
		end

		return wax.shared.Hooks[Function](...)
	end)
end
