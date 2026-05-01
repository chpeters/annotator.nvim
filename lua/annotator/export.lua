---@type AnnotatorExporters
local M = {}

local function set_clipboard(text)
  local ok = pcall(vim.fn.setreg, "+", text)
  if ok then
    return true
  end

  if vim.fn.executable("pbcopy") == 1 then
    vim.fn.system({ "pbcopy" }, text)
    return vim.v.shell_error == 0
  end

  return false
end

---@param ctx AnnotatorExportContext
---@return boolean
function M.copy_to_clipboard(ctx)
  if not set_clipboard(ctx.markdown) then
    ctx.notify("Could not copy Annotator annotations to clipboard", "error")
    return false
  end

  ctx.clear_exported()
  ctx.notify("Copied " .. #ctx.annotations .. " annotation(s)", "info")
  return true
end

return M
