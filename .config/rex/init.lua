rex.bind("cmd+shift+h", "pane.focus", { direction = "left" })
rex.bind("cmd+shift+j", "pane.focus", { direction = "down" })
rex.bind("cmd+shift+k", "pane.focus", { direction = "up" })
rex.bind("cmd+shift+l", "pane.focus", { direction = "right" })
rex.unbind("alt+cmd+m")
rex.bind("cmd+shift+m", "pane.minimize_floating")

rex.action({
    name = "new_worktree",
    title = "New Worktree Tab",
    args = { branch = "string?" },
    run = function(ctx, args)
        if not ctx.session_id or not ctx.block_id then
            error("Run this action from a terminal in a Rex session", 0)
        end
        local process, err = rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id })
        if err ~= nil then error(err, 0) end
        local cwd = process.foreground and process.foreground.cwd
        if not cwd then error("Cannot determine the focused terminal's working directory", 0) end

        local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
        local script = config_home .. "/fish/scripts/worktree-create.fish"

        if not args.branch or args.branch == "" then
            local source, source_err = rex.session.describe_block({ block_id = ctx.block_id })
            if source_err ~= nil then error(source_err, 0) end
            local prompt, prompt_err = rex.session.new_layer({
                window_id = source.block.window_id,
                bounds = { 0.25, 0.39, 0.5, 0.22 },
                focus = true,
                layout = rex.layout.block({
                    flavor = "com.superlogical.terminal.shell",
                    label = "New worktree",
                    options = {
                        cwd = cwd,
                        command = { "fish", script, "--prompt", ctx.block_id },
                        exit = { on_completion = true },
                    },
                }),
            })
            if prompt_err ~= nil then error(prompt_err, 0) end
            return prompt
        end

        local window, window_err = rex.session.new_window({
            window_label = "New worktree",
            layout = rex.layout.block({
                flavor = "com.superlogical.terminal.shell",
                options = {
                    cwd = cwd,
                    command = { "fish", script, args.branch },
                    exit = { on_completion = false },
                },
            }),
        })
        if window_err ~= nil then error(window_err, 0) end
        return window
    end,
})

rex.bind("cmd+shift+t", "new_worktree")

rex.action({
    name = "cleanup_worktree",
    title = "Clean Up Worktree",
    run = function(ctx)
        if not ctx.session_id or not ctx.block_id then
            error("Run this action from a terminal in a Rex session", 0)
        end
        local process, err = rex.block.call("com.superlogical.terminal", "process", { block_id = ctx.block_id })
        if err ~= nil then error(err, 0) end
        local cwd = process.foreground and process.foreground.cwd
        if not cwd then error("Cannot determine the focused terminal's working directory", 0) end
        local source, source_err = rex.session.describe_block({ block_id = ctx.block_id })
        if source_err ~= nil then error(source_err, 0) end
        local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")

        local prompt, prompt_err = rex.session.new_layer({
            window_id = source.block.window_id,
            bounds = { 0.2, 0.3, 0.6, 0.4 },
            focus = true,
            layout = rex.layout.block({
                flavor = "com.superlogical.terminal.shell",
                label = "Clean up worktree",
                options = {
                    cwd = cwd,
                    command = { "fish", config_home .. "/fish/scripts/worktree-close.fish" },
                    exit = { on_completion = false },
                },
            }),
        })
        if prompt_err ~= nil then error(prompt_err, 0) end
        return prompt
    end,
})
