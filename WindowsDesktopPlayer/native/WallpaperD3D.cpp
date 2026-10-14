#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi.h>
#include <wrl/client.h>
#include "WallpaperD3D.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cwchar>
#include <iterator>
#include <new>
#include <string>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

using Microsoft::WRL::ComPtr;

static_assert(sizeof(WallpaperFrame) == 560, "WallpaperFrame must match the HLSL cbuffer layout.");

struct Renderer
{
    HWND window{};
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    ComPtr<IDXGISwapChain> swapChain;
    ComPtr<ID3D11RenderTargetView> renderTarget;
    ComPtr<ID3D11VertexShader> vertexShader;
    ComPtr<ID3D11PixelShader> pixelShader;
    ComPtr<ID3D11Buffer> constants;
    ComPtr<ID3D11SamplerState> sampler;
    ComPtr<ID3D11Texture2D> placeholderTexture;
    ComPtr<ID3D11ShaderResourceView> placeholderView;
    ComPtr<ID3D11Texture2D> artwork;
    ComPtr<ID3D11ShaderResourceView> artworkView;
    WallpaperFrame frame{};
    bool resizePending{ true };
};

static std::wstring g_error;
static constexpr wchar_t kWindowClass[] = L"SoundDesk.D3DWallpaperHost";

static void SetError(const wchar_t* operation, HRESULT result)
{
    wchar_t message[256]{};
    swprintf_s(message, L"%s failed (0x%08X)", operation, static_cast<unsigned>(result));
    g_error = message;
}

static void SetShaderError(ID3DBlob* diagnostics, const wchar_t* fallback)
{
    if (!diagnostics || !diagnostics->GetBufferPointer()) { g_error = fallback; return; }
    const auto* message = static_cast<const char*>(diagnostics->GetBufferPointer());
    const int length = static_cast<int>(diagnostics->GetBufferSize());
    const int wideLength = MultiByteToWideChar(CP_UTF8, 0, message, length, nullptr, 0);
    if (wideLength <= 0) { g_error = fallback; return; }
    g_error.resize(wideLength);
    MultiByteToWideChar(CP_UTF8, 0, message, length, g_error.data(), wideLength);
}

static LRESULT CALLBACK HostWindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    if (message == WM_NCDESTROY)
    {
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        return DefWindowProcW(hwnd, message, wParam, lParam);
    }
    auto* renderer = reinterpret_cast<Renderer*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE)
    {
        const auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
        renderer = static_cast<Renderer*>(create->lpCreateParams);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(renderer));
    }
    if (renderer && message == WM_SIZE) renderer->resizePending = true;
    if (message == WM_NCHITTEST) return HTTRANSPARENT;
    if (message == WM_ERASEBKGND) return 1;
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

static bool RegisterHostClass()
{
    static const bool registered = [] {
        WNDCLASSEXW wc{ sizeof(WNDCLASSEXW) };
        wc.lpfnWndProc = HostWindowProc;
        wc.hInstance = GetModuleHandleW(nullptr);
        wc.lpszClassName = kWindowClass;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        return RegisterClassExW(&wc) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    }();
    return registered;
}

static bool CreateBackBuffer(Renderer* renderer)
{
    renderer->renderTarget.Reset();
    RECT rect{};
    GetClientRect(renderer->window, &rect);
    const UINT width = static_cast<UINT>(std::max<LONG>(1, rect.right - rect.left));
    const UINT height = static_cast<UINT>(std::max<LONG>(1, rect.bottom - rect.top));
    HRESULT hr = renderer->swapChain->ResizeBuffers(0, width, height, DXGI_FORMAT_UNKNOWN, 0);
    if (FAILED(hr)) { SetError(L"IDXGISwapChain::ResizeBuffers", hr); return false; }
    ComPtr<ID3D11Texture2D> backBuffer;
    hr = renderer->swapChain->GetBuffer(0, IID_PPV_ARGS(&backBuffer));
    if (FAILED(hr)) { SetError(L"IDXGISwapChain::GetBuffer", hr); return false; }
    hr = renderer->device->CreateRenderTargetView(backBuffer.Get(), nullptr, &renderer->renderTarget);
    if (FAILED(hr)) { SetError(L"ID3D11Device::CreateRenderTargetView", hr); return false; }
    renderer->resizePending = false;
    return true;
}

