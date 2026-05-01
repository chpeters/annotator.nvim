local annotations = require("annotator")
local state = require("annotator.state")

local function fail(message)
  error(message, 2)
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    fail((message or "values differ") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
  end
end

local function assert_contains(haystack, needle, message)
  if not haystack:find(needle, 1, true) then
    fail((message or "missing text") .. ": " .. needle)
  end
end

local function by_kind(items, kind)
  for _, annotation in ipairs(items) do
    if (annotation.kind or "comment") == kind then
      return annotation
    end
  end
  fail("missing annotation kind: " .. kind)
end

local function confirm_replacement(text)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))

  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.lhs == "<CR>" and type(mapping.callback) == "function" then
      mapping.callback()
      return
    end
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
  vim.cmd.redraw()
end

local storage_path = vim.fn.tempname() .. ".json"

vim.opt.swapfile = false
vim.notify = function() end
vim.ui.input = function(_, callback)
  callback("persistent smoke annotation")
end
vim.ui.select = function(items, _, callback)
  callback(items[1])
end

annotations.setup({
  mappings = false,
  storage = "state",
  storage_path = storage_path,
  labels = {
    { id = "clarify", title = "Clarify", comment = "Clarify this point." },
  },
  hooks = {
    export = function(ctx)
      ctx.clear_exported()
    end,
  },
})

vim.cmd.edit("README.md")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("AnnotatorAdd")
vim.cmd("2,3AnnotatorSuggest")
confirm_replacement("persistent replacement")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("AnnotatorLabel")
vim.cmd("5AnnotatorMarkDelete")

assert_equal(state.count(), 4, "typed commands should create persisted annotations")
assert_equal(vim.fn.filereadable(storage_path), 1, "annotation state should be written")

local saved = table.concat(vim.fn.readfile(storage_path), "\n")
assert_contains(saved, "persistent smoke annotation")
assert_equal(saved:find("bufnr", 1, true), nil, "state should not persist buffer ids")
assert_equal(saved:find("extmark_id", 1, true), nil, "state should not persist extmark ids")

local decoded = vim.json.decode(saved)
assert_equal(by_kind(decoded, "comment").comment, "persistent smoke annotation", "state should persist comments")
assert_equal(by_kind(decoded, "suggest").replacement, "persistent replacement", "state should persist replacements")
assert_equal(by_kind(decoded, "label").label, "clarify", "state should persist labels")
assert_equal(by_kind(decoded, "delete").comment, "Remove this text.", "state should persist delete comments")

state.configure({ on_change = nil })
state.replace({})
assert_equal(state.count(), 0, "test should clear in-memory annotations before reload")

annotations.setup({
  mappings = false,
  storage = "state",
  storage_path = storage_path,
})

assert_equal(state.count(), 4, "setup should load stored annotations")
assert_contains(annotations.render(), "persistent smoke annotation")
assert_contains(annotations.render(), "[suggest] lines 2-3")
assert_contains(annotations.render(), "persistent replacement")
assert_contains(annotations.render(), "[label:clarify] line 4")
assert_contains(annotations.render(), "[delete] line 5")

vim.cmd("AnnotatorExport")
assert_equal(state.count(), 0, "export hook should clear loaded annotations")

local cleared = vim.json.decode(table.concat(vim.fn.readfile(storage_path), "\n"))
assert_equal(#cleared, 0, "state file should be cleared after export")

vim.fn.delete(storage_path)
