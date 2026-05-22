# Branding — Remote Pi

Identidade visual oficial. Fonte de verdade: arquivos SVG (escaláveis).
PNGs derivados gerados via ferramenta externa quando necessário.

## Paleta

| Cor | Hex | Uso |
|---|---|---|
| Preto puro | `#000000` | Background (full + adaptive icon bg) |
| Branco puro | `#FFFFFF` | Símbolo π (foreground principal) |
| Azul Pi | `#4FC3F7` | Bolinha característica |

## Arquivos

| Arquivo | Conteúdo | Uso recomendado |
|---|---|---|
| `logo-full.svg` | Background preto + π branco + bolinha azul | Logo single-piece (favicon, README header, site, app store screenshots) |
| `logo-foreground.svg` | π + bolinha em fundo transparente | iOS app icon (com background separado), Android adaptive icon foreground layer |
| `logo-background.svg` | Preto sólido 1024×1024 | Android adaptive icon background layer |
| `logo-monochrome.svg` | Silhueta branca completa | Android 13+ themed icon (sistema colore conforme wallpaper) |

Todos os arquivos: **1024×1024** viewBox, safe zone Android-compatível (~66% central).

## Como converter pra PNG

Nenhuma ferramenta de conversão hoje instalada no projeto. Opções pra
gerar PNG quando necessário:

### Via `rsvg-convert` (mais simples)

```bash
brew install librsvg
rsvg-convert -w 1024 -h 1024 logo-foreground.svg -o logo-foreground.png
rsvg-convert -w 1024 -h 1024 logo-background.svg -o logo-background.png
rsvg-convert -w 1024 -h 1024 logo-monochrome.svg -o logo-monochrome.png
rsvg-convert -w 1024 -h 1024 logo-full.svg -o logo-full.png
```

### Via ImageMagick

```bash
brew install imagemagick
magick -background none -resize 1024x1024 logo-foreground.svg logo-foreground.png
```

### Via Inkscape (CLI)

```bash
inkscape --export-type=png --export-width=1024 logo-foreground.svg
```

### Via Figma/online

- [https://cloudconvert.com/svg-to-png](https://cloudconvert.com/svg-to-png)
- [https://svgtopng.com](https://svgtopng.com)

## Tamanhos padrão exportar

Antes de upload em store/site, gere variantes:

| Plataforma | Tamanho | Arquivo fonte |
|---|---|---|
| iOS App Icon | 1024×1024 PNG (sem alpha) | `logo-full.svg` |
| Android Adaptive (foreground) | 432×432 PNG transparente | `logo-foreground.svg` |
| Android Adaptive (background) | 432×432 PNG (cor sólida basta) | `logo-background.svg` |
| Android Themed (monochrome) | 432×432 PNG transparente | `logo-monochrome.svg` |
| Favicon | 32×32, 16×16 PNG | `logo-full.svg` |
| App Store screenshot header | 1200×630 PNG | `logo-full.svg` (compor) |
| npm registry README | 512×512 PNG | `logo-full.svg` |

> Android adaptive icons: tanto foreground quanto background ocupam 108dp
> canvas total, mas conteúdo importante deve ficar dentro de 66dp central
> (safe zone). Os SVGs já respeitam essa proporção (~66% do 1024).

## Atualização

Mudanças visuais: editar SVG (Figma → export SVG é OK). Regenerar PNGs
derivados nos pontos de uso (site, app, store).

Antes de mudar paleta ou silhueta, atualizar este README com a nova
versão da identidade visual + razão da mudança.
