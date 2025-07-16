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
---@field run_task fun(task: Cronua.Task, instructions: integer) : nil
---
---@field idle fun(ms: integer) : nil

---@class Cronua.Scheduler.Options
---@field callbacks Cronua.Scheduler.Callbacks
---
---@field instructions_per_ms integer
---@field min_time_ms number minimum time a task gets
---
---@field aging_factor number

---@class Cronua.Scheduler
---@field options Cronua.Scheduler.Options
---
---@field runqueue Cronua.Task.Id[]
---@field tasks { [Cronua.Task.Id]: Cronua.Task }
---@field task_counter integer
local Scheduler = {}

---@param options Cronua.Scheduler.Options
---@return Cronua.Scheduler
function Scheduler.new(options)
    ---@type Cronua.Scheduler
    local instance = {
        options = options,

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

    self:enqeueu_task(task_id)

    return task
end

---@param task_id Cronua.Task.Id
function Scheduler:remove_task(task_id)
    self.tasks[task_id] = nil
end

---@param task_id Cronua.Task.Id
function Scheduler:enqeueu_task(task_id)
    local task = self:get_task(task_id)
    task.schedule_time_ms = self.options.callbacks.get_time_point_ms()

    if #self.runqueue == 0 then
        self.runqueue[1] = task_id
        return
    end

    local inserted = false
    for index, id in ipairs(self.runqueue) do
        local other_task = self:get_task(id)
        local weight_dif = task.weight - other_task.weight
        if weight_dif > 0 then
            table_insert(self.runqueue, index + 1, task_id)
            inserted = true
            break
        elseif weight_dif == 0 then
            table_insert(self.runqueue, index, task_id)
            inserted = true
            break
        end
    end

    if not inserted then
        table_insert(self.runqueue, 1, task_id)
    end
end

---@param task_id Cronua.Task.Id
function Scheduler:deqeueu_task(task_id)
    for index, id in ipairs(self.runqueue) do
        if id == task_id then
            table_remove(self.runqueue, index)
            break
        end
    end
end

function Scheduler:update_weights()
    local time_point_ms = self.options.callbacks.get_time_point_ms()

    for _, task in pairs(self.tasks) do
        -- local weight_before = task.weight
        task.weight = task.weight +
            (task.priority / 2) * ((time_point_ms - task.schedule_time_ms) / 10 * self.options.aging_factor)
        -- print(("Task: %d weight: %.2f -> %.2f\n"):format(task.id, weight_before, task.weight))
    end

    table_sort(self.runqueue, function(a, b)
        return self:get_task(a).weight < self:get_task(b).weight
    end)
end

function Scheduler:run()
    local i = 0
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

            local time_ms = math.max(task.priority * task.weight, self.options.min_time_ms)
            local instructions = math.floor(self.options.instructions_per_ms * time_ms)
            print(("running task: %d time: %.2fms weight: %.2f instructions %d")
                :format(task_id, time_ms, task.weight, instructions))

            task.weight = math.max(task.weight / 2, task.priority)
            self.options.callbacks.run_task(task, instructions)

            if task.state == State.Dead then
                print("completed task: " .. task_id)
                self:remove_task(task_id)
            else
                self:enqeueu_task(task_id)
            end
        end

        if i == 20 then
            i = 0
            self:update_weights()
        end
        i = i + 1
    end
end

---@class Cronua
local Cronua = {
    Priority = Priority,
    State = State,

    Scheduler = Scheduler,
}

return Cronua
