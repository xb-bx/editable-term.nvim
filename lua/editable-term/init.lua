local M = {}
local function update_line(buf, chan, ln)
    local bufinfo = M.buffers[buf]
    if not bufinfo.promt_cursor then
        return
    end
    vim.fn.chansend(chan, vim.api.nvim_replace_termcodes('<C-U>', true, false, true))
    local line = ln or vim.api.nvim_get_current_line()
    vim.fn.chansend(chan, line:sub(bufinfo.promt_cursor[2] + 1))
    local cursor = vim.api.nvim_win_get_cursor(0)
    local p = vim.api.nvim_replace_termcodes('<C-a>', true, false, true) ..
    vim.fn['repeat'](vim.api.nvim_replace_termcodes('<C-f>', true, false, true), cursor[2] - bufinfo.promt_cursor[2])
    vim.fn.chansend(chan, p)
    M.buffers[buf].waiting = true
    vim.defer_fn(function()
        M.buffers[buf].waiting = false
    end, 50)
end
local function get_term_cursor() 
    local prevcursor = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_feedkeys('i', 'x', false)
    vim.schedule(function ()
        local cursor = vim.api.nvim_win_get_cursor(0)
        vim.api.nvim_input('<C-\\><C-N>')
    end)
end 
local function set_term_cursor(cursor)
    local bufinfo = M.buffers[vim.api.nvim_get_current_buf()]
    local p = vim.api.nvim_replace_termcodes('<C-a>', true, false, true) ..
    vim.fn['repeat'](vim.api.nvim_replace_termcodes('<C-f>', true, false, true), cursor - bufinfo.promt_cursor[2])
    vim.fn.chansend(vim.bo.channel, p)
end
M.setup = function()
    M.buffers = {}
    vim.api.nvim_create_autocmd('TermOpen', {
        group = vim.api.nvim_create_augroup('editable-term', { clear = true }),
        callback = function(args)
            local editgroup = vim.api.nvim_create_augroup('editable-term-text-change', { clear = true })
            M.buffers[args.buf] = { leaving_term = true }
            vim.keymap.set('n', 'A', function()
                local bufinfo = M.buffers[args.buf]
                local line = vim.api.nvim_get_current_line()
                line = line:sub(bufinfo.promt_cursor[2])
                local start, ent = line:find('%s*$')
                local p = vim.api.nvim_replace_termcodes('<C-a>', true, false, true) ..
                vim.fn['repeat'](vim.api.nvim_replace_termcodes('<C-f>', true, false, true), start - 2)
                vim.fn.chansend(vim.bo.channel, p)
                vim.cmd [[ startinsert ]]
            end, {buffer = args.buf})
            vim.keymap.set('n', 'I', function()
                local line = vim.api.nvim_get_current_line()
                local bufinfo = M.buffers[args.buf]
                line = line:sub(bufinfo.promt_cursor[2])
                local _, ent = line:find('[^%s]')
                local p = vim.api.nvim_replace_termcodes('<C-a>', true, false, true) ..
                vim.fn['repeat'](vim.api.nvim_replace_termcodes('<C-f>', true, false, true), ent - 2)
                vim.fn.chansend(vim.bo.channel, p)
                vim.cmd [[ startinsert ]]
            end, {buffer = args.buf})
            vim.keymap.set('n', 'i', function()
                local line = vim.api.nvim_get_current_line()
                local cursor = vim.api.nvim_win_get_cursor(0)
                set_term_cursor(cursor[2])
                vim.cmd [[ startinsert ]]
            end, {buffer = args.buf})
            vim.keymap.set('n', 'a', function()
                local line = vim.api.nvim_get_current_line()
                local start, ent = line:find('%$ ')
                if not ent then
                    ent = 0
                end
                local cursor = vim.api.nvim_win_get_cursor(0)
                local p = vim.api.nvim_replace_termcodes('<C-a>', true, false, true) ..
                vim.fn['repeat'](vim.api.nvim_replace_termcodes('<C-f>', true, false, true), cursor[2] + 1 - ent)
                vim.fn.chansend(vim.bo.channel, p)
                vim.cmd [[ startinsert ]]
            end, {buffer = args.buf})
            vim.keymap.set('n', 'dd', function()
                M.buffers[args.buf].leaving_term = true 
                vim.fn.chansend(vim.bo.channel, vim.api.nvim_replace_termcodes('<C-U><C-A>', true, false, true))
                set_term_cursor(0)
            end)
            vim.api.nvim_create_autocmd('TextYankPost', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    local start = vim.api.nvim_buf_get_mark(args.buf, '[') 
                    local ent = vim.api.nvim_buf_get_mark(args.buf, ']') 
                    if start[1] ~= ent[1] then
                        vim.fn.chansend(vim.bo.channel, vim.api.nvim_replace_termcodes('<C-C>', true, false, true))
                    elseif vim.v.event.operator == 'c' then
                        local line = vim.api.nvim_get_current_line()
                        line = line:sub(1, start[2]) .. line:sub(ent[2] + 2)
                        update_line(args.buf, vim.bo.channel, line)
                        set_term_cursor(start[2])
                    end
                end
            })
            vim.api.nvim_create_autocmd('TextChanged', {
                buffer = args.buf,
                group = editgroup,
                callback = function(args)
                    local bufinfo = M.buffers[args.buf]
                    if not bufinfo.leaving_term and not bufinfo.waiting then
                        update_line(args.buf, vim.bo.channel)
                    else
                        bufinfo.leaving_term = false
                    end
                end
            })
            vim.api.nvim_create_autocmd('TermLeave', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    M.buffers[args.buf].leaving_term = true
                end
            })
            vim.api.nvim_create_autocmd('TermRequest', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    if string.match(args.data.sequence, '^\027]133;B') then
                        M.buffers[args.buf].promt_cursor = args.data.cursor
                    end
                end,
            })
            vim.api.nvim_create_autocmd('CursorMoved', {
                group = editgroup,
                buffer = args.buf,
                callback = function(args)
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local bufinfo = M.buffers[args.buf]
                    vim.bo.modifiable = bufinfo.promt_cursor ~= nil and cursor[1] == bufinfo.promt_cursor[1]
                end,
            })
        end
    })
end
return M
