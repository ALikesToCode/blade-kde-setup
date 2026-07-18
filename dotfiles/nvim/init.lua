-- Fast, plugin-free Neovim baseline matching the Artix dark blue/green theme.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 6
opt.sidescrolloff = 8
opt.wrap = false
opt.breakindent = true
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.termguicolors = true

opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "split"
opt.splitbelow = true
opt.splitright = true

opt.expandtab = true
opt.shiftwidth = 4
opt.tabstop = 4
opt.softtabstop = 4
opt.smartindent = true

opt.undofile = true
opt.swapfile = false
opt.updatetime = 250
opt.timeoutlen = 400
opt.completeopt = { "menuone", "noselect", "popup" }

local undo_dir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(undo_dir, "p")
opt.undodir = undo_dir

vim.cmd.colorscheme("habamax")

local colors = {
  bg = "#05070a",
  surface = "#0d1117",
  surface2 = "#141b24",
  fg = "#dce8f5",
  muted = "#73869a",
  blue = "#38bdf8",
  green = "#50fa7b",
  yellow = "#ffd580",
  red = "#ff7a90",
}

local set_hl = vim.api.nvim_set_hl
set_hl(0, "Normal", { fg = colors.fg, bg = colors.bg })
set_hl(0, "NormalFloat", { fg = colors.fg, bg = colors.surface })
set_hl(0, "FloatBorder", { fg = colors.blue, bg = colors.surface })
set_hl(0, "CursorLine", { bg = colors.surface })
set_hl(0, "LineNr", { fg = colors.muted, bg = colors.bg })
set_hl(0, "CursorLineNr", { fg = colors.green, bg = colors.surface, bold = true })
set_hl(0, "Visual", { bg = "#173653" })
set_hl(0, "Search", { fg = colors.bg, bg = colors.yellow, bold = true })
set_hl(0, "IncSearch", { fg = colors.bg, bg = colors.green, bold = true })
set_hl(0, "Pmenu", { fg = colors.fg, bg = colors.surface })
set_hl(0, "PmenuSel", { fg = colors.bg, bg = colors.blue, bold = true })
set_hl(0, "StatusLine", { fg = colors.fg, bg = colors.surface2 })
set_hl(0, "StatusLineNC", { fg = colors.muted, bg = colors.surface })
set_hl(0, "WinSeparator", { fg = "#263545", bg = colors.bg })

vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight copied text",
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 180 })
  end,
})

local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "Quit window" })
map("n", "<C-h>", "<C-w>h", { desc = "Focus left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Focus lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Focus upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Focus right window" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Leave terminal mode" })
