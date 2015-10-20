--[[**************************************************************************
    *                                                                        *
    *    Copyright 2015, 2016 MetaStack Solutions Ltd.                       *
    *                                                                        *
    *  This file is distributed under the terms of the GNU General Public    *
    *  License version 3.0                                                   *
    *                                                                        *
    *  OPAM is distributed in the hope that it will be useful, but WITHOUT   *
    *  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *
    *  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public       *
    *  License for more details.                                             *
    *                                                                        *
    **************************************************************************]]

-- Translation of _opam_add_f _opam_commands from opam_completion.sh
local function opam_commands(cur, cmd)
  local scanning = false
  local result = {}

  for line in io.popen("opam " .. cmd .. " --help=groff 2>nul"):lines() do
    if scanning then
      local count = 0
      local cmd, _ = line:gsub("\\%-", "-")
      _, count, cmd = cmd:find("^\\fB([^, =]*)\\fR")
      if count ~= nil then
        table.insert(result, cmd)
      end
    end
    scanning = (scanning and (line:sub(1, 3) ~= ".SH")) or
               (line == ".SH COMMANDS")
  end
  clink.match_words(cur, result)
end

-- Translation of _opam_add_f _opam_flags from opam_completion.sh
local function opam_flags(cur, cmd)
  local result = {}

  for line in io.popen("opam " .. cmd .. " --help=groff 2>nul"):lines() do
    local flag = line:gsub("\\%-", "-")
    for flag in flag:gmatch("\\fB(-[^,= ]*)\\fR") do
      table.insert(result, flag)
    end
  end
  clink.match_words(cur, result)
end

-- Translation of _opam_add_f _opam_vars from opam_completion.sh
local function opam_vars(cur)
  local result = {}

  for line in io.popen("opam config list --safe 2>nul"):lines() do
    _, count, line = line:find("^([^# ][^ ]*)")
    if count ~= nil and line:sub(1, 4) ~= "PKG:" then
      table.insert(result, line)
    end
  end
  clink.match_words(cur, result)
end

-- Translation of _opam_add_f from opam_completion.sh
local function opam_f(cur, cmd)
  local result = {}
  for line in io.popen(cmd):lines() do
    table.insert(result, line)
  end
  clink.match_words(cur, result)
end

-- @@DRA Various commands taking too long to run for readline completion
-- Two possible fixes:
--   1. Speed the execution of the opam commands!
--   2. Failing that, cache the results in .opam and have completion read those
--        (mostly invalidation will occur during opam update which is already
--         slow)
-- This "solution" introduces two problems:
--   1. We're forced to write temporary files (because the opam processes take out long-lived locks otherwise)
--   2. New packages added during a session won't be detected (unless the user presses CTRL+Q)

local function cmd_to_lines(cmd, tmpname)
  local result = {}
  -- Annoyingly, os.tmpname() doesn't include $TMP on Windows!
  tmpname = clink.get_env("TMP") .. tmpname
  -- Use io.popen so as not to block while the command executes
  local handle = io.popen(cmd .. " > " .. tmpname)
  coroutine.yield()
  -- Ensure the process has finished
  for _ in handle:lines() do
  end
  io.close(handle)
  handle = io.open(tmpname)
  -- Now read the actual data
  for line in handle:lines() do
    table.insert(result, line)
  end
  io.close(handle)
  os.remove(tmpname)
  coroutine.yield(result)
end

local function wait_for(co)
  if type(co) == "thread" then
    local _, result = coroutine.resume(co)
    return result
  else
    return co
  end
end

local installed, _, _ = os.execute("opam help topics >nul 2>&1")

local opam_packages = coroutine.create(cmd_to_lines)
local opam_switches = coroutine.create(cmd_to_lines)

if installed then
  coroutine.resume(opam_packages, "opam list --safe -a -s 2>nul", os.tmpname())
  coroutine.resume(opam_switches, "opam switch list --safe -s -a 2>nul", os.tmpname())
end

