# Cockpit branding

Marca própria do Cockpit (out 2026, spec "Cockpit Logo Spec" no Claude
Design). Um π construído com três painéis de split; o ponto azul do Remote Pi
segue como indicador de status.

## Arquivos

| Arquivo | Uso |
|---|---|
| `cockpit-icon-dark.svg` | Ícone principal, tile preto arredondado (raio 22%). App, dock, favicon, avatar |
| `cockpit-icon-dark-square.svg` | Tile quadrado, canto a canto. **Fonte dos ícones de launch**: iOS, Android e o script do macOS aplicam a própria máscara |
| `cockpit-icon-light.svg` | Ícone em fundo claro (`#F2F2F4`, painéis `#111`) |
| `cockpit-mark-white.svg` / `cockpit-mark-black.svg` | Símbolo transparente, para fundo escuro / claro |
| `cockpit-mark-mono-white.svg` / `cockpit-mark-mono-black.svg` | Monocromático (1 cor): tray, menu bar, gravação |
| `png/` | Rasterizações dos SVGs (`rsvg-convert`), 16 a 1024 px |
| `cockpit_logo.png` | Ícone escuro em 512 px (cópia de `png/cockpit-icon-dark-512.png`), usado por `welcome_view`, `loading_screen` e `file_icon` |

## Construção (grade de 512u)

- Barra: 288 × 72u em x112 y142. Pernas: 96 × 154u em x140 e x276, y228.
- Respiro: 14u vertical, 40u entre as pernas. Raio dos painéis 16u.
- Ponto: ø56u no centro x410 y132, com anel de recorte de 10u (ø76u) na cor do fundo.
- Tile: 512u, raio 112u.

## Cores

- Pi Blue (ponto): `#4FC3F7`. É o azul do Remote Pi e não muda fora das versões mono.
- Fundo escuro `#000000`, painéis `#FFFFFF`.
- Fundo claro `#F2F2F4`, painéis `#111111`.

## Regras

- Não mudar a cor do ponto, não fechar os respiros, não distorcer, não mover o ponto nem tirar o recorte.
- Área de proteção = diâmetro do ponto (56u, ~11% do lado). Mínimo 16 px.

## Regenerar os PNGs

```sh
cd cockpit/assets/branding
rsvg-convert -w 1024 -h 1024 cockpit-icon-dark-square.svg -o png/cockpit-icon-square-1024.png
for s in 1024 512 256 128 64 32 16; do rsvg-convert -w $s -h $s cockpit-icon-dark.svg -o png/cockpit-icon-dark-$s.png; done
```
