local wezterm = require("wezterm") --[[@as Wezterm]] --- this type cast invokes the LSP module for Wezterm
local dev = wezterm.plugin.require("https://github.com/chrisgve/dev.wezterm")

local pub = {}

--- checks if the user is on windows
local is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"
local separator = is_windows and "\\" or "/"

local function init()
	-- enable_sub_modules()
	local opts = {
		auto = true,
		keywords = { "resurrect", "wezterm" },
	}
	local plugin_path = dev.setup(opts)

	require("resurrect.state_manager").change_state_save_dir(plugin_path .. separator .. "state" .. separator)

	-- Export submodules
	pub.workspace_state = require("resurrect.workspace_state")
	pub.window_state = require("resurrect.window_state")
	pub.tab_state = require("resurrect.tab_state")
	pub.fuzzy_loader = require("resurrect.fuzzy_loader")
	pub.state_manager = require("resurrect.state_manager")
	pub.process_handlers = require("resurrect.process_handlers")
end

init()

--- One-call setup that configures everything for session persistence
--- and Claude Code restoration. Users call this from their wezterm.lua:
---
---   local resurrect = wezterm.plugin.require("https://github.com/YedPool/resurrect.wezterm")
---   resurrect.setup(config)  -- or resurrect.setup(config, opts)
---
--- Options (all optional):
---   periodic_interval  = 300    -- seconds between periodic saves
---   restore_delay      = 3      -- seconds to wait before sending restore commands
---   save_workspaces    = true
---   save_windows       = true
---   save_tabs          = true
---   keybindings        = true   -- add Alt+W/R/Shift+W/Shift+T bindings
---   status_bar         = true   -- show save time + tab titles in right status
---   claude_hooks       = true   -- auto-configure Claude Code SessionStart hook
---
---@param config table wezterm config_builder object
---@param opts? table optional overrides
function pub.setup(config, opts)
	opts = opts or {}
	local save_workspaces = opts.save_workspaces ~= false
	local save_windows = opts.save_windows ~= false
	local save_tabs = opts.save_tabs ~= false

	-- Claude Code session hook setup (idempotent)
	if opts.claude_hooks ~= false then
		pub.process_handlers.setup_claude_session_hooks()
	end

	-- Event-driven save: fires on pane/tab structure changes
	pub.state_manager.event_driven_save({
		save_workspaces = save_workspaces,
		save_windows = save_windows,
		save_tabs = save_tabs,
	})

	-- Periodic save as a safety net
	pub.state_manager.periodic_save({
		interval_seconds = opts.periodic_interval or 300,
		save_workspaces = save_workspaces,
		save_windows = save_windows,
		save_tabs = save_tabs,
	})

	-- Restore delay for process commands (shells need time to init)
	if opts.restore_delay then
		pub.tab_state.process_restore_delay_seconds = opts.restore_delay
	end

	-- Restore workspace on startup
	wezterm.on("gui-startup", pub.state_manager.resurrect_on_gui_startup)

	-- Status bar: show save time + tab titles
	if opts.status_bar ~= false then
		local last_save_time = nil

		wezterm.on("resurrect.state_manager.event_driven_save.finished", function()
			last_save_time = os.date("%H:%M:%S")
		end)

		wezterm.on("resurrect.state_manager.periodic_save.finished", function()
			last_save_time = os.date("%H:%M:%S")
		end)

		wezterm.on("update-right-status", function(window, pane)
			local titles = {}
			local mux_win = window:mux_window()
			for _, tab in ipairs(mux_win:tabs()) do
				local title = tab:get_title() or ""
				if title ~= "" then
					titles[title] = (titles[title] or 0) + 1
				end
			end

			local parts = {}
			for title, count in pairs(titles) do
				if count > 1 then
					table.insert(parts, title .. " x" .. count)
				else
					table.insert(parts, title)
				end
			end
			table.sort(parts)
			local title_str = table.concat(parts, ", ")

			local status = ""
			if last_save_time then
				status = "saved " .. last_save_time .. " | " .. title_str
			elseif title_str ~= "" then
				status = title_str
			end

			window:set_right_status(wezterm.format({
				{ Foreground = { AnsiColor = "Green" } },
				{ Text = status },
			}))
		end)
	end

	-- Keybindings for manual save/restore
	if opts.keybindings ~= false then
		local restore_opts = {
			relative = true,
			restore_text = true,
			on_pane_restore = pub.tab_state.default_on_pane_restore,
		}

		config.keys = config.keys or {}

		-- Alt+W: save workspace
		table.insert(config.keys, {
			key = "w",
			mods = "ALT",
			action = wezterm.action_callback(function(win, pane)
				pub.state_manager.save_state(
					pub.workspace_state.get_workspace_state()
				)
			end),
		})

		-- Alt+Shift+W: save window
		table.insert(config.keys, {
			key = "W",
			mods = "ALT|SHIFT",
			action = pub.window_state.save_window_action(),
		})

		-- Alt+Shift+T: save tab
		table.insert(config.keys, {
			key = "T",
			mods = "ALT|SHIFT",
			action = pub.tab_state.save_tab_action(),
		})

		-- Alt+R: fuzzy load saved state
		table.insert(config.keys, {
			key = "r",
			mods = "ALT",
			action = wezterm.action_callback(function(win, pane)
				pub.fuzzy_loader.fuzzy_load(win, pane, function(id, label)
					local state_type = id:match("^([^/\\]+)")
					local name = id:match("[/\\](.+)$")
					if name then
						name = name:gsub("%.json$", "")
					end
					if state_type == "workspace" then
						local state = pub.state_manager.load_state(name, "workspace")
						pub.workspace_state.restore_workspace(state, restore_opts)
					elseif state_type == "window" then
						local state = pub.state_manager.load_state(name, "window")
						pub.window_state.restore_window(pane:window(), state, restore_opts)
					elseif state_type == "tab" then
						local state = pub.state_manager.load_state(name, "tab")
						pub.tab_state.restore_tab(pane:tab(), state, restore_opts)
					end
				end)
			end),
		})
	end
end

return pub
