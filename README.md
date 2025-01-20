# bedrock.nvim

What is harder than obsidian in minecraft?

[bedrock.nvim](https://github.com/nilszeilon/bedrock.nvim) is like [obsidian.md](https://obisidian.md) but for nvim.

## Features

1. Semantic search of your notes 🔍
2. Linking between your notes 🔗

## Prerequisites

- Neovim 0.8+
- SQLite3 installed on your system
  - Ubuntu/Debian: `apt install sqlite3`
  - macOS: `brew install sqlite3`
  - Windows: Download from [SQLite website](https://www.sqlite.org/download.html)


## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
    'nilszeilon/bedrock.nvim',
    requires = {
        'kkharji/sqlite.lua',
        'nvim-lua/plenary.nvim',
    }
}
```

Using lazy.nvim

```lua
{
    'nilszeilon/bedrock.nvim',
    dependencies = {
        'kkharji/sqlite.lua',
        'nvim-lua/plenary.nvim',
    },
    config = function()
        require('bedrock').setup()
    end
}
```
