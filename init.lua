local ps = { _VERSION = '0.1', utils = require 'modules.utils' }

local default_settings = {
  paths = {
    build = 'build/',
    modules = 'src/',
    deps = 'deps/',
    built_deps = {
      include = 'build/include/',
      lib = 'build/lib/',
    }
  },
  source_extensions = {".cpp", ".hpp", ".cxx", ".hxx", ".h"},
  configurations = {"Debug", "Release"},
  deps = {},
}

local function is_premake_call(name)
  return premake.field.get(name) ~= nil
end

local function generate_module_description(name, prefix)
  local premake_delayed_calls = {
    kind = "StaticLib",
    links = {},
  }

  local description_defaults = {
    name = name,
    dependson = {},
    additional_logic = utils.id,
    base_path = prefix .. name .. '/',
    custom_build_pipelines = {}
  }
  local description = {}
  local description_file = prefix .. name .. '/description.lua'
  description = table.merge(description_defaults, 
    os.isfile(description_file) and dofile(description_file) or {})
  
  for name, args in pairs(description) do
    -- collect premake api calls as delayed, but dependson needs special treatment, since each successive call
    -- to it overrides previous values
    if description_defaults[name] == nil and is_premake_call(name) and name ~= 'dependson' then
      premake_delayed_calls[name] = args
    end
  end
  description.premake_delayed_calls = premake_delayed_calls
  return description
end

local function generate_module_custom_build_pipeline(description, cbp)
  local name = description.name .. '/unnamed_pipeline'
  if type(cbp.name) == 'string' and cbp.name ~= '' then
    name = description.name .. '/' .. cbp.name .. '_pipeline'
  end
  if type(cbp.extension) ~= 'string' then 
    error('custom build pipeline requires a valid file extension!')
  end
  files { description.base_path .. "**" .. cbp.extension }
  filter { "files:**" .. cbp.extension }

  files { "**" .. cbp.extension }
  buildmessage (string.format("%s [using %s]", "%(Filename)%(Extension)", name))
  for i, stage in ipairs(cbp.stages) do
    buildoutputs (stage.outputs)
    buildcommands { stage.cmd .. ' ' .. stage.args }
  end
  filter {}
  
  if cbp.postbuildcommands ~= nil then
    postbuildcommands(cbp.postbuildcommands(description))
  end

  if cbp.cleancommands ~= nil then
    cleancommands(cbp.cleancommands(description))
  end
end

local function generate_module(description, paths, source_extensions)
  project(description.name)
  basedir(paths.build)
  debugdir(paths.build .. "bin")
  targetdir(paths.build .. "bin")
  objdir(paths.build .. "obj")

  for _, src_ext in ipairs(source_extensions) do
    files {description.base_path .. "**" .. src_ext}
  end

  for _, cbp in ipairs(description.custom_build_pipelines) do
    generate_module_custom_build_pipeline(description, cbp)
  end

  includedirs {paths.modules}
  externalincludedirs {paths.built_deps.include}
  syslibdirs {paths.built_deps.lib}
  externalincludedirs {path.getabsolute(paths.build) .. '/include'}

  if paths.VulkanSDK ~= nil then
    externalincludedirs {paths.VulkanSDK .. '/include'}
    syslibdirs{ paths.VulkanSDK .. '/Lib' }
  end

  dependson (description.dependson)
  links(description.links)

  for method, args in pairs(description.premake_delayed_calls) do
    _G[method](args)
  end
end

local function infer_solution_level_settings(module_descriptions)
  local startup_project = nil
  for name, desc in pairs(module_descriptions) do
    for method, args in pairs(desc.premake_delayed_calls) do
      if method == 'kind' and args:find('App') then
        if startup_project == nil then
          startproject(name)
          startup_project = name
        else
          premake.info("Startup project is set to '%s', but '%s' also has App kind.", startup_project, name)
        end
      end
    end
  end
end

function ps.generate(settings)
  if not premake or string.sub(premake._VERSION, 1, 1) ~= '5' then
    error('You should only use premake_scaffold from premake5!')
  end

  if settings == nil then
    settings = {}
  end
  if type(settings) ~= 'table' then
    error('You should provide settings table!')
  end

  local premake_delayed_calls = {}
  for name, args in pairs(settings) do
    if is_premake_call(name) then
      premake_delayed_calls[name] = args
      settings[name] = nil
    end
  end
  local S = table.merge(default_settings, settings)
  utils.create_basic_actions(S)

  -- setup up solution level settings
  architecture "x86_64"
  cppdialect "C++latest" 
  language "C++"
  configurations(S.configurations)
  basedir(S.paths.build)
  warnings "Extra"

  filter "system:windows"
  flags 
  { 
    "FatalWarnings", 
    "FatalLinkWarnings", 
    "MultiProcessorCompile", 
    "UndefinedIdentifiers" 
  }
  buildoptions { "/permissive-", "/await", "/Zc:__cplusplus" }

  filter { "system:windows" }
    disablewarnings
    {
      "4127", -- conditional expression is constant
      "4275", -- non-dll interface class used as base for dll-interface class
      "5054", -- operator '|': deprecated between enumerations of different types
      "4201", -- non-standard: nameless struct used (typically in a union)
    }
    defines
    {
      "NOMINMAX",
      "_CRT_SECURE_NO_WARNINGS",
    }
  filter { "configurations:Debug", "system:windows" }
    disablewarnings  -- disable annoying warnings during prototyping
    { 
      "4100",
    }
    symbols "FastLink"
    runtime "Debug"
    defines { "DEBUG" }
    targetsuffix "d"
  filter { "configurations:Release", "system:windows" }
    defines { "NDEBUG" }
    runtime "Release"
    optimize "On"
  filter {}

  for method, args in pairs(premake_delayed_calls) do
    _G[method](args)
  end

  -- setup dependency chain and generate projects based on modules' descriptions
  local module_descriptions = {}
  for _, module_path in ipairs(os.matchdirs(S.paths.modules .. '*')) do
    local module_name = path.getname(module_path)
    local desc = generate_module_description(module_name, S.paths.modules)
    module_descriptions[desc.name] = desc
    for name, desc in pairs(module_descriptions) do
      for _, link in ipairs(desc.premake_delayed_calls.links) do
        if module_descriptions[link] ~= nil then
          desc.dependson[#desc.dependson + 1] = link
        end
      end
    end
  end
  infer_solution_level_settings(module_descriptions)
  for _, desc in pairs(module_descriptions) do
    generate_module(desc, S.paths, S.source_extensions) 
  end
end

return ps