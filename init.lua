require "modules.extensions"
require "modules.options"
require "modules.vcpkg"
require "modules.nuget"

local scaffold_source = debug.getinfo(1, "S").source:sub(2)
local scaffold_dir = path.getabsolute(path.getdirectory(scaffold_source))
local previous_dir = os.getcwd()
os.chdir(path.join(scaffold_dir, "deps/premake5-cuda"))
dofile("premake5-cuda.lua")
os.chdir(previous_dir)

local ps = {_VERSION = "0.2", utils = require "modules.utils"}

local default_settings = {
  paths = {
    build = "build/",
    modules = "src/",
    deps = "deps/",
    built_deps = {
      include = "build/include/",
      lib = "build/lib/"
    }
  },
  source_extensions = {".cpp", ".hpp", ".ipp", ".cxx", ".hxx", ".h", ".cc"},
  configurations = {"Debug", "Release"},
  deps = {},
  module_defaults = {
    kind = "ConsoleApp",
  }
}

local function capture_premake_calls(fullpath)
  local premake_api_calls = {
    "architecture",
    "cppdialect",
    "language",
    "configurations",
    "basedir",
    "warnings",
    "vcpkgstatic",
    "staticruntime",
    "filter",
    "flags",
    "nodefaultlib",
    "incrementallink",
    "buffersecuritycheck",
    "runtimechecks",
    "buildoptions",
    "disablewarnings",
    "defines",
    "symbols",
    "runtime",
    "targetsuffix",
    "optimize",
    "project",
    "basedir",
    "debugdir",
    "targetdir",
    "objdir",
    "files",
    "removefiles",
    "includedirs",
    "externalincludedirs",
    "syslibdirs",
    "dependson",
    "links",
    "kind",
    "postbuildcommands",
    "cleancommands",
    "buildoutputs",
    "buildcommands",
    "buildmessage",
    "startproject",
    "buildcustomizations",
    "cudaRelocatableCode",
    "cudaExtensibleWholeProgram",
    "cudaCompilerOptions",
    "cudaLinkerOptions",
    "cudaLinkFiles",
    "cudaFastMath",
    "cudaVerbosePTXAS",
    "cudaMaxRegCount",
    "cudaFiles",
    "cudaPTXFiles",
    "cudaKeep",
    "cudaPath",
    "cudaGenLineInfo",
    "cudaIntDir",
    "cudaKeepDir"
  }

  local env = {}
  for k, v in pairs(_G) do
    env[k] = v
  end

  local premake_calls = {}

  for _, name in ipairs(premake_api_calls) do
    env[name] = function(...)
      table.insert(premake_calls, {func = name, args = {...}})
    end
  end

  env._ENV = env
  env._SCRIPT = fullpath

  local f = io.open(fullpath, "r")
  if not f then
    return premake_calls
  end

  local content = f:read("*a")
  f:close()

  local wrapper = string.format([[
    local _ENV = ...
    %s
  ]], content)

  local chunk, err = load(wrapper, fullpath, "t", env)
  if not chunk then
    error("Failed to load file: " .. tostring(err))
  end

  local success, result = pcall(chunk, env)
  if not success then
    error("Failed to execute file: " .. tostring(result))
  end

  return premake_calls
end

local function generate_module_description(name, prefix, module_defaults)
  local abs_desc_path = path.join(path.join(path.join(_WORKING_DIR, prefix), name), "description.lua")
  local premake_delayed_calls = capture_premake_calls(abs_desc_path)

  local description_defaults = {
    name = name,
    dependson = {},
    additional_logic = utils.id,
    base_path = prefix .. name .. "/",
    custom_build_pipelines = {},
  }
  local description = table.merge(description_defaults, module_defaults)
  description = table.merge(description, premake_delayed_calls)

  description.premake_delayed_calls = premake_delayed_calls
  return description
end

local function generate_module_custom_build_pipeline(description, cbp)
  local name = description.name .. "/unnamed_pipeline"
  if type(cbp.name) == "string" and cbp.name ~= "" then
    name = description.name .. "/" .. cbp.name .. "_pipeline"
  end
  if type(cbp.extension) ~= "string" then
    error("custom build pipeline requires a valid file extension!")
  end
  files {description.base_path .. "**" .. cbp.extension}
  filter {"files:**" .. cbp.extension}

  files {"**" .. cbp.extension}
  buildmessage(string.format("%s [using %s]", "%(Filename)%(Extension)", name))
  for i, stage in ipairs(cbp.stages) do
    buildoutputs(stage.outputs)
    buildcommands {stage.cmd .. " " .. stage.args}
  end
  filter {}

  if cbp.postbuildcommands ~= nil then
    postbuildcommands(cbp.postbuildcommands(description))
  end

  if cbp.cleancommands ~= nil then
    cleancommands(cbp.cleancommands(description))
  end
end

