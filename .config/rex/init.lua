rex.bind("cmd+shift+h", "pane.focus", { direction = "left" })
rex.bind("cmd+shift+j", "pane.focus", { direction = "down" })
rex.bind("cmd+shift+k", "pane.focus", { direction = "up" })
rex.bind("cmd+shift+l", "pane.focus", { direction = "right" })
rex.unbind("alt+cmd+m")
rex.bind("cmd+shift+m", "pane.minimize_floating")
rex.bind("cmd+shift+o", "pane.minimize_all_floating")
rex.bind("cmd+d", "pane.split", { direction = "right" })
rex.bind("cmd+s", "pane.split", { direction = "down" })

local pane_bounds = require("pane-bounds")

rex.action({
    name = "float_top_right",
    title = "Float Pane at Top Right",
    run = function(ctx)
        if not ctx.session_id or not ctx.block_id then
            error("Run this action from a pane in a Rex session", 0)
        end
        local result, err = rex.session.float_block({
            block_id = ctx.block_id,
            bounds = pane_bounds.popout,
        })
        if err ~= nil then error(err, 0) end
        return result
    end,
})
rex.bind("cmd+shift+d", "float_top_right")

local worktree = require("worktree")

rex.action({
    name = "new_worktree",
    title = "New Worktree Tab",
    args = { branch = "string?" },
    run = function(ctx, args)
        return worktree.open_prompt(ctx, "create", args.branch)
    end,
})
rex.bind("cmd+shift+t", "new_worktree")

rex.action({
    name = "cleanup_worktree",
    title = "Clean Up Worktree",
    run = function(ctx)
        return worktree.open_prompt(ctx, "close")
    end,
})
rex.bind("cmd+shift+c", "cleanup_worktree")
