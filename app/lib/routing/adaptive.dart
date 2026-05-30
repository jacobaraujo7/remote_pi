import 'package:flutter/widgets.dart';

/// Largura mínima (em pixels lógicos de largura *disponível*) a partir da
/// qual o app entra no modo tablet de dois painéis (master + detail).
///
/// É medida por largura disponível — não por `shortestSide` do device —
/// para reagir ao Split View / Slide Over do iPadOS: se o usuário encolher
/// o app para uma coluna estreita, ele colapsa graciosamente para um painel.
const double kTabletBreakpoint = 600.0;

/// `true` quando a largura disponível comporta o layout de dois painéis.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kTabletBreakpoint;

/// Largura máxima de conteúdo de coluna única (onboarding, empty states).
/// Acima disso o conteúdo é centralizado em vez de esticar borda-a-borda —
/// evita o efeito "UI de celular gigante" no tablet.
const double kMaxContentWidth = 460.0;

/// Centraliza e limita a largura do [child] em telas largas; em larguras de
/// celular é praticamente um passthrough (o conteúdo já preenche a tela).
/// Centraliza nos dois eixos, então serve tanto para conteúdo de altura
/// mínima (empty states) quanto para colunas full-height (onboarding com
/// `Expanded`).
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = kMaxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Estado de layout do shell adaptativo. Hoje carrega só `isZeroState`:
/// `true` quando a Home não tem nada para listar/selecionar (sem Pi pareado
/// ou lista vazia). Nesse caso o shell colapsa para um único painel cheio e
/// centralizado, em vez de mostrar o split com um placeholder grande e vazio.
///
/// Default `false` (split por padrão em telas largas) para não piscar
/// single→split no caso comum de já existirem sessões no boot.
class ShellLayout extends ChangeNotifier {
  bool _zeroState = false;
  bool get isZeroState => _zeroState;

  void setZeroState(bool value) {
    if (value == _zeroState) return;
    _zeroState = value;
    notifyListeners();
  }
}

/// Sessão atualmente selecionada na UI (o chat mostrado no painel detail
/// do tablet e destacado na lista master).
///
/// É **distinta** do peer conectado (`Preferences.selectedPeerEpk`, setado
/// no boot): começa `null` de propósito para que, ao abrir o app, nenhum
/// chat apareça pré-selecionado — o placeholder é mostrado até o primeiro
/// toque. Vive enquanto o app roda (não é restaurada entre execuções, já
/// que queremos iniciar sempre sem seleção).
class SessionSelection extends ChangeNotifier {
  ({String epk, String roomId, String title})? _current;

  ({String epk, String roomId, String title})? get current => _current;

  /// `true` se `(epk, roomId)` é a sessão selecionada agora.
  bool matches(String epk, String roomId) {
    final c = _current;
    return c != null && c.epk == epk && c.roomId == roomId;
  }

  void select(String epk, String roomId, String title) {
    final c = _current;
    if (c != null && c.epk == epk && c.roomId == roomId) {
      return; // no-op — evita rebuild do detail/master
    }
    _current = (epk: epk, roomId: roomId, title: title);
    notifyListeners();
  }

  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}