-- Translation of _opam from opam_completion.sh
--   COMPREPLY   --> clink.match_words(...), or clink.match_files(...)
--   COMP_WORDS  --> parts
--   COMP_CWORD  --> #parts
--   compgen_opt --> clink.matches_are_files()
--   _opam_reply --> not required by clink (clink.match_words is cumulative)
local function opam_process_matches(parts)
  local cmd = parts[1]
  local subcmd = parts[2]
  local cur = parts[#parts]
  local prev = parts[#parts - 1]

  if #parts == 1 then
    -- At present, using opam help topics is pretty lazy, though at some point
    -- it may of course also include plug-ins.
    opam_f(cur, "opam help topics")
  elseif cmd == "install" or cmd == "show" or cmd == "info" then
    opam_packages = wait_for(opam_packages)
    clink.match_words(cur, opam_packages)
    if #parts > 2 then
      opam_flags(cmd)
    end
  elseif cmd == "reinstall" or cmd == "remove" or cmd == "uninstall" then
    opam_f(cur, "opam list --safe -i -s")
    if #parts > 2 then
      opam_flags(cmd)
    end
  elseif cmd == "upgrade" then
    opam_f(cur, "opam list --safe -i -s")
    opam_flags(cmd)
  elseif cmd == "switch" then
    if #parts == 2 then
      opam_commands(cur, cmd)
      opam_f(cur, "opam switch list --safe -s -i")
    elseif #parts == 3 then
      if subcmd == "install" or subcmd == "set" then
        opam_switches = wait_for(opam_switches)
        clink.match_words(cur, opam_switches)
      elseif subcmd == "remove" or subcmd == "reinstall" then
        opam_f(cur, "opam switch list --safe -s -i")
      elseif subcmd == "import" or subcmd == "export" then
        clink.match_files(cur .. "*", true)
        clink.matches_are_files();
      end
    else
      opam_flags(cur, cmd)
    end
  elseif cmd == "config" then
    if #parts == 2 then
      opam_commands(cur, cmd)
    else
      if #parts == 3 and subcmd == "var" then
        opam_vars(cur)
      else
        opam_flags(cur, cmd)
      end
    end
  elseif cmd == "repository" or cmd == "remote" then
    if #parts == 2 then
      opam_commands(cur, cmd)
    elseif #parts == 3 then
      if subcmd == "add" then
        if #parts > 3 then
          clink.match_files(cur .. "*", true)
          clink.matches_are_files();
        end
      elseif subcmd == "remove" or subcmd == "priority" or
             subcmd == "set-url" then
        opam_f(cur, "opam repository list --safe -s")
      else
        opam_flags(cur, cmd)
      end
    else
      opam_flags(cur, cmd)
      if subcmd == "set-url" or subcmd == "add" then
        clink.match_files(cur .. "*", true)
        clink.matches_are_files();
      end
    end
  elseif cmd == "update" then
    opam_f(cur, "opam repository list --safe -s")
    opam_f(cur, "opam pin list --safe -s")
  elseif cmd == "source" then
    opam_f(cur, "opam list --safe -A -s")
    opam_flags(cur, cmd)
  elseif cmd == "pin" then
    if #parts == 2 then
      opam_commands(cur, cmd)
    elseif #parts == 3 then
      if subcmd == "add" then
        opam_f(cur, "opam list --safe -A -s")
      elseif subcmd == "remove" or subcmd == "edit" then
        opam_f(cur, "opam pin list --safe -s")
      else
        opam_flags(cur, cmd)
      end
    else
      if subcmd == "add" then
        clink.match_files(cur .. "*", true)
        clink.matches_are_files();
      else
        opam_flags(cur, cmd)
      end
    end
  elseif cmd == "unpin" then
    if #parts == 2 then
      opam_f(cur, "opam pin list --safe -s")
    else
      opam_flags(cur, cmd)
    end
  else
    opam_commands(cmd)
    opam_flags(cmd)
  end

  return true
end

-- Adapted from argument_match_generator in arguments.lua (http://git.io/vWYrS).
-- The built-in arguments framework doesn't provide for lazy dynamic generation
-- (i.e. calling out to commands only once the sub-command is known).
-- This mechanism also allows for a closer emulation of bash programmatic
-- completion.
local function opam_match_generator(text, first, last)
  -- 8< -- arguments.lua
  local leading = rl_state.line_buffer:sub(1, first - 1):lower()

  -- Extract the command.
  local cmd_l, cmd_r
  if leading:find("^%s*\"") then
    -- Command appears to be surround by quotes.
    cmd_l, cmd_r = leading:find("%b\"\"")
    if cmd_l and cmd_r then
      cmd_l = cmd_l + 1
      cmd_r = cmd_r - 1
    end
  else
    -- No quotes so the first, longest, non-whitespace word is extracted.
    cmd_l, cmd_r = leading:find("[^%s]+")
  end

  if not cmd_l or not cmd_r then
    return false
  end

  local regex = "[\\/:]*([^\\/:.]+)(%.*[%l]*)%s*$"
  local _, _, cmd, ext = leading:sub(cmd_l, cmd_r):lower():find(regex)

  -- Check to make sure the extension extracted is in pathext.
  if ext and ext ~= "" then
    if not clink.get_env("pathext"):lower():match(ext.."[;$]", 1, true) then
      return false
    end
  end
  -- >8 -- arguments.lua

  if cmd ~= "opam" then
    return false
  end

  -- 8< -- arguments.lua
  -- Split the command line into parts.
  local str = rl_state.line_buffer:sub(cmd_r + 2, last)
  local parts = {}
  for _, sub_str in ipairs(clink.quote_split(str, "\"")) do
    -- Quoted strings still have their quotes. Look for those type of
    -- strings, strip the quotes and add it completely.
    if sub_str:sub(1, 1) == "\"" then
      local l, r = sub_str:find("\"[^\"]+")
      if l then
        local part = sub_str:sub(l + 1, r)
        table.insert(parts, part)
      end
    else
      -- Extract non-whitespace parts.
      for _, r, part in function () return sub_str:find("^%s*([^%s]+)") end do
        table.insert(parts, part)
        sub_str = sub_str:sub(r + 1)
      end
    end
  end

  -- If 'text' is empty then add it as a part as it would have been skipped
  -- by the split loop above.
  if text == "" then
    table.insert(parts, text)
  end
  -- >8 -- arguments.lua

  return opam_process_matches(parts)
end

if installed then
  clink.register_match_generator(opam_match_generator, 5)
end
