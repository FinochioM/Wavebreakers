@echo off

sokol-shdc -i game/shaders/shader.glsl -o game/shaders/shader.odin -l hlsl5:wgsl -f sokol_odin --save-intermediate-spirv

odin build game -debug