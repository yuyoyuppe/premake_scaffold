require 'os_utils'

nuget = {}

-- NuGet package cache directory (inside build folder)
local NUGET_CACHE_DIR = "nuget_packages"

-- NuGet API URL for downloading packages
local NUGET_API_URL = "https://www.nuget.org/api/v2/package"

-- Track installed packages for include/lib path setup
local installed_packages = {}

local function get_cache_dir()
    return path.join(_MAIN_SCRIPT_DIR, "build", NUGET_CACHE_DIR)
end

local function get_package_dir(package_id, version)
    return path.join(get_cache_dir(), package_id .. "." .. version)
end

local function package_exists(package_id, version)
    local pkg_dir = get_package_dir(package_id, version)
    -- Check if the extracted directory exists and has content
    return os.isdir(pkg_dir) and os.isdir(path.join(pkg_dir, "build"))
end

local function download_package(package_id, version)
    local cache_dir = get_cache_dir()
    local pkg_dir = get_package_dir(package_id, version)
    local nupkg_path = pkg_dir .. ".nupkg"
    local download_url = string.format("%s/%s/%s", NUGET_API_URL, package_id, version)

    -- Create cache directory if it doesn't exist
    os.mkdir(cache_dir)

    -- Download the package
    premake.info("Downloading NuGet package: %s %s", package_id, version)

    local download_cmd
    if os.host() == "windows" then
        -- Use PowerShell's Invoke-WebRequest
        download_cmd = string.format(
            [[powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%s' -OutFile '%s'"]],
            download_url,
            nupkg_path
        )
    else
        -- Use curl on Unix
        download_cmd = string.format(
            [[curl -L -o "%s" "%s"]],
            nupkg_path,
            download_url
        )
    end

    if not os.execute(download_cmd) then
        premake.error("Failed to download NuGet package: %s %s", package_id, version)
        return false
    end

    return true
end

local function extract_package(package_id, version)
    local pkg_dir = get_package_dir(package_id, version)
    local nupkg_path = pkg_dir .. ".nupkg"
    local zip_path = pkg_dir .. ".zip"

    -- Create extraction directory
    os.mkdir(pkg_dir)

    premake.info("Extracting NuGet package: %s %s", package_id, version)

    local extract_cmd
    if os.host() == "windows" then
        -- Rename .nupkg to .zip (PowerShell's Expand-Archive requires .zip extension)
        os.rename(nupkg_path, zip_path)
        -- Use PowerShell's Expand-Archive
        extract_cmd = string.format(
            [[powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '%s' -DestinationPath '%s' -Force"]],
            zip_path,
            pkg_dir
        )
    else
        -- Use unzip on Unix (handles .nupkg directly)
        zip_path = nupkg_path
        extract_cmd = string.format(
            [[unzip -o "%s" -d "%s"]],
            nupkg_path,
            pkg_dir
        )
    end

    if not os.execute(extract_cmd) then
        premake.error("Failed to extract NuGet package: %s %s", package_id, version)
        return false
    end

    -- Remove the archive file after extraction to save space
    os.remove(zip_path)

    return true
end

-- Install a NuGet package (download and extract if not cached)
-- Returns the package directory path
function nuget.install(package_id, version)
    if _ACTION == nil then
        return nil
    end

    local pkg_dir = get_package_dir(package_id, version)

    if package_exists(package_id, version) then
        premake.info("NuGet package already cached: %s %s", package_id, version)
    else
        if not download_package(package_id, version) then
            return nil
        end
        if not extract_package(package_id, version) then
            return nil
        end
        premake.info("NuGet package installed: %s %s", package_id, version)
    end

    -- Track this package
    installed_packages[package_id] = {
        version = version,
        dir = pkg_dir
    }

    return pkg_dir
end

-- Get include directories for a NuGet package
-- Most native NuGet packages have headers in build/native/include
function nuget.include_dirs(package_id)
    local pkg = installed_packages[package_id]
    if not pkg then
        premake.warn("NuGet package not installed: %s", package_id)
        return {}
    end

    local include_paths = {}

    -- Common include locations in NuGet packages
    local possible_includes = {
        "build/native/include",
        "build/native/include/onnxruntime",  -- OnnxRuntime specific
        "include",
        "native/include"
    }

    for _, rel_path in ipairs(possible_includes) do
        local full_path = path.join(pkg.dir, rel_path)
        if os.isdir(full_path) then
            table.insert(include_paths, full_path)
        end
    end

    return include_paths
end

-- Get library directories for a NuGet package
-- Returns both release and debug lib paths
function nuget.lib_dirs(package_id, arch)
    local pkg = installed_packages[package_id]
    if not pkg then
        premake.warn("NuGet package not installed: %s", package_id)
        return {release = {}, debug = {}}
    end

    arch = arch or "x64"
    local win_arch = (arch == "x64") and "win-x64" or "win-x86"

    local lib_paths = {release = {}, debug = {}}

    -- Common lib locations in NuGet packages
    local possible_libs = {
        "runtimes/" .. win_arch .. "/native",
        "build/native/lib/" .. arch .. "/Release",
        "build/native/lib/" .. arch,
        "lib/native/" .. win_arch,
        "native/lib"
    }

    local possible_debug_libs = {
        "build/native/lib/" .. arch .. "/Debug",
        "runtimes/" .. win_arch .. "/native"  -- Often same for debug
    }

    for _, rel_path in ipairs(possible_libs) do
        local full_path = path.join(pkg.dir, rel_path)
        if os.isdir(full_path) then
            table.insert(lib_paths.release, full_path)
        end
    end

    for _, rel_path in ipairs(possible_debug_libs) do
        local full_path = path.join(pkg.dir, rel_path)
        if os.isdir(full_path) then
            table.insert(lib_paths.debug, full_path)
        end
    end

    -- If no debug libs found, use release libs
    if #lib_paths.debug == 0 then
        lib_paths.debug = lib_paths.release
    end

    return lib_paths
end

-- Get DLL paths for runtime copying (for post-build copy)
function nuget.dll_paths(package_id, arch)
    local pkg = installed_packages[package_id]
    if not pkg then
        return {}
    end

    arch = arch or "x64"
    local win_arch = (arch == "x64") and "win-x64" or "win-x86"

    local dll_paths = {}

    -- Common DLL locations
    local possible_dlls = {
        "runtimes/" .. win_arch .. "/native",
        "build/native/bin/" .. arch,
        "native/bin"
    }

    for _, rel_path in ipairs(possible_dlls) do
        local full_path = path.join(pkg.dir, rel_path)
        if os.isdir(full_path) then
            -- Find all DLLs in this directory
            local dlls = os.matchfiles(path.join(full_path, "*.dll"))
            for _, dll in ipairs(dlls) do
                table.insert(dll_paths, dll)
            end
        end
    end

    return dll_paths
end

-- Helper to set up include and lib paths for a project
function nuget.setup_project(package_id, arch)
    local includes = nuget.include_dirs(package_id)
    local libs = nuget.lib_dirs(package_id, arch)

    if #includes > 0 then
        externalincludedirs(includes)
    end

    filter {"configurations:Debug"}
    if #libs.debug > 0 then
        libdirs(libs.debug)
    end

    filter {"configurations:not Debug"}
    if #libs.release > 0 then
        libdirs(libs.release)
    end

    filter {}
end

-- Generate post-build commands to copy DLLs
function nuget.copy_dlls_command(package_id, dest_dir, arch)
    local dlls = nuget.dll_paths(package_id, arch)
    local commands = {}

    for _, dll in ipairs(dlls) do
        table.insert(commands, string.format('{COPYFILE} %%[%s] %%[%s]', dll, dest_dir))
    end

    return commands
end

-- Get the package directory (for custom access)
function nuget.package_dir(package_id)
    local pkg = installed_packages[package_id]
    if pkg then
        return pkg.dir
    end
    return nil
end

return nuget
