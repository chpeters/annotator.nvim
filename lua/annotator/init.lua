local annotate = require("annotator.annotate")
local markdown = require("annotator.markdown")
local render = require("annotator.render")
local exporter = require("annotator.export")
local state = require("annotator.state")
local store = require("annotator.store")
local ui = require("annotator.ui")

---@alias AnnotatorAnnotationKind "comment"|"suggest"|"delete"|"label"
---@alias AnnotatorStorage "memory"|"state"
---@alias AnnotatorNotifyKind "info"|"warn"|"error"
---@alias AnnotatorVirtualTextPosition "eol"|"eol_right_align"|"inline"|"overlay"|"right_align"

---@class AnnotatorAnnotation
---@field id string
---@field kind? AnnotatorAnnotationKind Missing kind is treated as "comment".
---@field cwd string
---@field repo_root? string
---@field git_branch? string
---@field git_commit? string
---@field file_path string Absolute file path.
---@field relative_path? string Path relative to the Git root when available.
---@field start_line integer 1-based inclusive line number.
---@field end_line integer 1-based inclusive line number.
---@field snippet string Original selected text.
---@field comment string Exported feedback text.
---@field timestamp string UTC timestamp.
---@field label? string Label id for label annotations.
---@field label_title? string Label display title for label annotations.
---@field replacement? string Replacement text for suggestion annotations.
---@field bufnr? integer Runtime-only buffer id, not persisted.
---@field extmark_id? integer Runtime-only extmark id, not persisted.

---@class AnnotatorLabel
---@field id string Stable label id used in exports.
---@field title string Label shown in the picker.
---@field comment string Exported feedback text.
---@field text? string Deprecated fallback for comment.

---@class AnnotatorDisplayKindConfig
---@field sign_text? string Sign column text for this annotation kind.
---@field sign_hl_group? string Sign highlight group for this annotation kind.
---@field virtual_text_prefix? string Prefix before this kind's virtual text preview.
---@field virtual_text_hl_group? string Virtual text highlight group for this annotation kind.
---@field virtual_text_pos? AnnotatorVirtualTextPosition|string Extmark virtual text position for this annotation kind.
---@field max_comment_length? integer Maximum virtual text comment preview length for this annotation kind.
---@field priority? integer Extmark priority for this annotation kind.

---@class AnnotatorDisplayConfig
---@field sign_text? string Sign column text.
---@field sign_hl_group? string Sign highlight group.
---@field virtual_text_prefix? string Prefix before the virtual text preview.
---@field virtual_text_hl_group? string Virtual text highlight group.
---@field virtual_text_pos? AnnotatorVirtualTextPosition|string Extmark virtual text position.
---@field max_comment_length? integer Maximum virtual text comment preview length.
---@field priority? integer Extmark priority.
---@field kinds? table<AnnotatorAnnotationKind, AnnotatorDisplayKindConfig> Per-kind display overrides.

---@class AnnotatorFormatterContext
---@field annotations AnnotatorAnnotation[] Pending typed annotations.
---@field default_format fun(annotations: AnnotatorAnnotation[]): string Built-in Markdown formatter.

---@class AnnotatorExportContext
---@field markdown string Rendered Markdown.
---@field annotations AnnotatorAnnotation[] Pending typed annotations.
---@field notify fun(message: string, kind?: AnnotatorNotifyKind|string)
---@field clear_exported fun() Clear exported annotations after a successful export.

---@class AnnotatorHooks
---@field export? fun(ctx: AnnotatorExportContext): any

---@class AnnotatorConfig
---@field mappings? boolean Whether to create default mappings.
---@field storage? AnnotatorStorage Memory-only or Neovim state-backed storage.
---@field storage_path? string Path override for state-backed storage.
---@field display? AnnotatorDisplayConfig Sign and virtual text display options.
---@field labels? AnnotatorLabel[] Label picker entries.
---@field formatter? fun(ctx: AnnotatorFormatterContext): string Export Markdown formatter.
---@field hooks? AnnotatorHooks Export hook configuration.

---@class AnnotatorCommandContext
---@field range integer
---@field line1 integer
---@field line2 integer

---@class AnnotatorExporters
---@field copy_to_clipboard fun(ctx: AnnotatorExportContext): boolean

