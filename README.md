# editable-term.nvim

### This plugin allows you to edit terminal promt as if it was a regular buffer.  

Almost **every** action is supported(except for undo/redo and replace mode), even actions from plugins such as 'ds' from [nvim-surround](https://github.com/kylechui/nvim-surround)

![demo](demo/demo.gif)

### Requirements
- Neovim 0.11+


### Installation
via lazy.nvim
```lua
{
    'xb-bx/editable-term.nvim',
    config = true,
}
```

### Configuration
By default the plugin only detects [OSC 133](https://gitlab.freedesktop.org/Per_Bothner/specifications/-/blob/master/proposals/semantic-prompts.md) promt lines but you can extend it to support REPLs that dont support OSC 133.
```lua
local editableterm = require('editable-term')  
editableterm.setup({
    promts = {
        ['^%(gdb%) '] = {}, -- gdb promt
        ['^>>> '] = {},     -- python PS1
        ['^... '] = {},     -- python PS2
        ['some_other_prompt'] = {
            keybinds = {
                clear_current_line = 'keys to clear the line',   
                goto_line_start = 'keys to goto line start',   
                forward_char = 'keys to move forward one character',   
            }
        },
    },
    wait_for_keys_delay = 50, -- amount of miliseconds to wait for shell to process keys 
})
```
#### Default keybinds
```lua
{
    clear_current_line = '<C-e><C-u>',
    forward_char = '<C-f>',
    goto_line_start = '<C-a>',
}
```
### Enable shell's vi-mode only when not in nvim 
add following to your shell's rc file
```sh
if [ -z "$NVIM" ]; then
    set -o vi
fi
```
