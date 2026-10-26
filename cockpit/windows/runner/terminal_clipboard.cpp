#ifndef COCKPIT_CLIPBOARD_TEST
#include "terminal_clipboard.h"
#endif
#include <windows.h>
#include <shellapi.h>
#include <objidl.h>
#include <gdiplus.h>
#ifndef COCKPIT_CLIPBOARD_TEST
#include <flutter/standard_method_codec.h>
#endif
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr size_t kMaxImageBytes = 128 * 1024 * 1024;
class ClipboardLock {
 public:
  ClipboardLock() {
    if (!OpenClipboard(nullptr)) throw std::runtime_error("Clipboard is busy; try again");
  }
  ~ClipboardLock() { CloseClipboard(); }
};
class GlobalMemoryLock {
 public:
  explicit GlobalMemoryLock(HGLOBAL handle) : handle_(handle), data_(GlobalLock(handle)) {
    if (!data_) throw std::runtime_error("Could not read clipboard memory");
  }
  ~GlobalMemoryLock() { GlobalUnlock(handle_); }
  void* data() const { return data_; }
 private:
  HGLOBAL handle_;
  void* data_;
};
std::string Utf8(const std::wstring& input) {
  if (input.empty()) return {};
  const int count = WideCharToMultiByte(CP_UTF8, 0, input.data(), static_cast<int>(input.size()), nullptr, 0, nullptr, nullptr);
  std::string result(count, '\0');
  WideCharToMultiByte(CP_UTF8, 0, input.data(), static_cast<int>(input.size()), result.data(), count, nullptr, nullptr);
  return result;
}
std::vector<uint8_t> DecodeDib(const uint8_t* bytes, size_t size) {
  if (size < sizeof(BITMAPINFOHEADER) || size > kMaxImageBytes) throw std::runtime_error("Invalid or oversized clipboard bitmap");
  const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(bytes);
  if (header->biSize < sizeof(BITMAPINFOHEADER) || header->biSize > size ||
      header->biWidth <= 0 || header->biHeight == 0 || header->biHeight == (std::numeric_limits<LONG>::min)() ||
      header->biPlanes != 1 ||
      (header->biBitCount != 1 && header->biBitCount != 4 && header->biBitCount != 8 &&
       header->biBitCount != 16 && header->biBitCount != 24 && header->biBitCount != 32) ||
      (header->biCompression != BI_RGB && header->biCompression != BI_BITFIELDS)) {
    throw std::runtime_error("Unsupported clipboard bitmap layout");
  }
  const uint64_t palette = header->biClrUsed ? header->biClrUsed :
      (header->biBitCount <= 8 ? (1ULL << header->biBitCount) : 0);
  const uint64_t masks = header->biSize == sizeof(BITMAPINFOHEADER) && header->biCompression == BI_BITFIELDS ? 12 : 0;
  const uint64_t offset = header->biSize + palette * sizeof(RGBQUAD) + masks;
  const uint64_t stride = ((static_cast<uint64_t>(header->biWidth) * header->biBitCount + 31) / 32) * 4;
  const uint64_t height = header->biHeight < 0 ? -static_cast<int64_t>(header->biHeight) : header->biHeight;
  if (offset > size || stride * height > size - offset) throw std::runtime_error("Truncated clipboard bitmap");
  Gdiplus::GdiplusStartupInput startup;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &startup, nullptr) != Gdiplus::Ok) throw std::runtime_error("Could not initialize image decoder");
  std::vector<uint8_t> result;
  // GDI+ objects must be destroyed before GdiplusShutdown.
  {
    Gdiplus::Bitmap bitmap(reinterpret_cast<const BITMAPINFO*>(bytes), const_cast<uint8_t*>(bytes + offset));
    IStream* stream = nullptr;
    if (bitmap.GetLastStatus() == Gdiplus::Ok && SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
      constexpr CLSID png_encoder = {0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
      if (bitmap.Save(stream, &png_encoder, nullptr) == Gdiplus::Ok) {
        STATSTG stat = {};
        HGLOBAL encoded = nullptr;
        if (SUCCEEDED(stream->Stat(&stat, STATFLAG_NONAME)) && stat.cbSize.QuadPart <= kMaxImageBytes &&
            SUCCEEDED(GetHGlobalFromStream(stream, &encoded))) {
          const auto* data = static_cast<const uint8_t*>(GlobalLock(encoded));
          if (data) {
            result.assign(data, data + static_cast<size_t>(stat.cbSize.QuadPart));
            GlobalUnlock(encoded);
          }
        }
      }
      stream->Release();
    }
  }
  Gdiplus::GdiplusShutdown(token);
  if (result.empty()) throw std::runtime_error("Could not encode clipboard bitmap as PNG");
  return result;
}
std::vector<uint8_t> ReadPngBytes(const uint8_t* bytes, size_t size) {
  if (size < 8 || size > kMaxImageBytes) throw std::runtime_error("Invalid or oversized clipboard PNG");
  constexpr uint8_t signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
  if (std::memcmp(bytes, signature, sizeof(signature)) != 0) throw std::runtime_error("Invalid clipboard PNG signature");
  return {bytes, bytes + size};
}
std::vector<uint8_t> ReadImage() {
  const UINT png = RegisterClipboardFormatW(L"PNG");
  if (IsClipboardFormatAvailable(png)) {
    const HGLOBAL handle = GetClipboardData(png);
    const size_t size = GlobalSize(handle);
    if (size < 8 || size > kMaxImageBytes) throw std::runtime_error("Invalid or oversized clipboard PNG");
    GlobalMemoryLock lock(handle);
    const auto* bytes = static_cast<const uint8_t*>(lock.data());
    return ReadPngBytes(bytes, size);
  }
  const UINT format = IsClipboardFormatAvailable(CF_DIBV5) ? CF_DIBV5 : CF_DIB;
  if (!IsClipboardFormatAvailable(format)) return {};
  const HGLOBAL handle = GetClipboardData(format);
  const size_t size = GlobalSize(handle);
  GlobalMemoryLock lock(handle);
  return DecodeDib(static_cast<const uint8_t*>(lock.data()), size);
}

