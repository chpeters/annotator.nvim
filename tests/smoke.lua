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

local function assert_not_contains(haystack, needle, message)
  if haystack:find(needle, 1, true) then
    fail((message or "unexpected text") .. ": " .. needle)
  end
end

local function annotation_extmark_at(line)
  local namespace = vim.api.nvim_get_namespaces().annotator
  local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    if mark[2] == line - 1 then
      return mark[4]
    end
  end
  fail("no annotation extmark found at line " .. line)
end

local function find_kind(kind)
  for _, annotation in ipairs(state.snapshot()) do
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

local inputs = {}
local selected_label = 1

vim.opt.swapfile = false
vim.notify = function() end
vim.ui.input = function(_, callback)
  callback(table.remove(inputs, 1))
end
vim.ui.select = function(items, _, callback)
  callback(items[selected_label])
end

annotations.setup({
  mappings = false,
  display = {
    sign_text = "A>",
    virtual_text_prefix = " Annotation: ",
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
  labels = {
    { id = "clarify", title = "Clarify", comment = "Clarify this point." },
    { id = "simplify", title = "Simplify", comment = "Simplify this." },
  },
})

vim.cmd.edit("README.md")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
inputs = { "first annotation" }
vim.cmd("AnnotatorAdd")

assert_equal(state.count(), 1, "AnnotatorAdd should create a comment annotation")
assert_equal(find_kind("comment").comment, "first annotation")
assert_contains(annotations.render(), "## README.md")
assert_contains(annotations.render(), "first annotation")
local extmark = annotation_extmark_at(1)
assert_equal(extmark.sign_text, "C>", "configured comment sign text should be used")
assert_equal(extmark.virt_text[1][1], " Comment: first annotation", "configured comment prefix should be used")

inputs = { "edited annotation" }
vim.cmd("AnnotatorAdd")
assert_equal(state.count(), 1, "AnnotatorAdd should edit a comment annotation at the cursor")
assert_contains(annotations.render(), "edited annotation")
assert_not_contains(annotations.render(), "first annotation")

vim.cmd("2,3AnnotatorSuggest")
confirm_replacement("replacement line one\nreplacement line two")
local suggestion = find_kind("suggest")
assert_equal(suggestion.start_line, 2, "suggestion should preserve range start")
assert_equal(suggestion.end_line, 3, "suggestion should preserve range end")
assert_contains(suggestion.snippet, "Lightweight", "suggestion should store original snippet")
assert_equal(suggestion.replacement, "replacement line one\nreplacement line two", "suggestion should store replacement")
assert_equal(annotation_extmark_at(2).sign_text, "S>", "configured suggestion sign text should be used")

selected_label = 2
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("AnnotatorLabel")
local label = find_kind("label")
assert_equal(label.label, "simplify", "label annotation should use configured label")
assert_equal(label.comment, "Simplify this.", "label annotation should save exported label comment")
assert_equal(annotation_extmark_at(4).sign_text, "L>", "configured label sign text should be used")

vim.cmd("5AnnotatorMarkDelete")
local deletion = find_kind("delete")
assert_equal(deletion.start_line, 5, "delete annotation should preserve range")
assert_equal(deletion.comment, "Remove this text.", "delete annotation should use default removal comment")
assert_equal(annotation_extmark_at(5).sign_text, "D>", "configured delete sign text should be used")

local rendered = annotations.render()
assert_contains(rendered, "[comment] line 1", "comment markdown should include kind")
assert_contains(rendered, "[suggest] lines 2-3", "suggest markdown should include kind")
assert_contains(rendered, "Suggested replacement:", "suggest markdown should include replacement heading")
assert_contains(rendered, "[label:simplify] line 4", "label markdown should include label id")
assert_contains(rendered, "[delete] line 5", "delete markdown should include kind")

vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("AnnotatorEdit")
confirm_replacement("edited replacement")
assert_equal(find_kind("suggest").replacement, "edited replacement", "AnnotatorEdit should edit suggestion replacement")
assert_equal(state.count(), 4, "AnnotatorEdit should not duplicate suggestions")

selected_label = 1
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("AnnotatorEdit")
assert_equal(find_kind("label").label, "clarify", "AnnotatorEdit should reopen label picker")
assert_equal(state.count(), 4, "AnnotatorEdit should not duplicate labels")

vim.api.nvim_win_set_cursor(0, { 5, 0 })
inputs = { "delete this section" }
vim.cmd("AnnotatorEdit")
assert_equal(find_kind("delete").comment, "delete this section", "AnnotatorEdit should edit delete comments")

vim.cmd("AnnotatorDelete")
assert_equal(state.count(), 3, "AnnotatorDelete should remove annotation at cursor, not create delete-kind annotations")
for _, annotation in ipairs(state.snapshot()) do
  assert_not_contains(annotation.kind or "comment", "delete", "delete-kind annotation should be removed")
end

local exported
annotations.setup({
  mappings = false,
  formatter = function(ctx)
    assert_equal(#ctx.annotations, 3, "formatter should receive typed annotations")
    assert_contains(ctx.default_format(ctx.annotations), "[suggest]", "formatter should expose default formatter")
    return "CUSTOM FORMAT\n" .. ctx.default_format(ctx.annotations)
  end,
  hooks = {
    export = function(ctx)
      exported = ctx
      assert_contains(ctx.markdown, "CUSTOM FORMAT", "custom formatter should override exported markdown")
      assert_contains(ctx.markdown, "[label:clarify]", "formatted markdown should include edited label")

      ctx.clear_exported()
      assert_equal(state.count(), 0, "clear_exported should remove exported annotations")

      ctx.clear_exported()
      assert_equal(state.count(), 0, "clear_exported should be idempotent")
    end,
  },
})

vim.cmd("AnnotatorExport")

if not exported then
  fail("AnnotatorExport did not call hooks.export")
end
