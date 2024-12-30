@echo off

sokol-shdc -i game/shader.glsl -o game/shader.odin -l hlsl5:wgsl -f sokol_odin --save-intermediate-spirv

if not exist build_release mkdir build_release

pushd build_release
odin build ../game -o:speed
popd