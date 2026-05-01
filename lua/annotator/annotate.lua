local context = require("annotator.context")
local render = require("annotator.render")
local state = require("annotator.state")
local ui = require("annotator.ui")

local M = {}

---@type { labels: AnnotatorLabel[] }
local config = {
  labels = {},
}

local function validate_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    ui.notify("Annotator annotation target buffer is no longer available", "warn")
    return nil
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    ui.notify("Save the buffer before annotating it", "warn")
    return nil
  end
  return vim.fn.fnamemodify(file_path, ":p")
end

local function selected_lines(bufnr, start_line, end_line)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false), "\n")
end

local function same_path(left, right)
  return vim.fn.fnamemodify(left or "", ":p") == vim.fn.fnamemodify(right or "", ":p")
end

local function clamp_range(bufnr, start_line, end_line)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count < 1 then
    line_count = 1
  end

  start_line = math.max(1, math.min(start_line, line_count))
  end_line = math.max(1, math.min(end_line, line_count))

  return math.min(start_line, end_line), math.max(start_line, end_line)
end

local function range_from_ctx(ctx)
  if ctx and ctx.range and ctx.range > 0 then
    return ctx.line1, ctx.line2
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return line, line
end

local function visual_range()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")

  if start_line == 0 or end_line == 0 then
    start_line = vim.fn.getpos("'<")[2]
    end_line = vim.fn.getpos("'>")[2]
  end

  return start_line, end_line
end

local function target_for_range(start_line, end_line)
  if not start_line or not end_line or start_line < 1 or end_line < 1 then
    ui.notify("Could not determine Annotator annotation range", "warn")
    return nil
  end

  local target = {
    bufnr = vim.api.nvim_get_current_buf(),
    cwd = vim.fn.getcwd(),
    start_line = math.min(start_line, end_line),
    end_line = math.max(start_line, end_line),
  }

  if not validate_buffer(target.bufnr) then
    return nil
  end

  target.start_line, target.end_line = clamp_range(target.bufnr, target.start_line, target.end_line)
  target.file_path = vim.api.nvim_buf_get_name(target.bufnr)
  target.filetype = vim.bo[target.bufnr].filetype
  target.snippet = selected_lines(target.bufnr, target.start_line, target.end_line)

  return target
end

local function build_annotation(target, fields)
  local bufnr = target.bufnr
  local file_path = validate_buffer(bufnr)
  if not file_path then
    return nil
  end

  local start_line, end_line = clamp_range(bufnr, target.start_line, target.end_line)
  local repo_root = context.git_root(file_path)
  local annotation = {
    kind = fields.kind or "comment",
    bufnr = bufnr,
    cwd = target.cwd,
    repo_root = repo_root,
    git_branch = context.git_branch(repo_root),
    git_commit = context.git_commit(repo_root),
    file_path = file_path,
    relative_path = context.relative_path(repo_root, file_path),
    start_line = start_line,
    end_line = end_line,
    snippet = selected_lines(bufnr, start_line, end_line),
    comment = fields.comment or "",
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }

  for key, value in pairs(fields) do
    annotation[key] = value
  end

  return annotation
end

local function matches_kind(annotation, kind)
  return (annotation.kind or "comment") == kind
end

local function find_exact(file_path, start_line, end_line, kind)
  return state.find(function(annotation)
    return same_path(annotation.file_path, file_path)
      and annotation.start_line == start_line
      and annotation.end_line == end_line
      and (not kind or matches_kind(annotation, kind))
  end)
end

local function find_covering(file_path, line, kind)
  return state.find(function(annotation)
    return same_path(annotation.file_path, file_path)
      and annotation.start_line <= line
      and annotation.end_line >= line
      and (not kind or matches_kind(annotation, kind))
  end)
end

local function save_annotation(target, fields, existing)
  local annotation = build_annotation(target, fields)
  if not annotation then
    return
  end

  if existing then
    annotation.id = existing.id
    render.clear(existing)
    annotation = state.update(existing.id, annotation)
    if annotation then
      render.show(annotation)
      ui.notify("Updated annotation", "info")
    end
    return annotation
  end

  annotation = state.add(annotation)
  render.show(annotation)
  ui.notify("Added annotation", "info")
  return annotation
end

local function edit_text(target, existing)
  ui.input("Annotation: ", existing and existing.comment or nil, function(comment)
    if not comment or comment:gsub("%s+", "") == "" then
      return
    end

    save_annotation(target, {
      kind = existing and (existing.kind or "comment") or "comment",
      comment = comment,
    }, existing)
  end)
