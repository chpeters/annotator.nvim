vim.opt.runtimepath:prepend(vim.fn.getcwd())

require("annotator").setup({
  mappings = false,
})
