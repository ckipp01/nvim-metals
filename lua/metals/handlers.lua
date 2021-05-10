local api = vim.api
local fn = vim.fn
local lsp = vim.lsp

local decoration = require("metals.decoration")
local diagnostic = require("metals.diagnostic")
local doctor = require("metals.doctor")
local log = require("metals.log")
local util = require("metals.util")

local M = {}

local decoration_namespace = api.nvim_create_namespace("metals_decoration")

-- Implementation of the `metals/quickPick` Metals LSP extension.
-- - https://scalameta.org/metals/docs/integrations/new-editor.html#metalsquickpick
M["metals/quickPick"] = function(_, _, resp)
  local ids = {}
  local labels = {}
  for i, item in pairs(resp.items) do
    table.insert(ids, item.id)
    table.insert(labels, i .. " - " .. item.label)
  end

  local choice = vim.fn.inputlist(labels)
  if choice == 0 then
    return { cancelled = true }
  else
    return { itemId = ids[choice] }
  end
end

-- Implementation of the `metals/inputBox` Metals LSP extension.
-- - https://scalameta.org/metals/docs/integrations/new-editor.html#metalsinputbox
M["metals/inputBox"] = function(_, _, resp)
  local name = vim.fn.input(resp.prompt .. ": ")

  if name == "" then
    return { cancelled = true }
  else
    return { value = name }
  end
end

-- Implementation of the `metals/executeClientCommand` Metals LSP extension.
-- - https://scalameta.org/metals/docs/integrations/new-editor.html#metalsexecuteclientcommand
M["metals/executeClientCommand"] = function(_, _, resp)
  if resp.command == "metals-goto-location" then
    lsp.util.jump_to_location(resp.arguments[1])
  elseif resp.command == "metals-doctor-run" then
    local args = fn.json_decode(resp.arguments[1])
    doctor.create(args)
  elseif resp.command == "metals-doctor-reload" then
    if doctor.is_open() then
      doctor.close()
      local args = fn.json_decode(resp.arguments[1])
      doctor.create(args)
    end
  elseif resp.command == "metals-diagnostics-focus" then
    diagnostic.open_all_diagnostics()
  else
    log.warn_and_show(string.format("Looks like nvim-metals doesn't handle %s yet.", resp.command))
  end
end

-- Callback function to handle `metals/status`
-- This simply sets a global variable `metals_status` which can be easily
-- picked up and used in a statusline.
-- Command and Tooltip are not covered from the spec.
-- - https://scalameta.org/metals/docs/editors/new-editor.html#metalsstatus
M["metals/status"] = function(_, _, params)
  if params.hide then
    util.metals_status()
  else
    util.metals_status(params.text)
  end
end

-- Function needed to implement the Decoration Protocol from Metals.
-- - https://scalameta.org/metals/docs/integrations/decoration-protocol.html
M["metals/publishDecorations"] = function(err, _, decorations)
  if err then
    log.error_and_show("Server error while publishing decorations. Please see logs for details.")
    log.error(err.message)
  end
  if not decorations then
    return
  end

  local uri = decorations.uri
  local bufnr = vim.uri_to_bufnr(uri)
  if not bufnr then
    log.warn_and_show(string.format("Couldn't find buffer for %s while publishing decorations.", uri))
    return
  end

  -- Unloaded buffers should not handle diagnostics.
  -- When the buffer is loaded, we'll call on_attach, which sends textDocument/didOpen.
  if not api.nvim_buf_is_loaded(bufnr) then
    return
  end

  local decoration_color = vim.g.metals_decoration_color or "Conceal"

  api.nvim_buf_clear_namespace(bufnr, decoration_namespace, 0, -1)
  decoration.clear_hover_messages()

  for _, deco in ipairs(decorations.options) do
    decoration.set_decoration(bufnr, decoration_namespace, deco, decoration_color)
    decoration.store_hover_message(deco)
  end
end

return M
