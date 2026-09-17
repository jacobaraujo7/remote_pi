; Template Inno Setup custom do Cockpit (plano 47). Referenciado por
; `script_template: inno_template.iss` no make_config.yaml. Baseado no template
; default do fastforge (flutter_app_packager) + as diretivas de self-update.
; As variáveis {{...}}/{% %} são preenchidas pelo fastforge (Liquid).
[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Plano 47 — self-update via WinSparkle. Num update silencioso o cockpit pode
; estar rodando: o Restart Manager fecha a instância (CloseApplications) e a
; relança após instalar (RestartApplications). O WinSparkle encerra o app antes
; de rodar o instalador, então o RM vê uma instância só — sem duplo-launch.
; VALIDAR no Windows real (não testável neste Mac).
CloseApplications=yes
RestartApplications=yes
; Associação de arquivos (k17): o Explorer reconstrói o cache de tipos.
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}

[Files]
Source: "{{SOURCE_DIR}}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\{{DISPLAY_NAME}}"; Filename: "{app}\{{EXECUTABLE_NAME}}"; Tasks: desktopicon

; "Abrir com Cockpit" (k17). ProgIds próprios por tipo; .kanban/.ckp/.dbq/.http
; são do Cockpit e viram default. .md só entra na lista "Abrir com"
; (OpenWithProgids) — não rouba o editor padrão de Markdown do usuário.
; Instalação por usuário → HKCU\Software\Classes (sem admin). O app recebe o
; caminho como argumento e, se já há um Cockpit aberto, repassa a ele
; (instância única, ver RunningInstance no Dart).
[Registry]
Root: HKCU; Subkey: "Software\Classes\Cockpit.Kanban"; ValueType: string; ValueData: "Cockpit Kanban Board"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Cockpit.Kanban\DefaultIcon"; ValueType: string; ValueData: "{app}\{{EXECUTABLE_NAME}},0"
Root: HKCU; Subkey: "Software\Classes\Cockpit.Kanban\shell\open\command"; ValueType: string; ValueData: """{app}\{{EXECUTABLE_NAME}}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.kanban"; ValueType: string; ValueData: "Cockpit.Kanban"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.kanban\OpenWithProgids"; ValueType: string; ValueName: "Cockpit.Kanban"; ValueData: ""; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\Classes\Cockpit.Layout"; ValueType: string; ValueData: "Cockpit Pane Layout"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Cockpit.Layout\DefaultIcon"; ValueType: string; ValueData: "{app}\{{EXECUTABLE_NAME}},0"
Root: HKCU; Subkey: "Software\Classes\Cockpit.Layout\shell\open\command"; ValueType: string; ValueData: """{app}\{{EXECUTABLE_NAME}}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.ckp"; ValueType: string; ValueData: "Cockpit.Layout"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.ckp\OpenWithProgids"; ValueType: string; ValueName: "Cockpit.Layout"; ValueData: ""; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\Classes\Cockpit.Query"; ValueType: string; ValueData: "Cockpit Database Query"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Cockpit.Query\DefaultIcon"; ValueType: string; ValueData: "{app}\{{EXECUTABLE_NAME}},0"
Root: HKCU; Subkey: "Software\Classes\Cockpit.Query\shell\open\command"; ValueType: string; ValueData: """{app}\{{EXECUTABLE_NAME}}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.dbq"; ValueType: string; ValueData: "Cockpit.Query"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.dbq\OpenWithProgids"; ValueType: string; ValueName: "Cockpit.Query"; ValueData: ""; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\Classes\Cockpit.Http"; ValueType: string; ValueData: "Cockpit HTTP Request"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Cockpit.Http\DefaultIcon"; ValueType: string; ValueData: "{app}\{{EXECUTABLE_NAME}},0"
Root: HKCU; Subkey: "Software\Classes\Cockpit.Http\shell\open\command"; ValueType: string; ValueData: """{app}\{{EXECUTABLE_NAME}}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.http\OpenWithProgids"; ValueType: string; ValueName: "Cockpit.Http"; ValueData: ""; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\Classes\Cockpit.Markdown"; ValueType: string; ValueData: "Markdown (Cockpit)"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Cockpit.Markdown\DefaultIcon"; ValueType: string; ValueData: "{app}\{{EXECUTABLE_NAME}},0"
Root: HKCU; Subkey: "Software\Classes\Cockpit.Markdown\shell\open\command"; ValueType: string; ValueData: """{app}\{{EXECUTABLE_NAME}}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: string; ValueName: "Cockpit.Markdown"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: string; ValueName: "Cockpit.Markdown"; ValueData: ""; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: nowait postinstall skipifsilent
