utils = {
  pprint = require 'pprint',
}

local known_deps = require 'known_deps'

function utils.exec_silent(cmd, ...)
  local formatted = cmd:format(...)
  if os.host() == "windows" then
    return os.execute(formatted .. ' >nul 2>nul')
  else
    return os.execute(formatted .. '  > /dev/null 2>&1')
  end
end

function utils.has_in_path(executable)
  if os.host() == "windows" then
    return utils.exec_silent('where ' .. executable)
  else
    return utils.exec_silent('which ' .. executable)
  end 
end

function utils.ensure_devtools_shell()
  if not os.getenv('VSCMD_ARG_TGT_ARCH') then
    error("this script should be run from a VS Native Tools prompt!")
  end
end

function utils.ensure_executables_in_path(list)
  for _, exec in ipairs(list) do
    if not utils.has_in_path(exec) then
      error('you should have ' .. exec .. ' in your PATH!')
    end
  end
end

function utils.git_clean_on_rebuild()
  if rebuild then
    utils.ensure_executables_in_path({'git'})
    os.execute('git clean -dqxf')
  end
end

function utils.is_rebuild()
  return _OPTIONS["rebuild"] == "true"
end

function utils.ensure_table_has_typed_fields(table_name, t, fields)
  if type(t) ~= 'table' then error('you should provide a table!') end

  for _, field in ipairs(fields) do
    local name, _type = field[1], field[2]
    if type(t[name]) ~= _type then error(table_name .. 'should have ' .. name .. ' ' .. _type) end
  end
end

function utils.git_get_all_dirty_files(extensions)
  local staged    = os.outputof('git diff --name-only --diff-filter=d --cached')
  local unstaged  = os.outputof('git ls-files -m')
  local untracked = os.outputof('git ls-files --others --exclude-standard')
  local result = {}
  
  local parse_output = function(cmd_out) 
    for filepath in string.gmatch(cmd_out, "%S+") do 
      for _, ext in pairs(extensions) do
        if(path.getextension(filepath) == ext) then
          table.insert(result, filepath)
          break
        end
      end
    end
  end
  parse_output(staged)
  parse_output(unstaged)
  parse_output(untracked)

  return result
end

function utils.id() end

function utils.get_all_sources(settings)
  local allFiles = {}
  for _, ext in ipairs(settings.source_extensions) do
      local pattern = settings.paths.modules .. "/**" .. ext
      local files = os.matchfiles(pattern)
      for _, file in ipairs(files) do
          table.insert(allFiles, file)
      end
  end
  return allFiles
end


function utils.create_basic_actions(settings)
  newaction {
    trigger = "clean",
    description = "Clean all generated build artifacts",
    onStart = function() os.rmdir(settings.paths.build) end
  }
  
  local has_clangformat = settings.paths.ClangFormatExecutable ~= nil and os.isfile(settings.paths.ClangFormatExecutable) 
  
  if (not has_clangformat) and utils.has_in_path('clang-format') then
    settings.paths.ClangFormatExecutable = 'clang-format'
    has_clangformat = true
  end

  if has_clangformat then 
    newaction {
      trigger = "format",
      description = "Apply .clang-format style to dirty source files or --all if specified.",
      onStart = function()
        local files_to_format = nil
        if _OPTIONS["all"] then
          files_to_format = utils.get_all_sources(settings)
        else
          files_to_format = utils.git_get_all_dirty_files(settings.source_extensions)
        end
        local count = #files_to_format
        print('%\tStatus')
        for i, filepath in ipairs(files_to_format) do
          print( '' .. i .. '/' .. count .. '\tFormatting ' .. filepath)
          os.executef('%s -i -style=file -fallback-style=none %s', settings.paths.ClangFormatExecutable, filepath)
        end
      end
    }
  end
  
  newoption {
    trigger     = "all",
    description = "Apply the action to all files",
  }

  newoption {
    trigger     = "rebuild",
    value       = "boolean",
    description = "Rebuild from scratch",
    default     = "false",
    allowed = {
       { "true",    "True" },
       { "false",  "False" },
    }
  }

  newaction {
    trigger = "deps",
    description = "Initialize and build all dependencies",
    onStart = function()
      table.map_inplace(settings.paths, path.getabsolute)
      
      os.mkdir(settings.paths.built_deps.include)
      os.mkdir(settings.paths.built_deps.lib)

      os.chdir(settings.paths.deps)
            
      for _, dep in ipairs(settings.deps) do
        if known_deps[dep] == nil then error("unknown third-party dependency " .. dep) end
        local dir_changed = os.chdir(dep)
        utils.git_clean_on_rebuild()
        known_deps[dep]:build(settings.paths)
        if dir_changed then os.chdir('..') end
      end
    end
  }
    
end

-- built-in module extensions 

function table.map_inplace(table, func)
  local impl
  impl = function(t, f)
    for k, v in pairs(t) do
      if(type(v) == "table") then
        impl(v, f)
      else
        t[k] = f(v)
      end
    end
  end
  impl(table, func)
end

-- os.rmdir uses RemoveDirectoryW on windows, which removes actual contents of the junction smh.
-- TODO: investigate why cmd's rmdir works differently. BTW, rmdir from cygwin also works
--       differently as it's able to error out w/ 'not a directory' error.
function os.rmdir_native(dir)
  if not os.isdir(dir) then 
    premake.warn('trying to remove nonexistent directory %s...', dir)
    return
  end
  if os.host() == "windows" then
    os.executef('rmdir /Q /S "%s"', dir)
  else
    premake.warn('make sure rmdir_native works in a correct fashion')
    os.rmdir(dir)
  end
end

function os.mklink(target_path, link_path)
  local dir_mode = os.isdir(target_path)
  if not dir_mode and not os.isfile(target_path) then
    error('mklink: ' .. target_path .. " isn't a file or directory!")
  end

  if os.isfile(link_path) or os.isdir(link_path) then
    if dir_mode then
      os.rmdir_native(link_path) 
    else
      os.remove(link_path)
    end
  end
  
  if os.host() == "windows" then
    if dir_mode then
      utils.exec_silent('mklink /J "%s" "%s"', link_path, target_path)
    else
      utils.exec_silent('mklink /H "%s" "%s"', link_path, target_path)
    end
  else
    premake.error('mklink is unimplemented for this platform')
  end
end

function os.link_files_filtered(src_path, dst_path, included_exts, recursive)
  local pattern = (recursive ~= nil and recursive == false) and '/*' or '/**'
  for _, ext in ipairs(included_exts or {''}) do
    for _, f in ipairs(os.matchfiles(src_path .. pattern .. ext)) do
      local dst_dir = path.getdirectory(path.join(dst_path, f))
      if not os.isdir(dst_dir) then os.mkdir(dst_dir) end
      os.mklink(f, path.join(dst_path, f))
    end
  end
end

return utils