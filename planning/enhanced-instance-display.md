# Plan: Enhanced Instance Selector Display

## Context

When WezTerm restarts, the instance selector shows saved sessions for restoration. Previously the display was nearly useless -- it only showed a timestamp and tab count like `Mar 13 16:45 -- Claude Code, PowerShell [2 tabs]`. With multiple instances of similar tab counts, the user couldn't tell them apart.

**Goal**: Make the selector show at a glance what each instance contains, so the user can confidently select the right ones.

## Desired Output

```
[ ] [Unnamed] Mar 13 16:45 - 2 windows, 7 tabs, 11 panes -- project-monopoly, Orahvision
[ ] [Orahvision] - 1 window, 3 tabs, 5 panes -- Orahvision
```

## Changes Made

### `plugin/resurrect/instance_manager.lua`

1. **Fixed `sanitize_display_string()`** - replaced Lua pattern with null byte (`\0`) in character class (which crashes Lua 5.1 on Windows) with a byte-level gsub callback that works on all Lua versions.

2. **Added helper functions:**
   - `count_panes_in_tree(node)` - Recursive count of pane tree nodes via `.right`/`.bottom` child pointers.
   - `count_panes(workspace_state)` - Traverses all windows/tabs, sums pane counts.
   - `collect_cwds_from_tree(node, cwds)` - Recursively collects CWD strings from pane tree.
   - `extract_project_name(cwd)` - Extracts project name from CWD path (looks for `/Code/`, strips ` Worktrees` suffix, falls back to last path component).
   - `extract_project_names(workspace_state)` - Collects all CWDs, extracts/deduplicates/sorts project names.

3. **Updated `save_instance()`** - Added new fields to `.meta` file:
   - `window_count`, `pane_count`, `projects`, `workspace`

4. **Rewrote `format_instance_summary()`** - New format with `[Name]` tag, window/tab/pane counts, and project names. Backward compatible with old `.meta` files.

5. **Exported `_test` table** for unit test access to internal helpers.

### `plugin/resurrect/spec/instance_manager_spec.lua`

- Updated `format_instance_summary` tests for new output format (7 tests)
- Added `count_panes_in_tree` tests (5 tests)
- Added `extract_project_name` tests (5 tests)
- Updated JSON parser stub to handle new meta fields

## Backward Compatibility

Old `.meta` files without `window_count`/`pane_count` degrade gracefully -- format falls back to showing just `tab_count`. Old instances age out via `retention_days` (7 days default).

## Verification

1. Restart WezTerm with multiple windows/tabs/panes
2. Wait for periodic save (or press Alt+S)
3. Check `.meta` files in `state/instances/` for new fields
4. Restart WezTerm again -- instance selector should show the new format
5. Verify old `.meta` files still display without errors