end

local function label_comment(label)
  return label.comment or label.text or label.title or label.id
end

local function select_label(target, existing)
  if #config.labels == 0 then
    ui.notify("No Annotator labels configured", "warn")
    return
  end

  ui.select("Annotation label: ", config.labels, function(label)
    return label.title or label.id
  end, function(label)
    if not label then
      return
    end

    save_annotation(target, {
      kind = "label",
      label = label.id,
      label_title = label.title,
      comment = label_comment(label),
    }, existing)
  end)
end

local function edit_suggestion(target, existing)
  ui.edit_replacement({
    title = "Suggestion",
    filetype = target.filetype,
    text = existing and existing.replacement or target.snippet,
  }, function(replacement)
    save_annotation(target, {
      kind = "suggest",
      comment = existing and existing.comment or "Suggested replacement.",
      replacement = replacement,
    }, existing)
  end)
end

local function edit_annotation(existing)
  local target = target_for_range(existing.start_line, existing.end_line)
  if not target then
    return
  end

  local kind = existing.kind or "comment"
  if kind == "suggest" then
    edit_suggestion(target, existing)
  elseif kind == "label" then
    select_label(target, existing)
  else
    edit_text(target, existing)
  end
end

---@param opts? { labels?: AnnotatorLabel[] }
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", config, opts)
  if opts.labels ~= nil then
    config.labels = opts.labels
  end
end

function M.range(start_line, end_line, opts)
  local target = target_for_range(start_line, end_line)
  if not target then
    return
  end

  local existing
  if opts and opts.match == "covering" then
    existing = find_covering(target.file_path, target.start_line, "comment")
  else
    existing = find_exact(target.file_path, target.start_line, target.end_line, "comment")
  end
  if existing and opts and opts.match == "covering" then
    target.start_line = existing.start_line
    target.end_line = existing.end_line
    target.snippet = selected_lines(target.bufnr, target.start_line, target.end_line)
  end

  edit_text(target, existing)
end

function M.current_line()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  M.range(line, line, { match = "covering" })
end

function M.visual_selection()
  M.range(visual_range())
end

---@param ctx? AnnotatorCommandContext
function M.command(ctx)
  M.range(range_from_ctx(ctx))
end

function M.suggest(start_line, end_line)
  local target = target_for_range(start_line, end_line)
  if not target then
    return
  end

  local existing = find_exact(target.file_path, target.start_line, target.end_line, "suggest")
  edit_suggestion(target, existing)
end

---@param ctx? AnnotatorCommandContext
function M.suggest_command(ctx)
  M.suggest(range_from_ctx(ctx))
end

function M.suggest_visual()
  M.suggest(visual_range())
end

function M.mark_delete(start_line, end_line)
  local target = target_for_range(start_line, end_line)
  if not target then
    return
  end

  local existing = find_exact(target.file_path, target.start_line, target.end_line, "delete")
  save_annotation(target, {
    kind = "delete",
    comment = "Remove this text.",
  }, existing)
end

---@param ctx? AnnotatorCommandContext
function M.mark_delete_command(ctx)
  M.mark_delete(range_from_ctx(ctx))
end

function M.mark_delete_visual()
  M.mark_delete(visual_range())
end

function M.label(start_line, end_line)
  local target = target_for_range(start_line, end_line)
  if not target then
    return
  end

  local existing = find_exact(target.file_path, target.start_line, target.end_line, "label")
  select_label(target, existing)
end

---@param ctx? AnnotatorCommandContext
function M.label_command(ctx)
  M.label(range_from_ctx(ctx))
end

function M.label_visual()
  M.label(visual_range())
end

function M.edit_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = validate_buffer(bufnr)
  if not file_path then
    return
  end

  local existing = find_covering(file_path, vim.api.nvim_win_get_cursor(0)[1])
  if not existing then
    ui.notify("No annotation at cursor", "info")
    return
  end

  edit_annotation(existing)
end

function M.delete_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = validate_buffer(bufnr)
  if not file_path then
    return
  end

  local existing = find_covering(file_path, vim.api.nvim_win_get_cursor(0)[1])
  if not existing then
    ui.notify("No annotation at cursor", "info")
    return
  end

  render.clear_all(state.remove_ids({ existing.id }))
  ui.notify("Deleted annotation", "info")
end

return M