#ifndef COCKPIT_CLIPBOARD_TEST
flutter::EncodableMap WithSequence(flutter::EncodableMap result) {
  // Delayed clipboard rendering can advance the sequence while reading data.
  result[flutter::EncodableValue("sequence")] = flutter::EncodableValue(static_cast<int64_t>(GetClipboardSequenceNumber()));
  return result;
}
flutter::EncodableMap ReadClipboard() {
  ClipboardLock lock;
  flutter::EncodableMap result;
  if (IsClipboardFormatAvailable(CF_HDROP)) {
    const HDROP drop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
    if (!drop) throw std::runtime_error("Could not read copied files");
    flutter::EncodableList files;
    const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < count; ++i) {
      const UINT length = DragQueryFileW(drop, i, nullptr, 0);
      std::wstring name(length + 1, L'\0');
      DragQueryFileW(drop, i, name.data(), length + 1);
      name.resize(length);
      if (!name.empty()) files.emplace_back(Utf8(name));
    }
    if (!files.empty()) {
      result[flutter::EncodableValue("files")] = flutter::EncodableValue(files);
      return WithSequence(std::move(result));
    }
  }
  auto image = ReadImage();
  if (!image.empty()) {
    result[flutter::EncodableValue("image")] = flutter::EncodableValue(image);
    return WithSequence(std::move(result));
  }
  if (IsClipboardFormatAvailable(CF_UNICODETEXT)) {
    const HGLOBAL text = GetClipboardData(CF_UNICODETEXT);
    const size_t units = GlobalSize(text) / sizeof(wchar_t);
    GlobalMemoryLock text_lock(text);
    const auto* chars = static_cast<const wchar_t*>(text_lock.data());
    size_t length = 0;
    while (length < units && chars[length] != L'\0') ++length;
    result[flutter::EncodableValue("text")] = flutter::EncodableValue(Utf8(std::wstring(chars, length)));
  }
  return WithSequence(std::move(result));
}
#endif
}  // namespace

#ifndef COCKPIT_CLIPBOARD_TEST
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateTerminalClipboardChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "cockpit/terminal_clipboard", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      if (call.method_name() == "read") result->Success(flutter::EncodableValue(ReadClipboard()));
      else if (call.method_name() == "sequence") result->Success(flutter::EncodableValue(static_cast<int64_t>(GetClipboardSequenceNumber())));
      else result->NotImplemented();
    } catch (const std::exception& error) {
      result->Error("clipboard_read_failed", error.what());
    }
  });
  return channel;
}

#endif
