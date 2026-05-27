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

p.api.register {
    name = "vcpkgenabled",
    scope = "workspace",
    kind = "boolean"
}

p.api.register {
    name = "vcpkgenableclassic",
    scope = "workspace",
    kind = "boolean"
}

p.api.register {
    name = "vcpkgmanifest",
    scope = "workspace",
    kind = "boolean"
}

p.api.register {
    name = "vcpkgmanifestinstall",
    scope = "workspace",
    kind = "boolean"
}

p.api.register {
    name = "vcpkgautolink",
    scope = "workspace",
    kind = "boolean"
}

p.api.register {
    name = "vcpkgapplocaldeps",
    scope = "workspace",
    kind = "boolean"
}

p.api.register {
    name = "vcpkgusemd",
    scope = "workspace",
    kind = "boolean"
}

p.api.register {
    name = "vcpkgroot",
    scope = "workspace",
    kind = "string"
}

p.api.register {
    name = "vcpkgmanifestroot",
    scope = "workspace",
    kind = "string"
}

p.api.register {
    name = "vcpkginstalleddir",
    scope = "workspace",
    kind = "string"
}

p.api.register {
    name = "vcpkgtriplet",
    scope = "workspace",
    kind = "string"
}

p.api.register {
    name = "vcpkghosttriplet",
    scope = "workspace",
    kind = "string"
}

p.api.register {
    name = "vcpkgadditionalinstalloptions",
    scope = "workspace",
    kind = "string"
}

local function VcpkgStatic(prj)
    if prj.workspace.vcpkgstatic then
        m.element("VcpkgUseStatic", nil, "true")
    end
end

local function optionalVcpkgElement(prj, field, element)
    local value = prj.workspace[field]
    if value ~= nil then
        m.element(element, nil, tostring(value))
    end
end

local function VcpkgSettings(prj)
    optionalVcpkgElement(prj, "vcpkgenabled", "VcpkgEnabled")
    optionalVcpkgElement(prj, "vcpkgenableclassic", "VcpkgEnableClassic")
    optionalVcpkgElement(prj, "vcpkgmanifest", "VcpkgEnableManifest")
    optionalVcpkgElement(prj, "vcpkgmanifestinstall", "VcpkgManifestInstall")
    optionalVcpkgElement(prj, "vcpkgautolink", "VcpkgAutoLink")
    optionalVcpkgElement(prj, "vcpkgapplocaldeps", "VcpkgApplocalDeps")
    optionalVcpkgElement(prj, "vcpkgusemd", "VcpkgUseMD")
    optionalVcpkgElement(prj, "vcpkgroot", "VcpkgRoot")
    optionalVcpkgElement(prj, "vcpkgmanifestroot", "VcpkgManifestRoot")
    optionalVcpkgElement(prj, "vcpkginstalleddir", "VcpkgInstalledDir")
    optionalVcpkgElement(prj, "vcpkgtriplet", "VcpkgTriplet")
    optionalVcpkgElement(prj, "vcpkghosttriplet", "VcpkgHostTriplet")
    optionalVcpkgElement(prj, "vcpkgadditionalinstalloptions", "VcpkgAdditionalInstallOptions")
end

p.override(
    m.elements,
    "globals",
    function(base, prj)
        local elements = base(prj)
        table.insert(elements, VcpkgStatic)
        table.insert(elements, VcpkgSettings)
        table.insert(elements, vsCodeAnalysis)
        return elements
    end
)
