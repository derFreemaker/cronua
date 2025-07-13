local cronua = require("cronua")

local scheduler = cronua.Scheduler.new({
    callbacks = {
        get_time_point_ms = function()
            return os.clock() * 1000
        end,

        run_task = function(id)
            error("run task: " .. tostring(id))
        end,
        yield_current_task = function()
            error("yield current task")
        end,

        set_hook = function(hook, instructions)
            debug.sethook(hook, "", instructions)
        end,
        clear_hook = debug.sethook,

        idle = function(ms)
            local sleep_end = os.clock() + ms * 1000
            while (os.clock() < sleep_end) do end
        end,
    },

    start_instructions = 8000000, -- ~50ms
    min_time_ms = 10,

    aging_factor = 0.2,
})

print(string.format("%d instructions per millisecond", scheduler.instructions_per_ms))
