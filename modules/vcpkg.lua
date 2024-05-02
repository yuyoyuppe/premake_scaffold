require 'os_utils'

vcpkg = {
}

local vcpkg_root = os.getenv("VCPKG_ROOT")
if vcpkg_root == nil or vcpkg_root == "" then
    error("You should set env var VCPKG_ROOT to vcpkg's install location")
end

local function vcpkg_install(packages, triplet)
    if os.getenv("ZSH_VERSION") ~= nil then
        packages = packages:gsub("%[", "\\["):gsub("%]", "\\]")
    end
    
    local cmd =
        string.format(
        "%s install %s --triplet=%s --host-triplet=%s --recurse --clean-after-build",
        premake.quoted(path.join(PATHS.vcpkg.root, "vcpkg")),
        packages:gsub("\n", " "),
        triplet,
        triplet
    )
    premake.info("Installing vcpkg packages for %s...", triplet)
    if os_utils.exec_silent(cmd) then
        premake.info("vcpkg installation complete!")
    else
        premake.error(cmd .. " exited with an error!")
    end
end

local TARGET_TO_TRIPLET = {
    windows = "windows-static",
    linux = "linux",
    macosx = "osx"
}

if not PATHS then
    PATHS = {}
end

PATHS.vcpkg = {}
PATHS.vcpkg.root = path.normalize(vcpkg_root)
PATHS.vcpkg.target_triplet = _OPTIONS["arch"] .. "-" .. TARGET_TO_TRIPLET[os.target()]
PATHS.vcpkg.host_triplet = PATHS.vcpkg.target_triplet
if MACOS_CROSS_COMPILATION then
    PATHS.vcpkg.host_triplet = "x64-osx"
end
PATHS.vcpkg.target_triplet = _OPTIONS["arch"] .. "-" .. TARGET_TO_TRIPLET[os.target()]
PATHS.vcpkg.installed = path.join(PATHS.vcpkg.root, "installed")
PATHS.vcpkg.tools = path.join(PATHS.vcpkg.installed, PATHS.vcpkg.host_triplet .. "/tools")

function PATHS.vcpkg.includes_for_triplet(triplet)
    local main_include_path = path.join(PATHS.vcpkg.installed, triplet .. "/include")
    return {main_include_path}
end

filter {}
externalincludedirs(PATHS.vcpkg.includes_for_triplet(PATHS.vcpkg.target_triplet))

function PATHS.vcpkg.libs_for_triplet(triplet)
    return {path.join(PATHS.vcpkg.installed, triplet .. "/lib")}
end

function PATHS.vcpkg.debug_libs_for_triplet(triplet)
    return {path.join(PATHS.vcpkg.installed, triplet .. "/debug/lib")}
end

-- Helper function for libs that have inconsistent naming due to vcpkg's sloppiness
function PATHS.vcpkg.links(names, filter_conf)
    local unix_debug_suffices = {
        fmt = "d",
        infoware = "d",
        spdlog = "d",
        libbreakpad = "d",
        libbreakpad_client = "d",
        imgui = "d",
        nfd = "_d",
        bz2 = "d",
        ["SDL2"] = "d",
        ["SDL2_image"] = "d"
    }

    local debug_suffices = {
        windows = {
            fmt = "d",
            spdlog = "d",
            curl = "-d",
            zlib = "d",
            imgui = "d",
            infoware = "d",
            libbreakpad_client = "d",
            libbreakpad = "d",
            libpng16 = "d",
            nfd = "_d",
            ["SDL2_image-static"] = "d",
            ["SDL2-static"] = "d"
        },
        linux = unix_debug_suffices,
        macosx = unix_debug_suffices
    }

    local prefices = {
        windows = {
            curl = "lib",
            crypto = "lib",
            ssl = "lib"
        },
        linux = {},
        macosx = {}
    }

    if type(filter_conf) == "table" then
        filter(filter_conf)
    end

    local target_prefices = prefices[os.target()]
    local target_debug_suffices = debug_suffices[os.target()]
    for _, name in ipairs(names) do
        local suffix = target_debug_suffices[name]
        local prefix = target_prefices[name]

        if prefix ~= nil then
            name = prefix .. name
        end

        if suffix ~= nil then
            filter {"configurations:not Debug"}
            links {name}
            filter {"configurations:Debug"}
            links {name .. suffix}
            filter {}
        else
            links {name}
        end
    end
end

filter {"configurations:Debug"}
libdirs(PATHS.vcpkg.debug_libs_for_triplet(PATHS.vcpkg.target_triplet))
filter {"configurations:not Debug"}
libdirs(PATHS.vcpkg.libs_for_triplet(PATHS.vcpkg.target_triplet))
filter {}

function vcpkg.install(packages)
    packages = table.concat(packages, " ")
    if _ACTION ~= nil and (_ACTION == "vs2022" or _ACTION == "gmake2") then
        if MACOS_CROSS_COMPILATION then
            vcpkg_install("flatbuffers", PATHS.vcpkg.host_triplet)
            vcpkg_install(packages, PATHS.vcpkg.host_triplet)
        end
    
        vcpkg_install(packages, PATHS.vcpkg.target_triplet)
    end
end


return vcpkg