# Build macOS universal — Apple Silicon e Intel

Este projeto gera um único `Cockpit.app` compatível com os dois tipos de Mac:

| Computador do usuário                   | Arquitetura no app |
| --------------------------------------- | ------------------ |
| Mac com Apple Silicon (M1, M2, M3, M4…) | `arm64`            |
| Mac Intel                               | `x86_64`           |

O mantenedor faz as releases em **Apple Silicon**. Este é o fluxo principal e
recomendado: nele o próprio Mac de build cria todas as fatias do aplicativo e
dos helpers internos (`cockpit-cli` e `cockpit-hook`).

> O arquivo mantém o nome histórico `BUILD_X86_64_INTEL.md`, mas não descreve
> mais um build exclusivo para Intel: a release gerada é universal.

## Fluxo principal: release em Apple Silicon

### 1. Pré-requisitos (somente uma vez por máquina)

Instale ou confirme:

1. Xcode e as Command Line Tools.
2. O Flutter **ARM** usado normalmente pelo projeto.
3. Uma segunda instalação do Flutter **x64**, com a **mesma versão** do Flutter
   ARM. Ela é usada apenas sob Rosetta para compilar a fatia Intel dos helpers.
4. Rosetta 2:

```bash
softwareupdate --install-rosetta --agree-to-license
```

O Flutter ARM e o Flutter x64 podem ficar em diretórios diferentes. Exemplo:

```text
/opt/flutter-arm64
/opt/flutter-x64
```

Confirme que os dois Dart SDKs têm a mesma versão. Os comandos devem mostrar a
mesma versão de Dart (por exemplo, `3.12.2`):

```bash
/opt/flutter-arm64/bin/dart --version
arch -x86_64 /opt/flutter-x64/bin/dart --version
```

### 2. Preparar o terminal de release

Na raiz deste repositório, selecione o Flutter ARM para o build e informe o
Dart x64 complementar:

```bash
export FLUTTER_ROOT="/opt/flutter-arm64"
export PATH="$FLUTTER_ROOT/bin:$PATH"
export COCKPIT_DART_X64="/opt/flutter-x64/bin/dart"
```

Faça uma conferência rápida antes de compilar:

```bash
flutter --version
arch -x86_64 "$COCKPIT_DART_X64" --version
```

Se houver divergência de versão do Dart, pare aqui e instale a versão x64 que
corresponde ao Flutter ARM. O build detecta essa situação e falha de propósito.

### 3. Compilar

```bash
flutter pub get
flutter build macos --release
```

Durante o build:

1. Flutter gera o aplicativo principal com `arm64` e `x86_64`.
2. Os scripts `macos/build_cli.sh` e `macos/build_hook.sh` compilam os helpers
   em `arm64` com o Dart nativo.
3. Os mesmos scripts executam o Dart x64 sob Rosetta e compilam a fatia Intel.
4. `lipo` une cada par de fatias em um único executável universal.
5. A assinatura configurada pelo projeto é aplicada ao helper final.

O resultado fica em:

```text
build/macos/Build/Products/Release/Cockpit.app
```

### 4. Validar antes de assinar ou distribuir

```bash
APP="build/macos/Build/Products/Release/Cockpit.app"

lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/Cockpit"
lipo -verify_arch arm64 x86_64 "$APP/Contents/Resources/cockpit-cli"
lipo -verify_arch arm64 x86_64 "$APP/Contents/Resources/cockpit-hook"
codesign --verify --deep --strict --verbose=2 "$APP"
```

Os quatro comandos devem terminar sem erro. Os dois últimos executáveis são
essenciais: sem eles, terminal, CLI interna e integração de hooks poderiam
falhar em uma das arquiteturas mesmo que a janela principal abrisse.

## Erros comuns

| Mensagem ou sintoma                | Causa provável                                | Como resolver                                                        |
| ---------------------------------- | --------------------------------------------- | -------------------------------------------------------------------- |
| `COCKPIT_DART_X64` não definido    | Build Apple Silicon sem SDK x64 indicado      | Exporte o caminho para `flutter-x64/bin/dart`.                       |
| Não foi possível executar SDK x64  | Rosetta ausente ou caminho incorreto          | Instale Rosetta e rode `arch -x86_64 "$COCKPIT_DART_X64" --version`. |
| Versões Dart diferentes            | Flutter ARM e x64 não correspondem            | Instale o SDK x64 da mesma versão do Flutter ARM.                    |
| `lipo -verify_arch` falha em Intel | Os helpers Intel têm apenas x64 por definição | Faça a release em Apple Silicon.                                     |

## Referências no projeto

- `macos/build_dart_helper.sh`: lógica compartilhada para criar helpers
  universais.
- `macos/build_cli.sh`: empacota a CLI interna.
- `macos/build_hook.sh`: empacota o helper de hooks.
- [`packaging/README.md`](packaging/README.md): assinatura, DMG, notarização e
  publicação.
