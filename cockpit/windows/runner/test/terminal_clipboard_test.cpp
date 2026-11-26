// Pure bitmap tests: never open or modify the user's clipboard.
#define COCKPIT_CLIPBOARD_TEST
#include "../terminal_clipboard.cpp"
#include <iostream>

void Check(bool condition) {
  if (!condition) throw std::runtime_error("Native clipboard regression assertion failed");
}

std::vector<uint8_t> Dib(bool v5, bool top_down = false) {
  const size_t header_size = v5 ? sizeof(BITMAPV5HEADER) : sizeof(BITMAPINFOHEADER);
  std::vector<uint8_t> bytes(header_size + 16, 0);
  auto* info = reinterpret_cast<BITMAPINFOHEADER*>(bytes.data());
  info->biSize = static_cast<DWORD>(header_size);
  info->biWidth = 2;
  info->biHeight = top_down ? -2 : 2;
  info->biPlanes = 1;
  info->biBitCount = 32;
  info->biCompression = BI_RGB;
  std::memset(bytes.data() + header_size, 255, 16);
  return bytes;
}
int main() {
  int passed = 0;
  for (const bool v5 : {false, true}) {
    for (const bool top_down : {false, true}) {
      const auto bytes = Dib(v5, top_down);
      const auto png = DecodeDib(bytes.data(), bytes.size());
      Check(png.size() > 8 && png[0] == 137 && png[1] == 80 && png[2] == 78 && png[3] == 71);
      ++passed;
    }
  }
  for (const bool v5 : {false, true}) {
    auto bytes = Dib(v5);
    if (!v5) bytes.insert(bytes.begin() + sizeof(BITMAPINFOHEADER), 12, 0);
    auto* info = reinterpret_cast<BITMAPINFOHEADER*>(bytes.data());
    info->biCompression = BI_BITFIELDS;
    auto* masks = reinterpret_cast<DWORD*>(bytes.data() + sizeof(BITMAPINFOHEADER));
    masks[0] = 0x00ff0000; masks[1] = 0x0000ff00; masks[2] = 0x000000ff;
    const auto png = DecodeDib(bytes.data(), bytes.size());
    Check(png.size() > 8); ++passed;
    Check(ReadPngBytes(png.data(), png.size()) == png); ++passed;
  }
  for (const auto bytes : {std::vector<uint8_t>{}, std::vector<uint8_t>(8, 0)}) {
    bool rejected = false;
    try { ReadPngBytes(bytes.data(), bytes.size()); } catch (const std::runtime_error&) { rejected = true; }
    Check(rejected); ++passed;
  }
  auto valid = Dib(false);
  for (const size_t length : {size_t(0), size_t(39), valid.size() - 1}) {
    bool failed = false;
    try { DecodeDib(valid.data(), length); } catch (const std::runtime_error&) { failed = true; }
    Check(failed); ++passed;
  }
  for (const LONG height : {LONG(0), (std::numeric_limits<LONG>::min)(), LONG(1000000)}) {
    auto bytes = Dib(true);
    reinterpret_cast<BITMAPINFOHEADER*>(bytes.data())->biHeight = height;
    bool failed = false;
    try { DecodeDib(bytes.data(), bytes.size()); } catch (const std::runtime_error&) { failed = true; }
    Check(failed); ++passed;
  }
  auto invalid = Dib(false);
  reinterpret_cast<BITMAPINFOHEADER*>(invalid.data())->biCompression = BI_RLE8;
  bool failed = false;
  try { DecodeDib(invalid.data(), invalid.size()); } catch (const std::runtime_error&) { failed = true; }
  Check(failed); ++passed;
  std::cout << passed << " native bitmap tests passed\n";
}
