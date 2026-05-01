local M = {}

local fields = {
  "id",
  "kind",
  "label",
  "label_title",
  "replacement",
  "cwd",
  "repo_root",
  "git_branch",
  "git_commit",
  "file_path",
  "relative_path",
  "start_line",
  "end_line",
  "snippet",
  "comment",
  "timestamp",
}

local function joinpath(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end
  return table.concat({ ... }, "/")
end

local function portable(annotation)
  local item = {}
  for _, field in ipairs(fields) do
    if annotation[field] ~= nil then
      item[field] = annotation[field]
    end
  end
  return item
end

local function portable_list(items)
  return vim.tbl_map(portable, items or {})
end

function M.default_path()
  return joinpath(vim.fn.stdpath("state"), "annotator.nvim", "annotations.json")
end

function M.load(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "Could not read Annotator annotations state"
  end

  local text = table.concat(lines, "\n")
  if text:gsub("%s+", "") == "" then
    return {}
  end

  local decoded_ok, decoded = pcall(vim.json.decode, text)
  if not decoded_ok or type(decoded) ~= "table" then
    return nil, "Could not decode Annotator annotations state"
  end

  return portable_list(decoded)
end

function M.save(path, items)
  local dir = vim.fn.fnamemodify(path, ":h")
  local mkdir_ok = pcall(vim.fn.mkdir, dir, "p")
  if not mkdir_ok then
    return false, "Could not create Annotator annotations state directory"
  end

  local encode_ok, encoded = pcall(vim.json.encode, portable_list(items))
  if not encode_ok then
    return false, "Could not encode Annotator annotations state"
  end

  local tmp = path .. ".tmp"
  local write_ok, write_result = pcall(vim.fn.writefile, { encoded }, tmp)
  if not write_ok or write_result ~= 0 then
    return false, "Could not write Annotator annotations state"
  end

  local rename_ok, rename_result = pcall(vim.fn.rename, tmp, path)
  if not rename_ok or rename_result ~= 0 then
    return false, "Could not replace Annotator annotations state"
  end

  return true
end

return M
