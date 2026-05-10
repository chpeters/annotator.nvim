local markdown = require("annotator.markdown")

local M = {}

local function snacks()
  if rawget(_G, "Snacks") then
    return Snacks
  end

  local ok, mod = pcall(require, "snacks")
  if ok then
    return mod
  end
  return nil
end

local function level(name)
  return vim.log.levels[(name or "info"):upper()] or vim.log.levels.INFO
end

local function jump(annotation)
  vim.cmd.edit(vim.fn.fnameescape(annotation.file_path))
  vim.api.nvim_win_set_cursor(0, { annotation.start_line, 0 })
  vim.cmd("normal! zz")
end

local function kind_label(annotation)
  local kind = annotation.kind or "comment"
  if kind == "label" and annotation.label then
    return "label:" .. annotation.label
  end
  return kind
end

function M.notify(message, kind)
  vim.schedule(function()
    local opts = { title = "Annotator annotations" }
    if kind == "error" or kind == "warn" then
      opts.timeout = 10000
    end
    vim.notify(message, level(kind), opts)
  end)
end

function M.input(prompt, default, callback)
  if type(default) == "function" then
    callback = default
    default = nil
  end

  vim.ui.input({ prompt = prompt, default = default }, function(value)
    callback(value)
  end)
end

function M.select(prompt, items, format_item, callback)
  vim.ui.select(items, {
    prompt = prompt,
    format_item = format_item,
  }, function(item)
    callback(item)
  end)
end

local function split_lines(text)
  return vim.split(text or "", "\n", { plain = true })
end

function M.edit_replacement(opts, callback)
  opts = opts or {}

  local previous_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = opts.filetype or ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, split_lines(opts.text))

  local width = math.min(math.max(40, math.floor(vim.o.columns * 0.8)), 100)
  local height = math.min(math.max(5, #split_lines(opts.text)), math.max(5, math.floor(vim.o.lines * 0.5)))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = " " .. (opts.title or "Annotation") .. " ",
    title_pos = "center",
    style = "minimal",
  })

  local closed = false

  local function close()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_win_is_valid(previous_win) then
      vim.api.nvim_set_current_win(previous_win)
    end
  end

  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    close()
    callback(table.concat(lines, "\n"))
  end

  vim.keymap.set("n", "<CR>", confirm, { buffer = buf, nowait = true, desc = "Save annotation replacement" })
  vim.keymap.set("n", "<C-s>", confirm, { buffer = buf, nowait = true, desc = "Save annotation replacement" })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Cancel annotation replacement" })

  return { bufnr = buf, winid = win }
end

function M.annotations(items)
  if #items == 0 then
    M.notify("No pending Annotator annotations", "info")
    return
  end

  local picker_items = vim.tbl_map(function(annotation)
    local file = annotation.relative_path or annotation.file_path
    local range = annotation.start_line == annotation.end_line and tostring(annotation.start_line)
      or (annotation.start_line .. "-" .. annotation.end_line)

    return {
      text = file .. ":" .. range .. " [" .. kind_label(annotation) .. "] " .. annotation.comment,
      file = annotation.file_path,
      pos = { annotation.start_line, 0 },
      preview = { text = markdown.preview(annotation), ft = "markdown" },
      action = function()
        jump(annotation)
      end,
    }
  end, items)

  local snack = snacks()
  if snack and snack.picker then
    snack.picker.pick({
      title = "Annotator Annotations",
      items = picker_items,
      format = "text",
      preview = "preview",
      confirm = "item_action",
    })
    return
  end

  vim.fn.setqflist({}, " ", {
    nr = "$",
    title = "Annotator Annotations",
    items = vim.tbl_map(function(annotation)
      return {
        filename = annotation.file_path,
        lnum = annotation.start_line,
        end_lnum = annotation.end_line,
        text = annotation.comment,
      }
    end, items),
  })
  vim.cmd.copen()
end

return M