static bool CreateRenderer(Renderer* renderer, const wchar_t* shaderPath)
{
    DXGI_SWAP_CHAIN_DESC swapDesc{};
    swapDesc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swapDesc.SampleDesc.Count = 1;
    swapDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swapDesc.BufferCount = 2;
    swapDesc.OutputWindow = renderer->window;
    swapDesc.Windowed = TRUE;
    swapDesc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    constexpr D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_0 };
    D3D_FEATURE_LEVEL selected{};
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#if defined(_DEBUG)
    flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
    HRESULT hr = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
        levels, static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION, &swapDesc,
        &renderer->swapChain, &renderer->device, &selected, &renderer->context);
    if (FAILED(hr))
    {
        flags &= ~D3D11_CREATE_DEVICE_DEBUG;
        hr = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
            levels, static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION, &swapDesc,
            &renderer->swapChain, &renderer->device, &selected, &renderer->context);
    }
    if (FAILED(hr)) { SetError(L"D3D11CreateDeviceAndSwapChain", hr); return false; }

    ComPtr<ID3DBlob> vsCode, psCode, diagnostics;
    hr = D3DCompileFromFile(shaderPath, nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE,
        "wallpaperVS", "vs_5_0", D3DCOMPILE_ENABLE_STRICTNESS, 0, &vsCode, &diagnostics);
    if (FAILED(hr))
    {
        SetShaderError(diagnostics.Get(), L"Could not compile wallpaperVS.");
        return false;
    }
    hr = D3DCompileFromFile(shaderPath, nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE,
        "wallpaperPS", "ps_5_0", D3DCOMPILE_ENABLE_STRICTNESS, 0, &psCode, &diagnostics);
    if (FAILED(hr))
    {
        SetShaderError(diagnostics.Get(), L"Could not compile wallpaperPS.");
        return false;
    }
    hr = renderer->device->CreateVertexShader(vsCode->GetBufferPointer(), vsCode->GetBufferSize(), nullptr, &renderer->vertexShader);
    if (FAILED(hr)) { SetError(L"ID3D11Device::CreateVertexShader", hr); return false; }
    hr = renderer->device->CreatePixelShader(psCode->GetBufferPointer(), psCode->GetBufferSize(), nullptr, &renderer->pixelShader);
    if (FAILED(hr)) { SetError(L"ID3D11Device::CreatePixelShader", hr); return false; }

    D3D11_BUFFER_DESC bufferDesc{};
    bufferDesc.ByteWidth = sizeof(WallpaperFrame);
    bufferDesc.Usage = D3D11_USAGE_DEFAULT;
    bufferDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    hr = renderer->device->CreateBuffer(&bufferDesc, nullptr, &renderer->constants);
    if (FAILED(hr)) { SetError(L"ID3D11Device::CreateBuffer", hr); return false; }

    D3D11_SAMPLER_DESC samplerDesc{};
    samplerDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
    samplerDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    samplerDesc.MaxLOD = D3D11_FLOAT32_MAX;
    hr = renderer->device->CreateSamplerState(&samplerDesc, &renderer->sampler);
    if (FAILED(hr)) { SetError(L"ID3D11Device::CreateSamplerState", hr); return false; }

    const std::uint32_t placeholder = 0xFF111722;
    D3D11_TEXTURE2D_DESC textureDesc{};
    textureDesc.Width = textureDesc.Height = 1;
    textureDesc.MipLevels = textureDesc.ArraySize = 1;
    textureDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    textureDesc.SampleDesc.Count = 1;
    textureDesc.Usage = D3D11_USAGE_DEFAULT;
    textureDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA initial{};
    initial.pSysMem = &placeholder;
    initial.SysMemPitch = sizeof(placeholder);
    hr = renderer->device->CreateTexture2D(&textureDesc, &initial, &renderer->placeholderTexture);
    if (FAILED(hr)) { SetError(L"placeholder artwork texture", hr); return false; }
    hr = renderer->device->CreateShaderResourceView(renderer->placeholderTexture.Get(), nullptr, &renderer->placeholderView);
    if (FAILED(hr)) { SetError(L"placeholder artwork view", hr); return false; }
    renderer->artworkView = renderer->placeholderView;
    return CreateBackBuffer(renderer);
}

extern "C" __declspec(dllexport) void* __cdecl WallpaperD3D_Create(HWND parent, int width, int height, const wchar_t* shaderPath)
{
    g_error.clear();
    if (!parent || !shaderPath || !RegisterHostClass()) { g_error = L"Could not create the Direct3D host window."; return nullptr; }
    auto renderer = new (std::nothrow) Renderer();
    if (!renderer) { g_error = L"Out of memory creating the Direct3D renderer."; return nullptr; }
    renderer->window = CreateWindowExW(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
        kWindowClass, L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        0, 0, std::max(1, width), std::max(1, height), parent, nullptr, GetModuleHandleW(nullptr), renderer);
    if (!renderer->window)
    {
        g_error = L"Could not create the Direct3D child window.";
        delete renderer;
        return nullptr;
    }
    if (!CreateRenderer(renderer, shaderPath))
    {
        const HWND child = renderer->window;
        SetWindowLongPtrW(child, GWLP_USERDATA, 0);
        DestroyWindow(child);
        delete renderer;
        return nullptr;
    }
    return renderer;
}

