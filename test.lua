-- local HookManager = require("hook_manager")
-- local hook_manager = HookManager.new()

local cronua = require("cronua")

local threads = {}

local function get_base_IPS()
    local thread = coroutine.create(function()
        while true do
            local function work(x)
                for k = 1, 10 do
                    x = x + k
                end
            end

            for j = 1, 10 do
                local x = j * j + j - 1
                work(x)
            end
        end
    end)

    -- debug.sethook(thread, function()
    --     debug.sethook(thread)

    --     local time = os.clock() * 1000 - start_time
    --     instructions_per_ms = math.floor(1000000 / time)

    -- end, "", 1000000)

    local instructions = 1000000
    coroutine.yieldafterinstructions(thread, instructions)

    local start_time = os.clock()
    coroutine.resume(thread)
    local time = os.clock() - start_time

    return math.floor(instructions / time)
end

local scheduler = cronua.Scheduler.new({
    callbacks = {
        get_time_point_ms = function()
            return os.clock() * 1000
        end,

        run_task = function(task, instructions)
            local thread = threads[task.id]

            if not thread then
                thread = {
                    finished = false,
                }

                thread.thread = coroutine.create(function(num)
                    local function work(x)
                        for k = 1, 10 do
                            x = x + k
                        end
                    end

                    for j = 1, num * 100000 do
                        local x = j * j + j - 1
                        work(x)
                    end

                    thread.finished = true
                end)
                threads[task.id] = thread
            end

            coroutine.yieldafterinstructions(thread.thread, instructions)
            print("task:", task.id, "stopped", coroutine.resume(thread.thread, task.id))

            if thread.finished then
                task.state = cronua.State.Dead
                coroutine.close(thread.thread)
                threads[task.id] = nil
            end
        end,

        idle = function(ms)
            print("idle")
            local sleep_end = os.clock() + ms / 1000
            while (os.clock() < sleep_end) do end
        end,
    },

    instructions_per_ms = math.floor(get_base_IPS() / 1000),
    min_time_ms = 50,

    aging_factor = 0.2,
})

for i = 1, 100 do
    scheduler:add_task(i % 4 + 1)
end

scheduler:run()
-- hook_manager:close()

print("$END$")
