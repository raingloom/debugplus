--yes, we do need these locals, because this is a *debugging* module and we don't want the debug library to be messed with by overriden globals
local assert, type, string_gmatch, coroutine_running
    = assert, type, string.gmatch, coroutine.running

--option constants.
--bitwise OR like it's C 99
local mask_c = 1
local mask_r = 2
local mask_l = 4


--i hate single use metatables :P (and so does memory)
local threads = { __mode = 'k' } setmetatable( threads, threads )



local function pushHook( thread, hook, mask, count )
	--check if type is what we expect
	--if it isn't, shift the arguments and assign the default
	--this way the hook stack will also have full information and not have nil holes
	if type( thread ) ~= 'thread' then
		hook = coroutine_running()
		hook, mask, count = thread, hook, mask
	end
	assert( type( hook ) ~= 'function', "hook must be a function" )
	assert( type( mask ) ~= 'string', "mask must be a string" )
	count = count or 0
	
	local c, r, l
	for char in string_gmatch( mask, '.' ) do
		if char == 'c' then c = true
		elseif char == 'r' then r = true
		elseif char == 'l' then l = true
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
	end
	local struct_i, struct_hook, struct_mask, struct_count
	= struct.i + 1, struct.hook, struct.mask, struct.count
	struct_hook[ struct_i ] = hook
	struct_mask[ struct_i ] = mask
	struct_count[ struct_i ] = count
	struct.i = struct_i
end


local function popHook( thread )
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


local instructionCounter = 0
local function superHook( event, lineno )
	--idk how Lua handles count events, but the documentation does not define it, so i'll assume it's Undefined Behaviour
	instructionCounter = instructionCounter + 1
	local struct = threads[ coroutine_running() ]
	if struct then
		local struct_mask = struct.mask
		--i'm too tired to explain why subtraction works here
		--just trust me it's the same as if we checked whether
		--the right side of the equality check was in the set
		for i = 1, struct.i do
			if (event == 'call' or event == 'tail call') and
				struct_mask - mask_r - mask_l == mask_c then
				struct.hook( event, lineno )
			elseif event == 'return' and
				struct_mask - mask_c - mask_l == mask_r then
				struct.hook( event, lineno )
			elseif event == 'line' and
				struct_mask - mask_c - mask_r == mask_l then
				struct.hook( event, lineno )
			elseif event == 'count' then
				if instructionCounter % struct.count == 0 then
					struct.hook( event, lineno )
				end
			--else error"what are you trying to accomplish?"
			end
		end
	end
end


return {
	pushHook = pushHook,
	popHook = popHook
}