---@class Annotator
---@field exporters AnnotatorExporters
---@type Annotator
local M = {}

---@type AnnotatorLabel[]
local default_labels = {
  { id = "explain", title = "Explain", comment = "Please explain this more clearly." },
  { id = "clarify", title = "Clarify", comment = "Please clarify this point." },
  { id = "simplify", title = "Simplify", comment = "Please simplify this." },
  { id = "tighten", title = "Tighten", comment = "Please tighten this up." },
  { id = "expand", title = "Expand", comment = "Please expand on this." },
}

---@type AnnotatorConfig
local config = {
  mappings = true,
  storage = "memory",
  display = {
    sign_text = "A>",
    sign_hl_group = "AnnotatorAnnotationSign",
    virtual_text_prefix = " Annotation: ",
    virtual_text_hl_group = "AnnotatorAnnotationVirtual",
    virtual_text_pos = "eol",
    max_comment_length = 80,
    priority = 120,
    kinds = {
      comment = {
        sign_text = "C>",
        virtual_text_prefix = " Comment: ",
      },
      suggest = {
        sign_text = "S>",
        virtual_text_prefix = " Suggest: ",
      },
      delete = {
        sign_text = "D>",
        virtual_text_prefix = " Delete: ",
      },
      label = {
        sign_text = "L>",
        virtual_text_prefix = " Label: ",
      },
    },
  },
  hooks = {
    export = exporter.copy_to_clipboard,
  },
  labels = default_labels,
  formatter = nil,
}

local storage_enabled = false
local storage_path

local function ids(items)
  return vim.tbl_map(function(annotation)
    return annotation.id
  end, items)
end

local function clear_all()
  render.clear_all(state.all())
  state.clear()
end

local function clear_exported(items)
  render.clear_all(state.remove_ids(ids(items)))
end

local function persist(items)
  if not storage_enabled then
    return
  end

  local ok, err = store.save(storage_path, items)
  if not ok then
    ui.notify(err or "Could not save Annotator annotations state", "error")
  end
end

local function notify(message, kind)
  ui.notify(message, kind)
end

---@param items AnnotatorAnnotation[]
---@return string
local function default_format(items)
  return markdown.render(items)
end

---@param items AnnotatorAnnotation[]
---@return string
local function format_annotations(items)
  if type(config.formatter) ~= "function" then
    return default_format(items)
  end

  local ok, result = pcall(config.formatter, {
    annotations = vim.deepcopy(items),
    default_format = default_format,
  })

  if not ok then
    ui.notify("Annotator formatter failed: " .. tostring(result), "error")
    return default_format(items)
  end

  if type(result) ~= "string" then
    ui.notify("Annotator formatter must return a string", "error")
    return default_format(items)
  end

  return result
end

local function same_path(left, right)
  return vim.fn.fnamemodify(left or "", ":p") == vim.fn.fnamemodify(right or "", ":p")
end

