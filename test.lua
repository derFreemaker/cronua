local cronua = require("cronua")

local thread

local scheduler = cronua.Scheduler.new({
    callbacks = {
        get_time_point_ms = function()
            return os.clock() * 1000
        end,

        run_task = function(id)
            thread = coroutine.create(function(num)
                for i = 1, num * 10000000 do
                    local x = 1
                end
            end)
            coroutine.resume(thread, id)
            coroutine.close(thread)
            thread = nil
        end,
        yield_current_task = function()
            coroutine.yield()
        end,

        set_hook = function(hook, instructions)
            debug.sethook(thread or coroutine.running(), hook, "", instructions)
        end,
        clear_hook = function()
            debug.sethook(thread or coroutine.running())
        end,

        idle = function(ms)
            local sleep_end = os.clock() + ms * 1000
            while (os.clock() < sleep_end) do end
        end,
    },

    start_instructions = 8000000, -- ~50ms
    min_time_ms = 10,

    aging_factor = 0.2,
})

for _ = 1, 10000 do
    scheduler:add_task()
end

scheduler:run()
