import '../domain/entities/db_result.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/widgets.dart';

/// Frase de um [DbQueryException] para a UI.
///
/// Mora na feature, e não no `core/ui` junto do `automation_error_message`,
/// porque o `DbQueryException` é do domínio do cockpit — e o core não importa
/// de feature nenhuma.
///
/// Quase toda mensagem de banco é **texto de terceiros** — stderr do driver,
/// "authentication failed" do Postgres — e por isso não se traduz (regra de
/// i18n do projeto): sai como veio. A exceção são os erros que o próprio
/// Cockpit inventa, e aí a frase nasce aqui.
///
/// O `switch` é sobre `String`, e não sobre enum, porque o `kind` do
/// [DbQueryException] é o contrato textual estável que a CLI também consome
/// (`connection_failed`, `password_required`, …). Um `default` que devolve a
/// mensagem crua é o comportamento certo para todo kind vindo do driver.
String dbErrorMessage(BuildContext context, DbQueryException e) =>
    switch (e.kind) {
      // Senha guardada no host que não existe lá: quase sempre conexão
      // cadastrada antes do plano 62, cuja senha ficou no cofre do cliente que
      // a criou. A frase precisa dizer o que fazer, porque o texto do driver
      // ("authentication failed") mandaria investigar a coisa errada.
      'password_required' => context.t.cockpit.dbPanel.passwordRequired,
      _ => e.message,
    };
