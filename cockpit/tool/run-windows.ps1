# `flutter run -d windows` com o PATH que o build desktop precisa.
#
# O build compila o libghostty (Zig 0.16, instalado em %LOCALAPPDATA%\zig e
# fora do PATH do sistema) e a CLI interna (cargo, em ~/.cargo/bin). O PTY da
# task do Cockpit não herda o PATH do shell de login, então prefixamos os dois
# aqui. Chamado pela task "Cockpit" (Windows) em ../.cockpit/tasks.json via
# `pwsh -NoProfile -File tool/run-windows.ps1` — um script-arquivo evita
# qualquer citação de args na linha de comando. Args extras vão pro flutter.
$zig = Get-ChildItem "$env:LOCALAPPDATA\zig" -Directory -Filter 'zig-*' -ErrorAction SilentlyContinue |
  Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$prefix = @()
if ($zig) { $prefix += $zig }
$prefix += "$env:USERPROFILE\.cargo\bin"
$env:PATH = ($prefix + $env:PATH) -join ';'
flutter run -d windows @args
exit $LASTEXITCODE
