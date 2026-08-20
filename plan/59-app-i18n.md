# 59 — App: i18n (slang) + seletor de idioma

## Contexto

O app Remote Pi sempre teve strings hardcoded em inglês. O Cockpit já usa
`slang` com suporte a `en`, `pt_BR` e `es`. Este plano migra todas as strings
do app para o `slang` e adiciona um seletor de idioma (System / English /
Português / Español) no Settings.

## Escopo

- **3 locales**: en, pt-BR, es
- **slang** com `TranslationProvider` + rebuild no `MaterialApp`
- **Preferences.localeCode** persistido via `FlutterSecureStorage`
- **Seletor de idioma** em Settings → Display → Language
- **140+ strings** migradas em 6 namespaces (common, home, chat, pairing,
  settings, notifications) cobrindo 20+ arquivos UI

## DoD

- [x] 1 — Infra `slang` + `TranslationProvider`
- [x] 2 — `Preferences.localeCode` com persistência
- [x] 3 — Seletor System / English / Português / Español
- [x] 4 — Todas as strings migradas (20+ arquivos)
- [x] 5 — Testes (6 locale_test) passando + zero regressões
