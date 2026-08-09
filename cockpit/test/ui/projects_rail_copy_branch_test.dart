import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/ui/widgets/projects_rail.dart';
import 'package:flutter_test/flutter_test.dart';

/// Resolução da branch do "Copiar branch" do kebab do workspace.
///
/// Em multirepo o item vira submenu (uma entrada por root, como pull/push) e o
/// menu devolve `copy-branch|<root path>`. Traduzir esse path de volta para a
/// branch é a única decisão real da funcionalidade — o resto é a mesma mecânica
/// que pull e push já usam.
void main() {
  const app = (
    path: '/w/mono/app',
    name: 'app',
    git: GitInfo(branch: 'feat/tema-pantera'),
  );
  const backend = (
    path: '/w/mono/backend',
    name: 'backend',
    git: GitInfo(branch: 'main'),
  );
  const docs = (path: '/w/mono/docs', name: 'docs', git: null);

  group('branchOfRoot', () {
    test('single-root devolve a branch da própria raiz', () {
      expect(branchOfRoot(const [app], '/w/mono/app'), 'feat/tema-pantera');
    });

    test('multirepo devolve a branch da root escolhida, não a da primeira', () {
      const roots = <RailRoot>[app, backend];
      expect(branchOfRoot(roots, '/w/mono/backend'), 'main');
      expect(branchOfRoot(roots, '/w/mono/app'), 'feat/tema-pantera');
    });

    test('root sem git não tem branch a copiar', () {
      expect(branchOfRoot(const [app, docs], '/w/mono/docs'), isNull);
    });

    test('path desconhecido não estoura nem copia lixo', () {
      // Acontece se a lista de roots mudar entre abrir o menu e escolher.
      expect(branchOfRoot(const [app], '/w/outro'), isNull);
      expect(branchOfRoot(const [], '/w/mono/app'), isNull);
    });

    test('branch vazia conta como ausente', () {
      // Copiar string vazia limparia o clipboard sem o usuário entender por quê.
      const semBranch = (
        path: '/w/mono/x',
        name: 'x',
        git: GitInfo(branch: ''),
      );
      expect(branchOfRoot(const [semBranch], '/w/mono/x'), isNull);
    });
  });
}
