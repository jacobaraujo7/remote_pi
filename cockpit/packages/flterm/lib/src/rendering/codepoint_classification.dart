/// Whether [cp] is a CJK or Hangul codepoint (rendered as tinted text).
///
/// Wide characters that are NOT CJK are assumed to be emoji and rendered
/// as full-color image sprites. Flutter doesn't expose a font-level
/// `isColorGlyph()` check, so codepoint range classification is the
/// pragmatic way to distinguish CJK text from emoji in the hot loop.
bool isCjkCodepoint(int cp) => switch (cp) {
  >= 0x2E80 && <= 0x9FFF => true, // CJK radicals, unified ideographs
  >= 0xAC00 && <= 0xD7AF => true, // Hangul Syllables
  >= 0xF900 && <= 0xFAFF => true, // CJK Compatibility Ideographs
  >= 0xFE30 && <= 0xFE4F => true, // CJK Compatibility Forms
  >= 0xFF01 && <= 0xFF60 => true, // Fullwidth Forms
  >= 0xFFE0 && <= 0xFFE6 => true, // Fullwidth Signs
  >= 0x1100 && <= 0x11FF => true, // Hangul Jamo
  >= 0x3130 && <= 0x318F => true, // Hangul Compatibility Jamo
  >= 0xA960 && <= 0xA97F => true, // Hangul Jamo Extended-A
  >= 0xD7B0 && <= 0xD7FF => true, // Hangul Jamo Extended-B
  >= 0x20000 && <= 0x2FA1F => true, // CJK Supplementary
  _ => false,
};
