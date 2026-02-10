-- Health check for viduct
-- Run with :checkhealth viduct

local M = {}

M.check = function()
  vim.health.start("viduct")

  -- Check Neovim version
  if vim.fn.has("nvim-0.8") == 1 then
    vim.health.ok("Neovim 0.8+ detected")
  else
    vim.health.error("Neovim 0.8+ required")
  end

  -- Check Node.js
  local node_version = vim.fn.system("node --version 2>/dev/null"):gsub("%s+", "")
  if node_version ~= "" and node_version:match("^v%d+") then
    vim.health.ok("Node.js detected: " .. node_version)
  else
    vim.health.error("Node.js not found", { "Install Node.js 18+ from https://nodejs.org" })
  end

  -- Check node-helper path
  local source = debug.getinfo(1).source
  local plugin_path = ""
  if source:sub(1, 1) == "@" then
    plugin_path = source:sub(2):gsub("/lua/viduct/health%.lua$", "")
  end

  local helper_path = plugin_path .. "/node-helper/index.js"
  if vim.fn.filereadable(helper_path) == 1 then
    vim.health.ok("Node helper found: " .. helper_path)
  else
    vim.health.error("Node helper not found at: " .. helper_path)
  end

  -- Check if node_modules installed
  local node_modules = plugin_path .. "/node-helper/node_modules"
  if vim.fn.isdirectory(node_modules) == 1 then
    vim.health.ok("Node dependencies installed")
  else
    vim.health.error("Node dependencies not installed", {
      "Run: cd " .. plugin_path .. "/node-helper && npm install",
    })
  end
end

return M
