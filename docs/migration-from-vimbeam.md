# Migrating from Vimbeam to Viduct

This guide covers all naming changes for code that integrates with this plugin.

## Rename Summary

| Old | New |
|-----|-----|
| **Package** | |
| `vimbeam` | `viduct` |
| `require('vimbeam')` | `require('viduct')` |
| **Vim Commands** | |
| `:BeamConnect` | `:DuctConnect` |
| `:BeamDisconnect` | `:DuctDisconnect` |
| `:BeamCreate` | `:DuctCreate` |
| `:BeamOpen` | `:DuctOpen` |
| `:BeamClose` | `:DuctClose` |
| `:BeamInfo` | `:DuctInfo` |
| `:BeamUserName` | `:DuctUserName` |
| `:BeamUserColor` | `:DuctUserColor` |
| `:BeamQuick` | `:DuctQuick` |
| **Highlight Groups** | |
| `VimbeamCursor*` | `ViductCursor*` |
| `VimbeamCursorLabel*` | `ViductCursorLabel*` |
| **Vim Globals** | |
| `g:loaded_vimbeam` | `g:loaded_viduct` |
| `g:vimbeam_server_url` | `g:viduct_server_url` |
| `g:vimbeam_debug` | `g:viduct_debug` |
| **Internal** | |
| `vimbeam_cursors` (namespace) | `viduct_cursors` |
| `Vimbeam_` (augroup prefix) | `Viduct_` |
| `vimbeam-user` (default name) | `viduct-user` |
| `beam-` (user ID prefix) | `duct-` |
| `~/.local/share/vimbeam/` | `~/.local/share/viduct/` |
| **npm** | |
| `vimbeam-helper` | `viduct-helper` |
| **GitHub** | |
| `computerscienceiscool/vimbeam` | `computerscienceiscool/viduct` |

## Plugin Manager Config

### lazy.nvim (before)
```lua
{
  'computerscienceiscool/vimbeam',
  build = 'cd node-helper && npm install',
  config = function()
    require('vimbeam').setup({ ... })
  end,
}
```

### lazy.nvim (after)
```lua
{
  'computerscienceiscool/viduct',
  build = 'cd node-helper && npm install',
  config = function()
    require('viduct').setup({ ... })
  end,
}
```

## Quick Search & Replace

For other codebases that reference this plugin, run these replacements:

```
vimbeam       → viduct
Vimbeam       → Viduct
VIMBEAM       → VIDUCT
BeamConnect   → DuctConnect
BeamDisconnect→ DuctDisconnect
BeamCreate    → DuctCreate
BeamOpen      → DuctOpen
BeamClose     → DuctClose
BeamInfo      → DuctInfo
BeamUserName  → DuctUserName
BeamUserColor → DuctUserColor
BeamQuick     → DuctQuick
beam-         → duct-        (user ID prefix only)
```

## Storage Migration

If you have existing Automerge data, move it:
```bash
mv ~/.local/share/vimbeam ~/.local/share/viduct
```
