# annotator.nvim

Make annotations without leaving Neovim. Use `annotator.nvim` to leave
comments, rejection/approval marks, labels or suggest rewrites as you work.
When you are ready, hand off batches of annotations to LLMs or export
elsewhere. Annotations are exported as structured Markdown by default, but they
can be configured via templates.

## Demo

https://github.com/user-attachments/assets/36310a11-6ce9-4da3-ba0b-e23d982fba87

## Features

- Annotate lines and ranges with typed comments, suggestions, deletion marks,
  labels, optional persistence, and export hooks.
- No required external dependencies. If Snacks is installed, `:AnnotatorList`
  uses its picker; otherwise it falls back to Neovim quickfix.
- Keep annotations in memory by default, or opt into state-backed storage to
  restore unexported annotations on restart.

## Install

With `vim.pack`:
```lua
vim.pack.add({
  { src = "https://github.com/chpeters/annotator.nvim" },
})

require("annotator").setup()
```

With `lazy.nvim`:
```lua
{
  "chpeters/annotator.nvim",
  opts = {},
}
```

## Example

Annotate the current line:
```vim
:AnnotatorAdd
```

Suggest a replacement for a range:
```vim
:12,16AnnotatorSuggest
```

Mark a line for deletion:
```vim
:AnnotatorMarkDelete
```

Annotate a visual selection with the default mapping:
```vim
<leader>aa
```

Then export everything:
```vim
:AnnotatorExport
```

By default, export copies Markdown like this to the system clipboard:
````markdown
Neovim annotations:

## lua/example.lua

- lines 12-16 (annotator-ann-1)

This branch should probably preserve the original error.

```lua
return Effect.fail(error)
```
````

The default exporter clears annotations after copying them.

## Requirements

- Neovim 0.10 or newer.
- No required plugin dependencies. Snacks is optional and only improves
  `:AnnotatorList`.
- Git is optional. When available, annotator.nvim records repository root,
  branch, commit, and relative paths for exports.
- The default exporter uses Neovim clipboard support. On macOS it can also fall
  back to `pbcopy`. On Linux or Windows, configure a Neovim clipboard provider
  or replace `hooks.export`.

## Configuration

Default configuration:
```lua
require("annotator").setup({
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
      comment = { sign_text = "C>", virtual_text_prefix = " Comment: " },
      suggest = { sign_text = "S>", virtual_text_prefix = " Suggest: " },
      delete = { sign_text = "D>", virtual_text_prefix = " Delete: " },
      label = { sign_text = "L>", virtual_text_prefix = " Label: " },
    },
  },
  labels = {
    { id = "explain", title = "Explain", comment = "Please explain this more clearly." },
    { id = "clarify", title = "Clarify", comment = "Please clarify this point." },
    { id = "simplify", title = "Simplify", comment = "Please simplify this." },
    { id = "tighten", title = "Tighten", comment = "Please tighten this up." },
    { id = "expand", title = "Expand", comment = "Please expand on this." },
  },
  formatter = nil,
  hooks = {
    export = require("annotator").exporters.copy_to_clipboard,
  },
})
```

Options:
- `mappings`: set to `false` to skip default mappings.
- `storage`: `"memory"` by default, or `"state"` to persist unexported annotations.
- `storage_path`: optional path override for `"state"` storage.
- `display`: sign and virtual text options.
- `display.kinds`: per-kind overrides for `comment`, `suggest`, `delete`, and `label`.
- `labels`: label picker entries with `id`, `title`, and exported `comment`.
- `formatter(ctx)`: optional function that returns exported Markdown.
- `hooks.export(ctx)`: function called by `:AnnotatorExport`.

State storage defaults to:
```text
stdpath("state")/annotator.nvim/annotations.json
```

State-backed storage writes only portable annotation fields. Neovim buffer IDs
and extmark IDs are recreated for open buffers and are not persisted.

Example display tweak:
```lua
require("annotator").setup({
  display = {
    kinds = {
      comment = { sign_text = "C>", virtual_text_prefix = " Comment: " },
      suggest = { sign_text = "S>", virtual_text_prefix = " Suggest: " },
      delete = { sign_text = "D>", virtual_text_prefix = " Delete: " },
      label = { sign_text = "L>", virtual_text_prefix = " Label: " },
    },
  },
})
```

## Export Hooks

By default, annotator.nvim renders generic Markdown grouped by file. Override
the rendered Markdown with `formatter(ctx)`:

```lua
require("annotator").setup({
  formatter = function(ctx)
    -- ctx.annotations: pending typed annotations
    -- ctx.default_format(ctx.annotations): built-in Markdown formatter
    return ctx.default_format(ctx.annotations)
  end,
})
```

Provide `hooks.export(ctx)` to integrate with your own workflow:
```lua
require("annotator").setup({
  hooks = {
    export = function(ctx)
      -- ctx.markdown: rendered Markdown
      -- ctx.annotations: pending annotations
      -- ctx.notify(message, kind): show a Neovim notification
      -- ctx.clear_exported(): clear exported annotations after success

      vim.fn.setreg("+", ctx.markdown)
      ctx.clear_exported()
      ctx.notify("Copied annotations", "info")
    end,
  },
})
```

If the hook does not call `ctx.clear_exported()`, annotations remain pending.

## Commands

- `:AnnotatorAdd`: add an annotation for the current line or command range.
- `:AnnotatorSuggest`: edit a replacement for the current line or command range.
- `:AnnotatorMarkDelete`: mark the current line or command range for removal.
- `:AnnotatorLabel`: choose a configured label for the current line or command range.
- `:AnnotatorEdit`: edit the annotation at the cursor.
- `:AnnotatorDelete`: delete the annotation at the cursor.
- `:AnnotatorList`: browse pending annotations.
- `:AnnotatorExport`: run the configured export hook.
- `:AnnotatorClear`: clear pending annotations.

Default mappings:

- Normal `<leader>aa`: add or edit the current-line annotation.
- Visual `<leader>aa`: annotate the selected lines.
- Normal `<leader>ax`: export annotations.

Typed commands do not claim additional default mappings; map them in your own
config if you use them often.

## Lua API

```lua
local annotations = require("annotator")

annotations.setup(opts)
annotations.add() -- current line
annotations.add_visual()
annotations.suggest()
annotations.suggest_visual()
annotations.mark_delete()
annotations.mark_delete_visual()
annotations.label()
annotations.label_visual()
annotations.edit()
annotations.delete()
annotations.list()
annotations.render() -- Markdown for all pending annotations
annotations.export()
annotations.clear()
```

## Behavior

- Adding on a line with an existing comment annotation edits that annotation
  instead of creating a duplicate comment.
- Adding a range edits an existing annotation of the same kind only when the file
  and range match exactly.
- `:AnnotatorSuggest` opens a floating scratch buffer prefilled with the selected
  text. Normal-mode `<CR>` or `<C-s>` saves; `q` cancels.
- `:AnnotatorLabel` uses `vim.ui.select`, so your existing UI plugin can style
  it without annotator.nvim depending on that plugin.
- `:AnnotatorEdit` is kind-aware: comments and deletion marks use
  `vim.ui.input`, suggestions reopen the replacement editor, and labels reopen
  the label picker.
- `:AnnotatorList` uses Snacks picker when available and falls back to quickfix.
- The default exporter copies Markdown to the system clipboard.

## License

MIT. See [LICENSE](LICENSE).
