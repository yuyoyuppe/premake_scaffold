--
-- qt6_static: links all transitive dependencies required by a static Qt6 build
-- from vcpkg (x64-windows-static).
--
-- Usage:
--   local qt6s = require 'modules.qt6_static'
--   qt6s.link(vcpkg_installed, {
--       "Qt6/plugins/platforms/qwindows",
--       "Qt6/qml/QtQuick/qtquick2plugin",
--   })
--

local qt6_static = {}

local thirdparty = {
    "double-conversion", "zstd", "harfbuzz", "md4c",
    "brotlidec", "brotlicommon", "libssl", "libcrypto", "jpeg",
}

local thirdparty_debug_suffix = {
    { "zlib",     "zlibd" },
    { "icuin",    "icuind" },
    { "icuuc",    "icuucd" },
    { "icudt",    "icudtd" },
    { "pcre2-16", "pcre2-16d" },
    { "freetype", "freetyped" },
    { "bz2",      "bz2d" },
    { "libpng16", "libpng16d" },
}

local win_syslibs = {
    "synchronization", "mpr", "userenv", "advapi32", "authz", "kernel32",
    "netapi32", "ntdll", "ole32", "runtimeobject", "shell32", "user32",
    "uuid", "version", "winmm", "ws2_32", "d3d11", "dxgi", "dxguid",
    "d3d12", "gdi32", "uxtheme", "d2d1", "dwrite", "dnsapi", "iphlpapi",
    "secur32", "winhttp", "crypt32", "dwmapi", "imm32", "oleaut32",
    "setupapi", "shlwapi", "winspool", "wtsapi32", "shcore", "comdlg32",
    "d3d9", "uiautomationcore", "opengl32",
}

local function parse_prl_objs(prl_path, base)
    local objs = {}
    local f = io.open(prl_path, "r")
    if not f then return objs end

    local content = f:read("*a")
    f:close()

    local libs_line = content:match("QMAKE_PRL_LIBS_FOR_CMAKE%s*=%s*(.-)\n")
    if not libs_line then return objs end

    for token in libs_line:gmatch("[^;]+") do
        if token:match("%.obj$") then
            local resolved = token
                :gsub("%$%$%[QT_INSTALL_PREFIX%]", base)
                :gsub("%$%$%[QT_INSTALL_LIBS%]",   path.join(base, "lib"))
                :gsub("%$%$%[QT_INSTALL_PLUGINS%]", path.join(base, "Qt6/plugins"))
                :gsub("%$%$%[QT_INSTALL_QML%]",    path.join(base, "Qt6/qml"))
            resolved = path.normalize(resolved)
            if os.isfile(resolved) then
                objs[#objs + 1] = '"' .. path.getabsolute(resolved) .. '"'
            end
        end
    end
    return objs
end

local function apply_config(base, suffix, plugins)
    local lib_dirs_set, lib_names, objs = {}, {}, {}

    for _, entry in ipairs(plugins) do
        local dir  = path.getdirectory(entry)
        local name = path.getbasename(entry)

        lib_dirs_set[path.join(base, dir)] = true
        lib_names[#lib_names + 1] = name .. suffix

        local prl_path = path.join(base, entry .. suffix .. ".prl")
        for _, o in ipairs(parse_prl_objs(prl_path, base)) do
            objs[#objs + 1] = o
        end
    end

    local dirs = {}
    for d in pairs(lib_dirs_set) do dirs[#dirs + 1] = d end
    syslibdirs(dirs)
    links(lib_names)
    if #objs > 0 then linkoptions(objs) end
end

function qt6_static.link(vcpkg_installed, plugins)
    links(thirdparty)
    links(win_syslibs)

    filter { "configurations:Release" }
        for _, p in ipairs(thirdparty_debug_suffix) do links { p[1] } end
        apply_config(vcpkg_installed, "", plugins)
    filter { "configurations:Debug" }
        for _, p in ipairs(thirdparty_debug_suffix) do links { p[2] } end
        apply_config(path.join(vcpkg_installed, "debug"), "d", plugins)
    filter {}
end

return qt6_static
