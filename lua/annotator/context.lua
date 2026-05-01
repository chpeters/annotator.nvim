local M = {}

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function run(args, cwd)
  if vim.system then
    local result = vim.system(args, { cwd = cwd, text = true }):wait()
    if result.code == 0 then
      return trim(result.stdout)
    end
    return nil
  end

  local command = table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
  local output = vim.fn.systemlist(command)
  if vim.v.shell_error == 0 then
    return trim(table.concat(output, "\n"))
  end
  return nil
end

local function dirname(path)
  if path == nil or path == "" then
    return vim.fn.getcwd()
  end
  return vim.fn.fnamemodify(path, ":p:h")
end

function M.git_root(path)
  return run({ "git", "-C", dirname(path), "rev-parse", "--show-toplevel" })
end

function M.git_branch(root)
  if not root then
    return nil
  end
  return run({ "git", "-C", root, "branch", "--show-current" }) or run({ "git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD" })
end

function M.git_commit(root)
  if not root then
    return nil
  end
  return run({ "git", "-C", root, "rev-parse", "HEAD" })
end

function M.relative_path(root, path)
  if not root or root == "" then
    return path
  end

  local normalized_root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")
  local normalized_path = vim.fn.fnamemodify(path, ":p")
  local prefix = normalized_root .. "/"

  if normalized_path:sub(1, #prefix) == prefix then
    return normalized_path:sub(#prefix + 1)
  end

  return path
end

return M
