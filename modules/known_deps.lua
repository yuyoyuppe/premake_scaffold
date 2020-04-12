return {
  glfw = {
    build = function(self, paths)
      utils.ensure_executables_in_path({'cmake', 'git'})
      utils.ensure_devtools_shell()
      os.execute('cmake -DBUILD_SHARED_LIBS=OFF -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF -DUSE_MSVC_RUNTIME_LIBRARY_DLL=OFF -DGLFW_VULKAN_STATIC=OFF -DCMAKE_GENERATOR_PLATFORM=x64 -DVULKAN_INCLUDE_DIR=%s -DVULKAN_LIBRARY=%s .', paths.VulkanSDK, paths.VulkanSDK)
      os.execute('msbuild /m /nologo /v:q /p:Configuration=Release /p:Platform=x64 GLFW.sln')
      os.mklink('src/Release/glfw3.lib', path.join(paths.built_deps.lib, 'glfw3.lib'))
      -- utils.link_files_filtered('include/GLFW', '../build/') -- todo: fix for updated paths api
    end
  },

  glm = {
    build = function(self, paths)
      utils.ensure_devtools_shell()
      os.execute('cmake -DCMAKE_GENERATOR_PLATFORM=x64 -DBUILD_STATIC_LIBS=1 .')
      os.execute('msbuild /m /nologo /v:q /p:Configuration=Release /p:Platform=x64 glm\\glm_static.vcxproj')
      -- todo: fix for updated paths api
      -- os.mklink('glm/Release/glm_static.lib', '../build/lib/glm_static.lib')
      -- utils.link_files_filtered('glm/', '../build/include/', {'.hpp', '.inl', '.h'}) 
    end
  },

  imgui = {
    build = function(self, paths)
      os.link_files_filtered('.', paths.built_deps.include, {'.h'}, false)
      os.link_files_filtered('misc/cpp', paths.built_deps.include, {'.h'}, false)
      os.chdir('misc/cpp/')
      os.mklink('imgui_stdlib.h', path.join(paths.built_deps.include, 'imgui_stdlib.h'))
      os.chdir('../../')
    end
  },

  colony = {
    build = function(self, paths)
      os.mklink('plf_colony/plf_colony.h', path.join(paths.built_deps.include, 'plf_colony.h'))
    end
  },

  toml11 = {
    build = function(self, paths)
      os.mklink('toml.hpp', path.join(paths.built_deps.include, 'toml.hpp'))
      os.mklink('toml', path.join(paths.built_deps.include, 'toml'))
    end
  },

  entt = {
    build = function(self, paths)
      os.mklink('src/entt', path.join(paths.built_deps.include, 'entt'))
    end
  } 
}