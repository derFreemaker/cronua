local debug_sethook = debug.sethook
local debug_gethook = debug.gethook

-- c -> "call", "tail call"
-- r -> "return"
-- l -> "line"
-- <count> -> "count"

---@alias Hook.Event
---| "call" # mask: "c"
---| "tail call" # mask: "c"
---| "return" # mask: "r"
---| "line" # mask: "l"
---| "count" # when count provided

---@enum Hook.Mask
local HookMask = {
    none = "",
    call = "c",    -- call hook - triggered when Lua calls a function
    _return = "r", -- return hook - triggered when Lua returns from a function
    line = "l",    -- line hook - triggered when Lua starts executing a new line
}

---@alias Hook.Mask.Combined
---| "" # no hook mask
---| "c" # call hook - triggered when Lua calls a function
---| "r" # return hook - triggered when Lua returns from a function
---| "l" # line hook - triggered when Lua starts executing a new line
---| "cr" # call and return hooks
---| "cl" # call and line hooks
---| "rl" # return and line hooks
---| "crl" # call, return and line hooks

---@type { [Hook.Event]: Hook.Mask }
local event_to_mask_map = {
    ["call"] = "c",
    ["tail call"] = "c",
    ["return"] = "r",
    ["line"] = "l",
    ["count"] = "",
}

---@alias Hook.Func fun(event: Hook.Event, new_line: integer?, debug_ptr: lightuserdata) : nil

---@class Hook
---@field name string
---
---@field func Hook.Func
---@field mask Hook.Mask.Combined
---@field count integer?
---
---@field got_count integer
---@field hook_call boolean?
---@field hook_return boolean?
---@field hook_line boolean?

---@class HookManager
---@field thread thread
---@field hook_slot Hook?
---
---@field map { [Hook.Mask]: { [string]: Hook } }
---@field count_hooks { [string]: Hook }
---
---@field mask Hook.Mask.Combined
---@field count integer?
local HookManager = {}

---@type { [thread]: HookManager? }
local _managers = {}

---@diagnostic disable-next-line: duplicate-set-field
function debug.sethook(thread_or_hook, hook_or_mask, mask_or_count, count_or_name, name_or_none)
    local thread, hook, mask, count, name

    if type(thread_or_hook) == "thread" then
        thread = thread_or_hook
        hook = hook_or_mask
        mask = mask_or_count
        count = count_or_name
        name = name_or_none
    else
        thread = coroutine.running()
        hook = thread_or_hook
        mask = hook_or_mask
        count = mask_or_count
        name = name_or_none
    end

    ---@cast thread thread
    ---@cast hook fun(...) : nil
    ---@cast mask Hook.Mask.Combined
    ---@cast count integer?
    ---@cast name string?

    local hook_manager = _managers[thread]
    if not hook_manager then
        return debug_sethook(thread, hook, mask, count)
    end
    ---@cast hook_manager -nil

    if not hook then
        hook_manager:unregiester(name)
        return
    end

    return hook_manager:register(hook, mask, count, name)
end

---@diagnostic disable-next-line: duplicate-set-field
function debug.gethook(thread)
    thread = thread or coroutine.running()

    local hook_manager = _managers[thread]
    if not hook_manager then
        return debug_gethook(thread)
    end
    ---@cast hook_manager -nil

    local hook = hook_manager.hook_slot
    if not hook then
        return nil
    end

    return hook.func, hook.mask, hook.count
end

---@param thread thread?
---@return HookManager
function HookManager.new(thread)
    ---@type HookManager
    local instance = {
        thread = thread or coroutine.running(),
        mask = "",

        map = {
            ["c"] = {},
            ["r"] = {},
            ["l"] = {},
        },
        count_hooks = {},
    }
    instance.map[""] = instance.count_hooks
    instance = setmetatable(instance, { __index = HookManager })

    _managers[instance.thread] = instance

    local hook, mask, count = debug_gethook(instance.thread)
    if hook then
        ---@cast mask -nil
        ---@cast count -nil

        instance:register(hook, mask, count)
    end

    instance:update_main_hook_all()

    return instance
end

function HookManager:close()
    local hook = self.hook_slot
    if hook then
        debug_sethook(hook.func, hook.mask, hook.count)
    end

    _managers[self.thread] = nil
end

---@param event Hook.Event
---@param new_line integer?
---@param debug_ptr lightuserdata
function HookManager:execute(event, new_line, debug_ptr)
    local mask = event_to_mask_map[event]

    if mask == HookMask.none then
        for _, hook in pairs(self.map[mask]) do
            hook.got_count = hook.got_count + self.count
            if hook.got_count >= hook.count then
                hook.got_count = 0
                hook.func(event, new_line, debug_ptr)
            end
        end

        self:update_main_hook_count()
        self:update_main_hook()
    end

    for _, hook in pairs(self.map[mask]) do
        hook.func(event, new_line, debug_ptr)
    end
end

---@param hook Hook.Func
---@param mask Hook.Mask.Combined
---@param count integer?
---@param name string?
---@return Hook
function HookManager:register(hook, mask, count, name)
    ---@type Hook
    local hook_instance = {
        name = name or "hook slot",

        func = hook,
        mask = mask,
        count = count,

        got_count = 0
    }

    if not name then
        self.hook_slot = hook_instance
        name = hook_instance.name
    end

    if mask then
        if mask:find("c", nil, true) then
            hook_instance.hook_call = true
        end
        if mask:find("r", nil, true) then
            hook_instance.hook_return = true
        end
        if mask:find("l", nil, true) then
            hook_instance.hook_line = true
        end

        if hook_instance.hook_call then
            self.map["c"][name] = hook_instance
        end
        if hook_instance.hook_return then
            self.map["r"][name] = hook_instance
        end
        if hook_instance.hook_line then
            self.map["l"][name] = hook_instance
        end
    end

    if count and count > 0 then
        self.count_hooks[name] = hook_instance
    end

    self:update_main_hook_all()
    return hook_instance
end

---@param name string?
function HookManager:unregiester(name)
    if name then
        for _, hooks in pairs(self.map) do
            hooks[name] = nil
        end
        self.count_hooks[name] = nil
    else
        self.hook_slot = nil
    end

    self:update_main_hook_all()
end

function HookManager:update_main_hook_mask()
    local call, _return, line = false, false, false

    local hook_slot = self.hook_slot
    if hook_slot then
        call = hook_slot.hook_call or false
        _return = hook_slot.hook_return or false
        line = hook_slot.hook_line or false
    end

    if next(self.map[HookMask.call], nil) then
        call = true
    end

    if next(self.map[HookMask._return], nil) then
        _return = true
    end

    if next(self.map[HookMask.call], nil) then
        call = true
    end

    local mask = ""

    if call then
        mask = mask .. HookMask.call
    end

    if _return then
        mask = mask .. HookMask._return
    end

    if line then
        mask = mask .. HookMask.line
    end

    self.mask = mask
end

function HookManager:update_main_hook_count()
    local min_count

    local hook_slot = self.hook_slot
    if hook_slot and hook_slot.count and hook_slot.count > 0 then
        min_count = hook_slot.count
    end

    for _, hook in pairs(self.count_hooks) do
        local needed_count = hook.count - (hook.got_count or 0)
        if not min_count or min_count > needed_count then
            min_count = needed_count
        end
    end

    self.count = min_count
end

function HookManager:update_main_hook()
    debug_sethook(self.thread, function(...)
        self:execute(...)
    end, self.mask, self.count)
end

function HookManager:update_main_hook_all()
    self:update_main_hook_mask()
    self:update_main_hook_count()
    self:update_main_hook()
end

return HookManager
