local DBP = {}


--yes, we do need these locals, because this is a *debugging* module and we don't want the debug library to be messed with by overriden globals
local assert, type, string_gmatch, coroutine_running, debug_sethook, debug_gethook
    = assert, type, string.gmatch, coroutine.running, debug.sethook, debug.gethook


local instructionCounter = 1


--option constants.
--let's bitwise OR like it's C 99
local mask_c = 1
local mask_r = 2
local mask_l = 4


--i hate single use metatables :P (and so does memory)
local threads = { __mode = 'k' }
setmetatable( threads, threads )


---Pushes a new hook onto the hook stack of a thread.
--Its signature is not the same as debug.sethook!
function DBP.pushHook( hook, mask, count, thread )
	thread = thread or coroutine_running()
	count = count or 0
	assert( type( thread ) == 'thread', "thread must be a thread" )
	assert( type( hook ) == 'function', "hook must be a function" )
	assert( type( mask ) == 'string', "mask must be a string" )
	assert( type( count ) == 'number', "count must be a number" )
	
	local c, r, l = 0, 0, 0
	for char in string_gmatch( mask, '.' ) do
		if char == 'c' then c = mask_c
		elseif char == 'r' then r = mask_r
		elseif char == 'l' then l = mask_l
		end
	end
	mask = c + r + l --classic C style binary ORing, because that's so h4x0r
	--plus i want this thing to be fast and low on memory
	
	local struct = threads[ thread ]
	if not struct then
		struct = {
			i = 1,
			hook = {},
			mask = {},
			count = {},
		}
		threads[ thread ] = struct
	end
	local struct_i, struct_hook, struct_mask, struct_count
	    = struct.i, struct.hook, struct.mask, struct.count
	struct_hook[ struct_i ] = hook
	struct_mask[ struct_i ] = mask
	struct_count[ struct_i ] = count
	struct.i = struct_i + 1
end


function DBP.popHook( thread )
	thread = thread or coroutine_running()
	if not thread then thread = coroutine_running() end
	local struct = threads[ threads ]
	if struct then
		local struct_i = struct.i - 1
		struct.hook[ struct_i ] = nil
		struct.mask[ struct_i ] = nil
		struct.count[ struct_i ] = nil
		struct.i = struct_i
	end
end


---The hook that runs all registered hooks.
function DBP.superHook( event, lineno )
	--idk how Lua handles count events, but the documentation does not define it, so i'll assume it's Undefined Behaviour
	instructionCounter = instructionCounter + 1
	local struct = threads[ coroutine_running() ]
	if struct then
		--i'm too tired to explain why subtraction works here
		--just trust me it's the same as if we checked whether
		--the right side of the equality check was in the set
		for i = 1, struct.i - 1 do
			local struct_mask = struct.mask[ i ]
			if (event == 'call' or event == 'tail call') and
				struct_mask - mask_r - mask_l == mask_c then
				struct.hook[ i ]( event, lineno )
			elseif event == 'return' and
				struct_mask - mask_c - mask_l == mask_r then
				struct.hook[ i ]( event, lineno )
			elseif event == 'line' and
				struct_mask - mask_c - mask_r == mask_l then
				struct.hook[ i ]( event, lineno )
			elseif event == 'count' and
				struct.count[ i ] ~= 0 and
				instructionCounter % struct.count[ i ] == 0 then
					struct.hook[ i ]( event, lineno )
			--else error"what are you trying to accomplish?"
			end
		end
	end
end


function DBP.register( thread )
	thread = thread or coroutine_running()
	debug_sethook( thread, DBP.superHook, 'crl', 1 )
end


---Append to current debugging session.
function DBP.append( thread )
	thread = thread or coroutine_running()
	local h, m, c = debug_gethook( thread )
	if h then
		DBP.pushHook( h, m, c )
	end
	DBP.register( thread )
end


--for statistics and such
function DBP.getIC() return instructionCounter end
--if the IC gets too huge
function DBP.resetIC() instructionCounter = 1 end


return DBP