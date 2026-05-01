local M = {}

local namespace = vim.api.nvim_create_namespace("annotator")

local config = {
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
}

local function display_for(annotation)
  local kind = annotation.kind or "comment"
  return vim.tbl_deep_extend("force", config, config.kinds and config.kinds[kind] or {})
end

local function short_comment(comment, display)
  local value = (comment or ""):gsub("%s+", " ")
  local max_length = display.max_comment_length or 80
  if max_length > 3 and #value > max_length then
    return value:sub(1, max_length - 3) .. "..."
  end
  return value
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  vim.api.nvim_set_hl(0, "AnnotatorAnnotationSign", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "AnnotatorAnnotationVirtual", { link = "Comment", default = true })
end

function M.show(annotation)
  if not vim.api.nvim_buf_is_valid(annotation.bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(annotation.bufnr)
  if line_count < 1 then
    return
  end

  local line = math.max(0, math.min((annotation.start_line or 1) - 1, line_count - 1))
  local display = display_for(annotation)

  local opts = {
    sign_text = display.sign_text,
    sign_hl_group = display.sign_hl_group,
    virt_text = {
      { (display.virtual_text_prefix or "") .. short_comment(annotation.comment, display), display.virtual_text_hl_group },
    },
    virt_text_pos = display.virtual_text_pos,
    priority = display.priority,
  }

  annotation.extmark_id = vim.api.nvim_buf_set_extmark(annotation.bufnr, namespace, line, 0, opts)
end

function M.clear(annotation)
  if annotation and annotation.extmark_id and vim.api.nvim_buf_is_valid(annotation.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, annotation.bufnr, namespace, annotation.extmark_id)
  end
end

function M.clear_all(items)
  for _, annotation in ipairs(items) do
    M.clear(annotation)
  end
end

function M.clear_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
end

return M
