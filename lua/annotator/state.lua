local M = {}

local items = {}
local next_id = 1
local on_change

local function copy_list(list)
  return vim.deepcopy(list)
end

local function id_number(id)
  return tonumber((id or ""):match("^annotator%-ann%-(%d+)$"))
end

local function bump_next_id(id)
  local number = id_number(id)
  if number and number >= next_id then
    next_id = number + 1
  end
end

local function reset_next_id(list)
  next_id = 1
  for _, annotation in ipairs(list) do
    bump_next_id(annotation.id)
  end
end

local function changed()
  if on_change then
    on_change(copy_list(items))
  end
end

local function compare_position(a, b)
  if (a.start_line or 0) ~= (b.start_line or 0) then
    return (a.start_line or 0) < (b.start_line or 0)
  end
  if (a.end_line or 0) ~= (b.end_line or 0) then
    return (a.end_line or 0) < (b.end_line or 0)
  end
  return tostring(a.id or "") < tostring(b.id or "")
end

function M.configure(opts)
  on_change = opts and opts.on_change or nil
end

function M.replace(list)
  items = copy_list(list or {})
  reset_next_id(items)
end

function M.add(annotation)
  annotation.id = annotation.id or ("annotator-ann-" .. tostring(next_id))
  bump_next_id(annotation.id)
  table.insert(items, annotation)
  changed()
  return annotation
end

function M.find(predicate)
  local matches = {}
  for _, annotation in ipairs(items) do
    if predicate(annotation) then
      table.insert(matches, annotation)
    end
  end

  table.sort(matches, compare_position)
  return matches[1]
end

function M.update(id, fields)
  for _, annotation in ipairs(items) do
    if annotation.id == id then
      for key, value in pairs(fields) do
        annotation[key] = value
      end
      changed()
      return annotation
    end
  end
  return nil
end

function M.all()
  return items
end

function M.count()
  return #items
end

function M.snapshot()
  return copy_list(items)
end

function M.clear()
  items = {}
  changed()
end

function M.remove_ids(ids)
  local idset = {}
  for _, id in ipairs(ids) do
    idset[id] = true
  end

  local kept = {}
  local removed = {}
  for _, annotation in ipairs(items) do
    if idset[annotation.id] then
      table.insert(removed, annotation)
    else
      table.insert(kept, annotation)
    end
  end

  items = kept
  changed()
  return removed
end

function M.remove_buffer(bufnr)
  local kept = {}
  for _, annotation in ipairs(items) do
    if annotation.bufnr ~= bufnr then
      table.insert(kept, annotation)
    end
  end
  items = kept
  changed()
end

return M