local function render_buffer_annotations(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then
    return
  end

  render.clear_buffer(bufnr)
  for _, annotation in ipairs(state.all()) do
    if same_path(annotation.file_path, file_path) then
      annotation.bufnr = bufnr
      annotation.extmark_id = nil
      render.show(annotation)
    end
  end
end

local function render_open_annotations()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    render_buffer_annotations(bufnr)
  end
end

local function setup_storage()
  storage_enabled = config.storage == "state"
  storage_path = config.storage_path or store.default_path()

  if config.storage ~= "memory" and config.storage ~= "state" then
    storage_enabled = false
    state.configure({ on_change = nil })
    ui.notify("Unknown Annotator annotations storage: " .. tostring(config.storage), "error")
    return
  end

  if not storage_enabled then
    state.configure({ on_change = nil })
    return
  end

  local items, err = store.load(storage_path)
  if items then
    state.replace(items)
  elseif err then
    ui.notify(err, "error")
  end

  state.configure({ on_change = persist })
end

---@param items AnnotatorAnnotation[]
---@return AnnotatorExportContext
local function export_context(items)
  local cleared = false

  return {
    annotations = vim.deepcopy(items),
    markdown = format_annotations(items),
    notify = notify,
    clear_exported = function()
      if cleared then
        return
      end
      cleared = true
      clear_exported(items)
    end,
  }
end

---@param ctx? AnnotatorCommandContext
function M.add(ctx)
  annotate.command(ctx)
end

function M.add_visual()
  annotate.visual_selection()
end

---@param ctx? AnnotatorCommandContext
function M.suggest(ctx)
  annotate.suggest_command(ctx)
end

function M.suggest_visual()
  annotate.suggest_visual()
end

---@param ctx? AnnotatorCommandContext
function M.mark_delete(ctx)
  annotate.mark_delete_command(ctx)
end

function M.mark_delete_visual()
  annotate.mark_delete_visual()
end

---@param ctx? AnnotatorCommandContext
function M.label(ctx)
  annotate.label_command(ctx)
end

function M.label_visual()
  annotate.label_visual()
end

function M.edit()
  annotate.edit_current()
end

function M.delete()
  annotate.delete_current()
end

function M.list()
  ui.annotations(state.snapshot())
end

---@return string
function M.render()
  return format_annotations(state.snapshot())
end

function M.export()
  local items = state.snapshot()
  if #items == 0 then
    ui.notify("No pending Annotator annotations", "info")
    return
  end

  local hook = config.hooks and config.hooks.export
  if type(hook) ~= "function" then
    ui.notify("No Annotator annotations export hook configured", "error")
    return
  end

  hook(export_context(items))
end

function M.clear()
  clear_all()
  ui.notify("Cleared Annotator annotations", "info")
end

---@param opts? AnnotatorConfig
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", config, opts)
  if opts.labels ~= nil then
    config.labels = opts.labels
  end
  annotate.setup({
    labels = config.labels,
  })
  render.setup(config.display)
  setup_storage()

  pcall(vim.api.nvim_del_user_command, "AnnotatorAdd")
  pcall(vim.api.nvim_del_user_command, "AnnotatorSuggest")
  pcall(vim.api.nvim_del_user_command, "AnnotatorMarkDelete")
  pcall(vim.api.nvim_del_user_command, "AnnotatorLabel")
  pcall(vim.api.nvim_del_user_command, "AnnotatorEdit")
  pcall(vim.api.nvim_del_user_command, "AnnotatorDelete")
  pcall(vim.api.nvim_del_user_command, "AnnotatorList")
  pcall(vim.api.nvim_del_user_command, "AnnotatorExport")
  pcall(vim.api.nvim_del_user_command, "AnnotatorClear")

  vim.api.nvim_create_user_command("AnnotatorAdd", function(ctx)
    M.add(ctx)
  end, { range = true })

  vim.api.nvim_create_user_command("AnnotatorSuggest", function(ctx)
    M.suggest(ctx)
  end, { range = true })

  vim.api.nvim_create_user_command("AnnotatorMarkDelete", function(ctx)
    M.mark_delete(ctx)
  end, { range = true })

  vim.api.nvim_create_user_command("AnnotatorLabel", function(ctx)
    M.label(ctx)
  end, { range = true })

  vim.api.nvim_create_user_command("AnnotatorEdit", M.edit, {})
  vim.api.nvim_create_user_command("AnnotatorDelete", M.delete, {})
  vim.api.nvim_create_user_command("AnnotatorList", M.list, {})
  vim.api.nvim_create_user_command("AnnotatorExport", M.export, {})
  vim.api.nvim_create_user_command("AnnotatorClear", M.clear, {})

  local group = vim.api.nvim_create_augroup("annotator", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufFilePost" }, {
    group = group,
    callback = function(args)
      render_buffer_annotations(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      render.clear_buffer(args.buf)
      if not storage_enabled then
        state.remove_buffer(args.buf)
      end
    end,
  })

  if config.mappings then
    vim.keymap.set("n", "<leader>aa", function()
      M.add()
    end, { desc = "Add annotation" })
    vim.keymap.set("x", "<leader>aa", function()
      M.add_visual()
    end, { desc = "Add annotation selection" })
    vim.keymap.set("n", "<leader>ax", function()
      M.export()
    end, { desc = "Export annotations" })
  end

  render_open_annotations()
end

---@type AnnotatorExporters
M.exporters = exporter

return M
