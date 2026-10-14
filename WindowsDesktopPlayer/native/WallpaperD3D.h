#pragma once
#include <Windows.h>
#include <cstdint>

struct WallpaperFrame
{
    float time, low, mid, high;
    float guitar, piano, drums, aspect;
    std::uint32_t effectIndex;
    float padding[3];
    float bands[128];
};

extern "C" __declspec(dllexport) void* __cdecl WallpaperD3D_Create(HWND parent, int width, int height, const wchar_t* shaderPath);
extern "C" __declspec(dllexport) void __cdecl WallpaperD3D_Destroy(void* handle);
extern "C" __declspec(dllexport) void __cdecl WallpaperD3D_Show(void* handle, int show);
extern "C" __declspec(dllexport) int __cdecl WallpaperD3D_SetArtwork(void* handle, const std::uint8_t* pixels, int width, int height, int stride);
extern "C" __declspec(dllexport) int __cdecl WallpaperD3D_Render(void* handle, const WallpaperFrame* frame);
extern "C" __declspec(dllexport) int __cdecl WallpaperD3D_GetLastError(wchar_t* destination, int capacity);
