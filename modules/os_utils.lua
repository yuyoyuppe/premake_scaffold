os_utils = {}

function os_utils.exec_silent(cmd, ...)
    local formatted = cmd:format(...)
    if os.host() == "windows" then
        return os.execute(formatted .. " >nul 2>nul")
    else
        return os.execute(formatted .. "  > /dev/null 2>&1")
    end
end

function os_utils.has_in_path(executable)
    if os.host() == "windows" then
        return os_utils.exec_silent("where " .. executable)
    else
        return os_utils.exec_silent("which " .. executable)
    end
end

function os_utils.cmake_configure_file(template_path, output_path, variables_to_sub)
    local template = io.readfile(template_path)
    for _, var_name in ipairs(variables_to_sub) do
        template = template:gsub("@" .. var_name .. "@", _G[var_name])
    end
    os.writefile_ifnotequal(template, output_path)
end

local function read_cache(filename)
    local cache = {}
    local file = io.open(path.join(PATHS.build, filename), "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("([^:]+):(.*)")
            cache[key] = value
        end
        file:close()
    end
    return cache
end

local function save_cache(cache, filename)
    local file = io.open(path.join(PATHS.build, filename), "w")
    for key, value in pairs(cache) do
        file:write(key .. ":" .. value .. "\n")
    end
    file:close()
end

local function get_latest_vs_install_path()
    local instances_dir = "C:\\ProgramData\\Microsoft\\VisualStudio\\Packages\\_Instances\\"

    local instance_ids = {}
    for instance in io.popen('dir "' .. instances_dir .. '" /b /ad'):lines() do
        table.insert(instance_ids, instance)
    end

    local newest_version = "0.0.0"
    local newest_path = nil

    for _, instance_id in ipairs(instance_ids) do
        local state_path = instances_dir .. instance_id .. "\\state.json"

        local file = io.open(state_path, "r")
        if file then
            local content = file:read("*all")
            file:close()

            local version = content:match('"buildVersion"%s-:%s-"(.-)%+')
            local path = content:match('"installationPath"%s-:%s-"(.-)"')

            if version and path and version > newest_version then
                newest_version = version
                newest_path = path
            end
        end
    end

    -- Return the installation path of the newest version
    return newest_path
end

function os_utils.obtain_vcvars_tool_path(tool_name)
    if os.host() ~= "windows" then
        return nil
    end

    local cache_filename = "cached_vcvars_paths.txt"
    local cache = read_cache(cache_filename)
    if cache[tool_name] then
        return cache[tool_name]
    end

    local vs_root = get_latest_vs_install_path()

    premake.info("The latest Visual Studio installation found in %s", vs_root)

    local init_vc_env_cmd = path.join(vs_root, "VC\\Auxiliary\\Build\\vcvars64.bat")
    local output = os.outputof(premake.quoted(init_vc_env_cmd) .. " >nul 2>nul && where " .. tool_name)
    -- extract the first output line
    output = output:gsub("[\r\n]+", "\n")
    output = output:gsub("^%s*(.-)%s*$", "%1")
    output = '"' .. output:match("^[^\n]*") .. '"'

    cache[tool_name] = output
    save_cache(cache, cache_filename)
    return output
end

function os_utils.execute_or_exit(cmd)
    if not os.execute(cmd) then
        premake.error("Execution of the '" .. cmd .. "' failed. Stopping.")
    end
end

function os_utils.zip_dir(src_dir, zip_name)
    if os.host() == "windows" then
        return os.executef(
            [[powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive %s %s.zip -CompressionLevel Optimal -Force"]],
            src_dir,
            zip_name
        )
    else
        return os.executef("zip -r %s.zip %s", zip_name, src_dir)
    end
end

function os_utils.load_binary_file(filename)
    local file, err = io.open(filename, "rb")
    if not file then
        premake.error("Error opening file: " .. err)
        return nil
    end

    local content = file:read("*a")
    file:close()

    return content
end

function os_utils.zip_files(file_paths, zip_name, ignore_file_paths)
    if ignore_file_paths == nil then
        ignore_file_paths = true
    end
    if os.host() == "windows" then
        if not ignore_file_paths then
            premake.error("unimplemented!")
        end

        local file_list = "@("
        for _, file in ipairs(file_paths) do
            file_list = file_list .. '\\"' .. file .. '\\",'
        end
        file_list = string.sub(file_list, 1, -2) .. ")"
        return os.executef(
            [[powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path %s -DestinationPath %s.zip -CompressionLevel Optimal -Force"]],
            file_list,
            zip_name
        )
    else
        local file_list = ""
        for _, file in ipairs(file_paths) do
            file_list = file_list .. premake.quoted(file) .. " "
        end
        local zip_cmd = ignore_file_paths and "zip -j" or "zip"
        return os.executef("%s %s.zip %s", zip_cmd, zip_name, file_list)
    end
end

function os_utils.host_arch()
    if os.host() == "windows" then
        premake.error("os_utils.host_arch: Implement Windows support!")
        return "x64"
    end

    local arch = os.outputof("uname -m")
    if arch:find("x86_64") then
        return "x64"
    elseif arch:find("arm64") or arch:find("aarch64") then
        return "arm64"
    else
        return nil
    end
end

return os_utils
