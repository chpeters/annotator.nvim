local store = require("annotator.store")

local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn

local function snacks_picker_available()
  local snack = rawget(_G, "Snacks")
  if not snack then
    local ok_module, mod = pcall(require, "snacks")
    if ok_module then
      snack = mod
    end
  end
  return snack and snack.picker ~= nil
end

function M.check()
  start("annotator.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim version is supported")
  else
    warn("Neovim 0.10 or newer is recommended")
  end

  if vim.ui and type(vim.ui.input) == "function" then
    ok("vim.ui.input is available")
  else
    warn("vim.ui.input is required to add and edit annotations")
  end

  if vim.fn.has("clipboard") == 1 or vim.fn.executable("pbcopy") == 1 then
    ok("Clipboard support is available for the default exporter")
  else
    warn("No clipboard provider found; configure hooks.export for exporting annotations")
  end

  if snacks_picker_available() then
    ok("Snacks picker is available for :AnnotatorList")
  else
    ok("Snacks picker is not installed; :AnnotatorList will use quickfix")
  end

  local state_dir = vim.fn.stdpath("state")
  if vim.fn.isdirectory(state_dir) == 1 and vim.fn.filewritable(state_dir) == 2 then
    ok("State directory is writable for optional state storage")
  else
    warn("State directory may not be writable: " .. state_dir)
  end

  ok("Default state path: " .. store.default_path())
end

return M
