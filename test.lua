local HookManager = require("hook_manager")
local hook_manager = HookManager.new()

local cronua = require("cronua")

local threads = {}

local function get_base_IPMS()
    local start_time
    local instructions_per_ms

    local thread = coroutine.create(function()
        local function work(x)
            for k = 1, 10 do
                x = x + k
            end
        end

        for j = 1, 10 do
            local x = j * j + j - 1
            work(x)
        end
    end)

    debug.sethook(thread, function()
        debug.sethook(thread)

        local time = os.clock() * 1000 - start_time
        instructions_per_ms = math.floor(1000000 / time)

        coroutine.yield()
    end, 1000000)

    start_time = os.clock() * 1000

    coroutine.resume(thread)

    return instructions_per_ms
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
                    local task_hook_manager = HookManager.new()
                    local function hook()
                        print("switching from task: " .. task.id)
                        print(debug.getinfo(thread.thread, 2, "l").currentline)
                        coroutine.yield()
                    end
                    task_hook_manager:register(hook, "", instructions, "scheduler")

                    local function work(x)
                        for k = 1, 10 do
                            x = x + k
                        end
                    end

                    for j = 1, num * 100000 do
                        local x = j * j + j - 1
                        work(x)
                    end

                    task_hook_manager:close()
                    thread.finished = true
                end)
                threads[task.id] = thread
            end

            print("run task: " .. tostring(task.id))
            coroutine.resume(thread.thread, task.id)

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

    instructions_per_ms = get_base_IPMS(),
    min_time_ms = 10,

    aging_factor = 0.2,
})

for i = 1, 50 do
    scheduler:add_task(i % 4 + 1)
end

scheduler:run()
hook_manager:close()

print("$END$")
