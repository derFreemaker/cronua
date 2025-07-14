local math_floor = math.floor

local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort

---@class Cronua.Task.Id : integer

---@enum Cronua.Priority
local Priority = {
    Low = 1,
    Normal = 2,
    High = 3,
    Realtime = 4,
}

---@enum Cronua.Task.State
local State = {
    Ready = 0,
    Running = 1,
    Sleeping = 2,
    Dead = 3,
}

---@class Cronua.Task
---@field id Cronua.Task.Id
---
---@field priority Cronua.Priority
---@field schedule_time_ms number?
---@field weight number
---
---@field state Cronua.Task.State

---@class Cronua.Scheduler.Callbacks
---@field get_time_point_ms fun() : number return time in seconds
---
---@field run_task fun(id: Cronua.Task.Id) : nil
---@field yield_current_task fun() : nil
---
---@field set_hook fun(hook: (fun() : nil), instructions: integer) : nil
---@field clear_hook fun() : nil
---
---@field idle fun(ms: integer) : nil

---@class Cronua.Scheduler.Options
---@field callbacks Cronua.Scheduler.Callbacks
---
---@field start_instructions integer used to find out how many instructions can be done per second
---@field min_time_ms number minimum time a task gets
---
---@field aging_factor number

---@class Cronua.Scheduler
---@field options Cronua.Scheduler.Options
---
---@field instructions_per_ms integer
---
---@field runqueue Cronua.Task.Id[]
---@field tasks { Cronua.TaskId: Cronua.Task }
---@field task_counter integer
local Scheduler = {}

---@param options Cronua.Scheduler.Options
local function get_base_IPMS(options)
    local start_time
    local instructions_per_ms
    local running = true

    options.callbacks.set_hook(function()
        options.callbacks.clear_hook()

        local time = options.callbacks.get_time_point_ms() - start_time
        instructions_per_ms = math_floor(options.start_instructions / time)

        running = false
    end, options.start_instructions)

    start_time = options.callbacks.get_time_point_ms()

    -- work load
    while running do
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

    return instructions_per_ms
end

---@param options Cronua.Scheduler.Options
---@return Cronua.Scheduler
function Scheduler.new(options)
    ---@type Cronua.Scheduler
    local instance = {
        options = options,

        instructions_per_ms = get_base_IPMS(options),

        runqueue = {},
        tasks = {},
        task_counter = 0,
    }

    return setmetatable(instance, { __index = Scheduler })
end

---@param task_id Cronua.Task.Id
---@return Cronua.Task
function Scheduler:get_task(task_id)
    return self.tasks[task_id]
end

---@param priority Cronua.Priority?
function Scheduler:add_task(priority)
    priority = priority or Priority.Normal

    self.task_counter = self.task_counter + 1
    local task_id = self.task_counter

    ---@type Cronua.Task
    local task = {
        id = task_id,

        priority = priority,
        weight = priority,

        state = State.Ready,
    }
    self.tasks[task_id] = task

    self:enqeue_task(task_id)

    return task
end

---@param task_id Cronua.Task.Id
function Scheduler:enqeue_task(task_id)
    local task = self:get_task(task_id)
    task.schedule_time_ms = self.options.callbacks.get_time_point_ms()

    if #self.runqueue == 0 then
        self.runqueue[1] = task_id
        return
    end

    for index, id in ipairs(self.runqueue) do
        local other_task = self:get_task(id)
        if other_task.weight < task.weight then
            table_insert(self.runqueue, index + 1, task_id)
            break
        end
    end
end

---@param task_id Cronua.Task.Id
function Scheduler:deqeue_task(task_id)
    for index, id in ipairs(self.runqueue) do
        if id == task_id then
            table_remove(self.runqueue, index)
        end
    end
end

function Scheduler:update_weights()
    local time_point_ms = self.options.callbacks.get_time_point_ms()

    for _, task in pairs(self.tasks) do
        local weight_before = task.weight
        task.weight = task.priority * ((time_point_ms - task.schedule_time_ms) / 1000 * self.options.aging_factor) +
            task.weight
        print(string.format("task: %d weight: %.2f -> %.2f", task.id, weight_before, task.weight))
    end

    table_sort(self.runqueue, function(a, b)
        return self:get_task(a).weight >= self:get_task(b).weight
    end)
end

function Scheduler:run()
    while true do
        if next(self.tasks, nil) == nil then
            break
        end

        if #self.runqueue == 0 then
            self.options.callbacks.idle(10)
        else
            local task_id = self.runqueue[#self.runqueue]
            self.runqueue[#self.runqueue] = nil
            local task = self:get_task(task_id)

            local instructions = task.weight * self.instructions_per_ms
            print(string.format("running task: %d with instructions %d", task_id, instructions))
            self.options.callbacks.set_hook(function()
                print("switching from task: " .. task_id)

                self.options.callbacks.clear_hook()
                self.options.callbacks.yield_current_task()
            end, instructions)

            self.options.callbacks.run_task(task_id)
            self.options.callbacks.clear_hook()

            print("completed task: " .. task_id)
        end
    end
end

---@class Cronua
local Cronua = {
    Priority = Priority,
    State = State,

    Scheduler = Scheduler,
}

return Cronua
