local p = premake

-- compile shaders in parallel
require('vstudio')
p.override(p.vstudio.vc2010, "emitFiles",
  function(base, prj, group, tag, fileFunc, fileCfgFunc, checkFunc)
  if tag == "CustomBuild" then
    fileCfgFunc = table.join(fileCfgFunc, function(fcfg, condition)
      if string.endswith(fcfg.name, 'glsl') then
        p.vstudio.vc2010.element("BuildInParallel", condition, "true")
      end
    end)
  end
  return base(prj, group, tag, fileFunc, fileCfgFunc, checkFunc)
end)

local shaders = {
  use = function(self, paths)
    files { self.base_path .. "**.glsl"}
		filter { "files:**.glsl" }
    buildoutputs { paths.build .. "%(Filename).spirv" }
    buildmessage("Compiling '%(Filename)' shader...")
    filter { "files:**.glsl", "configurations:not Debug" }
    buildcommands { paths.VulkanSDK .. '/Bin/glslangValidator.exe -V110 -t %(FullPath) -o %(Filename).spirv && {DELETE}	$(IntDir)\\%(Filename)*.cpp > nul 2>&1 && $(OutDir)\\scre.exe %(Filename).spirv $(IntDir)\\'}
    filter { "files:**.glsl", "configurations:Debug" }
    buildcommands {paths.VulkanSDK .. '/Bin/glslangValidator.exe -V110 -g -t %(FullPath) -o %(Filename).spirv && {DELETE}	$(IntDir)\\%(Filename)*.cpp > nul 2>&1 && $(OutDir)\\scred.exe %(Filename).spirv $(IntDir)\\'}
    filter{}
    prebuildcommands {""}
  end
}


return {
  shaders
}
