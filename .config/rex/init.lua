rex.bind("cmd+shift+h", "pane.focus", { direction = "left" })
rex.bind("cmd+shift+j", "pane.focus", { direction = "down" })
rex.bind("cmd+shift+k", "pane.focus", { direction = "up" })
rex.bind("cmd+shift+l", "pane.focus", { direction = "right" })
rex.unbind("alt+cmd+m")
rex.bind("cmd+shift+m", "pane.minimize_floating")
rex.bind("cmd+shift+o", "pane.minimize_all_floating")

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
