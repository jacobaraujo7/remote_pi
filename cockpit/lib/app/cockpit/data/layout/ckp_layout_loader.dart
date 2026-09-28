import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/layout_loader.dart';
import 'package:cockpit/app/cockpit/domain/entities/layout_spec.dart';
import 'package:cockpit/app/cockpit/domain/services/ckp_layout_parser.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Lê um `.ckp` do disco e devolve o [LayoutSpec]. A validação inteira mora
/// no [CkpLayoutParser] (domínio, sem IO) — aqui é só o arquivo: o mesmo
/// parser roda no viewer de layout, sobre o texto que a sessão já tem.
class CkpLayoutLoader implements LayoutLoader {
  const CkpLayoutLoader({this.hostOs});

  /// SO usado no filtro de `platforms` — só sobrescrito em teste.
  final String? hostOs;

  @override
  Future<Result<LayoutSpec, String>> load(String ckpPath) async {
    final file = File(ckpPath);
    if (!await file.exists()) {
      return Failure('layout file not found: "$ckpPath"');
    }
    return CkpLayoutParser(
      hostOs ?? Platform.operatingSystem,
    ).parse(await file.readAsString(), name: layoutNameOf(ckpPath));
  }
}
