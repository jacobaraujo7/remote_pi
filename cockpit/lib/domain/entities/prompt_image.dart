/// Imagem anexada a um prompt. Vira um `ImageContent` no wire do `pi --mode rpc`
/// (`{type:'image', data:<base64>, mimeType}`), enviado no campo `images` do
/// comando `prompt`.
class PromptImage {
  const PromptImage({required this.data, required this.mimeType});

  /// Conteúdo em base64 (sem o prefixo `data:`).
  final String data;

  /// MIME type, ex.: `image/png`, `image/jpeg`.
  final String mimeType;
}
