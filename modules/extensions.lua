require("vstudio")
local p = premake
local m = p.vstudio.vc2010

p.api.register {
    name = "vscodeanalysis",
    scope = "workspace",
    kind = "boolean"
}

local function vsCodeAnalysis(prj)
    if prj.workspace.vscodeanalysis then
        m.element("RunCodeAnalysis", nil, "true")
    end
end

-- Allows switching to vcpkg static libraries
p.api.register {
    name = "vcpkgstatic",
    scope = "workspace",
    kind = "boolean"
}

local function VcpkgStatic(prj)
    if prj.workspace.vcpkgstatic then
        m.element("VcpkgUseStatic", nil, "true")
    end
end

p.override(
    m.elements,
    "globals",
    function(base, prj)
        local elements = base(prj)
        table.insert(elements, VcpkgStatic)
        table.insert(elements, vsCodeAnalysis)
        return elements
    end
)
