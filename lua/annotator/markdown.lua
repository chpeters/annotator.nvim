local M = {}

local function extension(path)
  return (path or ""):match("%.([^%.]+)$") or ""
end

local function fence_for(text)
  if (text or ""):find("```", 1, true) then
    return "````"
  end
  return "```"
end

local function line_range(annotation)
  if annotation.start_line == annotation.end_line then
    return "line " .. annotation.start_line
  end
  return "lines " .. annotation.start_line .. "-" .. annotation.end_line
end

local function sorted_annotations(items)
  table.sort(items, function(a, b)
    local a_path = a.relative_path or a.file_path
    local b_path = b.relative_path or b.file_path
    if a_path == b_path then
      if a.start_line == b.start_line then
        if a.end_line == b.end_line then
          return tostring(a.id or "") < tostring(b.id or "")
        end
        return a.end_line < b.end_line
      end
      return a.start_line < b.start_line
    end
    return a_path < b_path
  end)
  return items
end

local function kind_label(annotation)
  local kind = annotation.kind or "comment"
  if kind == "label" and annotation.label then
    return "label:" .. annotation.label
  end
  return kind
end

local function append_block(lines, title, text, file)
  local fence = fence_for(text)
  table.insert(lines, title)
  table.insert(lines, "")
  table.insert(lines, fence .. extension(file))
  table.insert(lines, text or "")
  table.insert(lines, fence)
  table.insert(lines, "")
end

local function append_comment(lines, annotation, file)
  table.insert(lines, annotation.comment or "")
  table.insert(lines, "")
  append_block(lines, "Current text:", annotation.snippet, file)
end

local function append_suggestion(lines, annotation, file)
  table.insert(lines, annotation.comment or "Suggested replacement.")
  table.insert(lines, "")
  append_block(lines, "Current text:", annotation.snippet, file)
  append_block(lines, "Suggested replacement:", annotation.replacement, file)
end

local function append_delete(lines, annotation, file)
  table.insert(lines, annotation.comment or "Remove this text.")
  table.insert(lines, "")
  append_block(lines, "Text to remove:", annotation.snippet, file)
end

---@param items AnnotatorAnnotation[]
---@return string
function M.render(items)
  local annotations = sorted_annotations(vim.deepcopy(items))
  local lines = {
    "Neovim annotations:",
    "",
  }

  local current_file = nil
  for _, annotation in ipairs(annotations) do
    local file = annotation.relative_path or annotation.file_path
    if file ~= current_file then
      current_file = file
      table.insert(lines, "## " .. file)
      table.insert(lines, "")
    end

    local kind = annotation.kind or "comment"
    table.insert(lines, "- [" .. kind_label(annotation) .. "] " .. line_range(annotation) .. " (" .. annotation.id .. ")")
    table.insert(lines, "")

    if kind == "suggest" then
      append_suggestion(lines, annotation, file)
    elseif kind == "delete" then
      append_delete(lines, annotation, file)
    else
      append_comment(lines, annotation, file)
    end
  end

  return table.concat(lines, "\n")
end

---@param annotation AnnotatorAnnotation
---@return string
function M.preview(annotation)
  return M.render({ annotation })
end

return M
