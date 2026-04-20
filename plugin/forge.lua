vim.api.nvim_create_user_command('Forge', function(opts)
  require('forge.cmd').run(opts)
end, {
  bar = true,
  nargs = '*',
  range = true,
  complete = function(arglead, cmdline, cursorpos)
    return require('forge.cmd').complete(arglead, cmdline, cursorpos)
  end,
  desc = 'forge.nvim',
})