local function module_relative_paths(description, values)
  local result = {}
  for _, value in ipairs(values) do
    if path.isabsolute(value) then
      result[#result + 1] = value
    else
      result[#result + 1] = path.getabsolute(path.join(description.base_path, value))
    end
  end
  return result
end

local function target_relative_paths(paths, values)
  local result = {}
  for _, value in ipairs(values) do
    if path.isabsolute(value) then
      result[#result + 1] = value
    else
      result[#result + 1] = path.getabsolute(path.join(paths.build .. "bin", value))
    end
  end
  return result
end

local function has_premake_call(description, func)
  for _, call in ipairs(description.premake_delayed_calls) do
    if call.func == func then
      return true
    end
  end
  return false
end

local function has_cuda_call(description)
  for _, call in ipairs(description.premake_delayed_calls) do
    if call.func:sub(1, 4) == "cuda" then
      return true
    end
  end
  return false
end

local function detect_cuda_version()
  local cudaPath = os.getenv("CUDA_PATH")
  if cudaPath ~= nil and cudaPath ~= "" then
    local nvcc = path.join(cudaPath, "bin/nvcc")
    return detectNvccVersion('"' .. nvcc .. '"')
  end

  return detectNvccVersion()
end

local function setup_cuda_module(description)
  if not has_cuda_call(description) then
    return
  end

  local cudaVersion = detect_cuda_version()
  if cudaVersion == 0 or cudaVersion == "0" or cudaVersion == nil then
    premake.warn("CUDA toolkit was not detected; skipping CUDA build customizations for " .. description.name)
    return
  end

  if not has_premake_call(description, "buildcustomizations") then
    buildcustomizations("BuildCustomizations/CUDA " .. cudaVersion)
  end

  if os.host() == "windows" then
    local cudaPath = os.getenv("CUDA_PATH")
    if cudaPath ~= nil then
      syslibdirs {cudaPath .. "/lib/x64"}
    end
  end
end

local function replay_premake_call(description, paths, call)
  local fn = _G[call.func]
  if not fn then
    premake.warn("Unknown premake API in " .. description.name .. ": " .. call.func)
    return
  end

  if (call.func == "cudaFiles" or call.func == "cudaPTXFiles") and type(call.args[1]) == "table" then
    fn(module_relative_paths(description, call.args[1]))
    return
  end

  if call.func == "cudaLinkFiles" and type(call.args[1]) == "table" then
    fn(target_relative_paths(paths, call.args[1]))
    return
  end

  fn(table.unpack(call.args))
end

local function generate_module(description, paths, source_extensions)
  project(description.name)
  kind(description.kind)
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
  externalincludedirs {path.getabsolute(paths.build) .. "/include"}

  if paths.VulkanSDK ~= nil then
    externalincludedirs {paths.VulkanSDK .. "/include"}
    syslibdirs {paths.VulkanSDK .. "/Lib"}
  end

  dependson(description.dependson)
  links(description.links)
  setup_cuda_module(description)

  for _, call in ipairs(description.premake_delayed_calls) do
    replay_premake_call(description, paths, call)
  end
end

local function infer_solution_level_settings(module_descriptions)
  local startup_project = nil
  for name, desc in pairs(module_descriptions) do
    for method, calls in pairs(desc.premake_delayed_calls) do
      if method == "kind" then
        for _, args in ipairs(calls) do
          if args[1]:find("App") then
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
  end
end

local function is_premake_call(name)
  return premake.field.get(name) ~= nil
end

function ps.generate(vcpkg_packages, settings)
  if not premake or string.sub(premake._VERSION, 1, 1) ~= "5" then
    error("You should only use premake_scaffold from premake5!")
  end

  if settings == nil then
    settings = {}
  end

  if vcpkg_packages and type(next(vcpkg_packages)) ~= "nil" then
    vcpkg.install(vcpkg_packages)
  end

  if type(settings) ~= "table" then
    error("You should provide settings table!")
  end

  local premake_delayed_calls = {}
  for name, args in pairs(settings) do
    if is_premake_call(name) then
      premake_delayed_calls[name] = args
      settings[name] = nil
    end
  end
  local S = table.merge(default_settings, settings)
  if premake_delayed_calls.vcpkgmanifest ~= nil then
    vcpkg.set_manifest_enabled(premake_delayed_calls.vcpkgmanifest)
  end
  utils.create_basic_actions(S)
  vcpkg.apply_classic_paths()

  -- setup up solution level settings
  architecture "x86_64"
  cppdialect "C++23"
  language "C++"
  configurations(S.configurations)
  basedir(S.paths.build)
  warnings "Extra"
  vcpkgstatic "true"
  staticruntime "on"
  fatalwarnings { "All" }

  filter "system:windows"
  multiprocessorcompile "on"
  buildoptions {"/permissive-", "/Zc:__cplusplus", "/utf-8"}

  filter {"system:windows"}
  disablewarnings {
    "4127", -- conditional expression is constant
    "4275", -- non-dll interface class used as base for dll-interface class
    "5054", -- operator '|': deprecated between enumerations of different types
    "4201" -- non-standard: nameless struct used (typically in a union)
  }
  defines {
    "NOMINMAX",
    "_CRT_SECURE_NO_WARNINGS",
    "_SILENCE_CXX23_ALIGNED_STORAGE_DEPRECATION_WARNING",
    "WIN32_LEAN_AND_MEAN"
  }
  filter {"configurations:Debug", "system:windows"}
  disablewarnings {
    -- disable annoying warnings during prototyping
    "4100"
  }
  symbols "FastLink"
  runtime "Debug"
  defines {"DEBUG"}
  targetsuffix "d"
  filter {"configurations:Release", "system:windows"}
  defines {"NDEBUG"}
  runtime "Release"
  optimize "On"
  filter {}

  for method, args in pairs(premake_delayed_calls) do
    _G[method](args)
  end

  -- setup dependency chain and generate projects based on modules' descriptions
  local module_descriptions = {}
  for _, module_path in ipairs(os.matchdirs(S.paths.modules .. "*")) do
    local module_name = path.getname(module_path)
    local desc = generate_module_description(module_name, S.paths.modules, S.module_defaults)
    module_descriptions[desc.name] = desc
    for name, desc in pairs(module_descriptions) do
      for _, link in ipairs(desc.premake_delayed_calls.links or {}) do
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
