# Motivation

In the age of bazels and deterministic builds, a man needs their reinvented wheels. Bootstrap your minimalistic projects based on ancient technologies at the speed of light:

```bash
$ git submodule add https://github.com/yuyoyuppe/premake_scaffold deps/premake_scaffold
```

and then your whole `premake5.lua` is:

```lua
ps = require 'deps.premake_scaffold'
workspace "awesome_project"
ps.generate({ paths = { 
  ClangFormatExecutable = "S:\\VS2019\\VC\\Tools\\Llvm\\bin\\clang-format.exe",
  VulkanSDK             = "S:\\VulkanSDK\\1.1.121.2\\" } })
```

What you've got? Let's say you've had a project structure like this:

```
- awesome_project
|- src
 |- shaders
  |- a.glsl, b.glsl ...
 |- engine
  | - e1.cxx, e2.cxx ...
 |- game
  | - g1.cxx, g2.cxx ...
```

Now your `engine` and `game` could be compiled as 64-bit C++latest static libraries with sane<sup>`-Wall -Werror`</sup> warning settings, and `shaders` will use Vulkan SDK to compile in parallel. All build artefacts are placed in `awesome_project/build` folder by default. You also got new `premake5` actions: `format`, `clean` and `rebuild`.

What about executable and dependencies, you say? Sure, create a `description.lua` in `game` folder with:
```lua
return {
  kind = 'WindowedApp',
  links = {'game'},
  dependson = 'shaders' }
```

And now you're done. As you see, you can specify any `premake5` *api-call data* on a per-module basis using `description.lua`.

# Philosophy
- Every software project needs its own philosophy
- Don't waste time
- Use a turn-key solution such as `vcpkg`/`pacman`/`brew` as much as you can

# TODO

- finalize custom types support (shaders)
- integrate scre
- integrate luafmt
- allow solution level premake overrides
- linux/macosx support
- profile configuration