extern "C" __declspec(dllexport) void __cdecl WallpaperD3D_Destroy(void* handle)
{
    auto* renderer = static_cast<Renderer*>(handle);
    if (!renderer) return;
    const HWND child = renderer->window;
    if (child)
    {
        SetWindowLongPtrW(child, GWLP_USERDATA, 0);
        DestroyWindow(child);
    }
    delete renderer;
}

extern "C" __declspec(dllexport) void __cdecl WallpaperD3D_Show(void* handle, int show)
{
    auto* renderer = static_cast<Renderer*>(handle);
    if (renderer && renderer->window) ShowWindow(renderer->window, show ? SW_SHOWNOACTIVATE : SW_HIDE);
}

extern "C" __declspec(dllexport) int __cdecl WallpaperD3D_SetArtwork(void* handle, const std::uint8_t* pixels, int width, int height, int stride)
{
    auto* renderer = static_cast<Renderer*>(handle);
    if (!renderer) return 0;
    renderer->artwork.Reset();
    renderer->artworkView = renderer->placeholderView;
    if (!pixels || width <= 0 || height <= 0 || stride < width * 4) return 1;
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = static_cast<UINT>(width);
    desc.Height = static_cast<UINT>(height);
    desc.MipLevels = desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    D3D11_SUBRESOURCE_DATA data{};
    data.pSysMem = pixels;
    data.SysMemPitch = static_cast<UINT>(stride);
    HRESULT hr = renderer->device->CreateTexture2D(&desc, &data, &renderer->artwork);
    if (SUCCEEDED(hr)) hr = renderer->device->CreateShaderResourceView(renderer->artwork.Get(), nullptr, &renderer->artworkView);
    if (FAILED(hr))
    {
        SetError(L"Create album artwork texture", hr);
        renderer->artwork.Reset();
        renderer->artworkView = renderer->placeholderView;
        return 0;
    }
    return 1;
}

extern "C" __declspec(dllexport) void __cdecl WallpaperD3D_Render(void* handle, const WallpaperFrame* frame)
{
    auto* renderer = static_cast<Renderer*>(handle);
    if (!renderer || !frame || !IsWindowVisible(renderer->window)) return;
    renderer->frame = *frame;
    RECT parentRect{};
    const HWND parent = GetParent(renderer->window);
    if (parent && GetClientRect(parent, &parentRect))
    {
        const int width = std::max<LONG>(1, parentRect.right - parentRect.left);
        const int height = std::max<LONG>(1, parentRect.bottom - parentRect.top);
        RECT childRect{};
        GetWindowRect(renderer->window, &childRect);
        if (childRect.right - childRect.left != width || childRect.bottom - childRect.top != height)
            SetWindowPos(renderer->window, nullptr, 0, 0, width, height, SWP_NOACTIVATE | SWP_NOZORDER);
    }
    if (renderer->resizePending && !CreateBackBuffer(renderer)) return;
    const float clear[4] = { 0.003f, 0.007f, 0.018f, 1.0f };
    renderer->context->OMSetRenderTargets(1, renderer->renderTarget.GetAddressOf(), nullptr);
    D3D11_VIEWPORT viewport{};
    RECT rect{};
    GetClientRect(renderer->window, &rect);
    viewport.Width = static_cast<float>(std::max<LONG>(1, rect.right - rect.left));
    viewport.Height = static_cast<float>(std::max<LONG>(1, rect.bottom - rect.top));
    viewport.MaxDepth = 1.0f;
    renderer->context->RSSetViewports(1, &viewport);
    renderer->context->ClearRenderTargetView(renderer->renderTarget.Get(), clear);
    renderer->context->UpdateSubresource(renderer->constants.Get(), 0, nullptr, &renderer->frame, 0, 0);
    renderer->context->VSSetShader(renderer->vertexShader.Get(), nullptr, 0);
    renderer->context->PSSetShader(renderer->pixelShader.Get(), nullptr, 0);
    renderer->context->PSSetConstantBuffers(0, 1, renderer->constants.GetAddressOf());
    auto* artwork = renderer->artworkView.Get();
    renderer->context->PSSetShaderResources(0, 1, &artwork);
    auto* sampler = renderer->sampler.Get();
    renderer->context->PSSetSamplers(0, 1, &sampler);
    renderer->context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    renderer->context->Draw(3, 0);
    renderer->swapChain->Present(0, 0);
}

extern "C" __declspec(dllexport) int __cdecl WallpaperD3D_GetLastError(wchar_t* destination, int capacity)
{
    if (!destination || capacity <= 0) return 0;
    const auto count = std::min<int>(capacity - 1, static_cast<int>(g_error.size()));
    std::copy_n(g_error.data(), count, destination);
    destination[count] = L'\0';
    return count;
}
