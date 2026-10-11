# Upstream x64-windows-static, pinned to the v143 toolset (what CI's windows-2022
# runner uses). Without this vcpkg picks VS 2026's default v145.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_PROVIDED_FORTRAN ON)
set(VCPKG_PLATFORM_TOOLSET v143)
