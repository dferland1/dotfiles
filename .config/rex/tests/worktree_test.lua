local directory = assert(arg[0]:match("^(.*)/tests/[^/]+$"))
local actions = {}
local windows, layers, selections = 0, 0, 0
local allowed = false

rex = {
    bind = function() end,
    unbind = function() end,
    action = function(action) actions[action.name] = action end,
    exec = function(command, options)
        assert(command[3] == 'exec fish "$WORKTREE_SCRIPT" --check')
        assert(options.cwd == "/repo")
        assert(options.env.WORKTREE_SCRIPT:match("/fish/scripts/worktree%-create.fish$"))
        return { ok = allowed, stderr = "Create worktrees from the main checkout" }
    end,
    block = { call = function() return { foreground = { cwd = "/repo" } } end },
    json = { encode = function() return "{}" end },
    layout = { block = function(block) return block end },
    session = {
        describe_block = function() return { block = { window_id = "window:source" } } end,
        new_window = function(options)
            assert(allowed and options.focus == true)
            assert(options.window_label == "New worktree")
            windows = windows + 1
            return { window_id = "window:prompt" }
        end,
        new_layer = function()
            layers = layers + 1
            return { layer_id = "layer:confirmation" }
        end,
    },
    client = { queue = function(action, args)
        assert(action == "session.select")
        assert(args.session_id == "session:test" and args.window_id == "window:prompt")
        selections = selections + 1
    end },
}

dofile(directory .. "/init.lua")
local ctx = { session_id = "session:test", block_id = "block:source", origin = "key" }
local ok, err = pcall(actions.new_worktree.run, ctx, {})
assert(not ok and tostring(err):find("from the main checkout"))
assert(windows == 0 and layers == 0 and selections == 0)
allowed = true
actions.new_worktree.run(ctx, {})
assert(windows == 1 and layers == 0 and selections == 1)
ctx.origin = "cli"
actions.new_worktree.run(ctx, {})
assert(windows == 2 and selections == 1)
actions.cleanup_worktree.run(ctx)
assert(layers == 1 and windows == 2)
print("PASS: preflight before UI, new-tab prompt, app selection for shortcuts, no CLI Remote Control, floating cleanup")

local minimized, focused, closed = 0, false, false
rex = {
    args = { operation = "create", branch = "feature/test", cwd = "/repo", config_home = "/config" },
    session_id = "session:test",
    block_id = "block:prompt",
    exec = function() return { ok = true, stderr = "", stdout = "metadata" } end,
    json = { decode = function()
        return { worktree = "/worktree", project = "repo", branch = "feature/test" }
    end },
    layout = { block = function(block) return block end },
    session = {
        describe_block = function() return { block = { window_id = "window:prompt" } } end,
        new_window = function() error("The worker must reuse the prompt tab") end,
        detach_block = function() error("The prompt must stay in its tab") end,
        focus_window = function() error("The worker must not switch tabs") end,
        set_window_label = function(options)
            assert(options.window_id == "window:prompt" and options.label == "repo/feature/test")
            return {}
        end,
        new_split = function(options)
            assert(options.anchor_id == "block:prompt" and options.focus == true)
            assert(options.layout.options.cwd == "/worktree")
            return { block_ids = { "block:shell" } }
        end,
        new_layer = function(options)
            assert(options.window_id == "window:prompt" and options.focus == false)
            return { layer_id = "layer:" .. options.layout.label }
        end,
        focus_block = function(options)
            assert(options.block_id == "block:shell" and minimized == 2)
            focused = true
            return {}
        end,
    },
    call = function(method, options)
        if method == "session.set_layer_state" then
            assert(options.state == "minimized")
            minimized = minimized + 1
        elseif method == "block.close" then
            assert(options.block_id == "block:prompt" and focused)
            closed = true
        else
            error(method)
        end
        return {}
    end,
}

dofile(directory .. "/worktree.lua")
assert(minimized == 2 and focused and closed)
print("PASS: worker reuses prompt tab, starts shell and minimized tools, then closes only prompt pane")
