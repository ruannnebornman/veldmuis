local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.default_prog = { '/usr/bin/fish' }

config.colors = {
  background = '#1b120d',
  foreground = '#f3d7a0',
  cursor_bg = '#f6b73c',
  cursor_fg = '#1b120d',
  selection_bg = '#8f4b28',
  selection_fg = '#ffe4ad',
  scrollbar_thumb = '#c46a2b',

  ansi = {
    '#2a1a12', '#b5482d', '#c98725', '#d79a35',
    '#a6532f', '#b9653d', '#d8a15b', '#f0c982',
  },
  brights = {
    '#60402b', '#df6840', '#f0a62b', '#ffc95c',
    '#e47a3b', '#e18a5f', '#f0c27b', '#fff0c7',
  },

  tab_bar = {
    background = '#120b08',
    active_tab = {
      bg_color = '#c46a2b',
      fg_color = '#1b120d',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#3a2418',
      fg_color = '#c89a68',
    },
    inactive_tab_hover = {
      bg_color = '#6d3822',
      fg_color = '#f3d7a0',
    },
    new_tab = {
      bg_color = '#24150f',
      fg_color = '#d79a35',
    },
    new_tab_hover = {
      bg_color = '#8f4b28',
      fg_color = '#ffe4ad',
    },
  },
}

return config
