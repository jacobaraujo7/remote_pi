## Contexto

Unifica Terminais, Boxes e Grafo no mesmo workspace, com a identidade **um terminal = uma box** e função/ferramenta opcionais. A interface e as operações de terminais/docks existentes são preservadas.

## O que muda

- Seletor **Terminais / Boxes / Grafo** e apresentação persistida por workspace. Layouts antigos começam em Terminais.
- **Boxes:** busca por nome/função, filtro de estado, arrasto vertical com ordem salva e prévia de uma sessão (60% inicialmente). Selecionar não abre/foca o terminal; duplo clique abre em Terminais.
- **Grafo:** funções, vínculos planejados, atividade observada e subagentes temporários, com prévia de uma sessão (35% inicialmente). Métricas ausentes aparecem como indisponíveis; hooks/protocolo observam atividade local e remota.
- **Inspector compartilhado:** nome, função opcional, ferramenta/modelo, conexões e ações de sessão explícitas. Salvar não inicia CLI. Em áreas estreitas, o painel se sobrepõe.
- Hosts estáveis de panes, abas e workspaces preservam a identidade das views; inclui correção do travamento no X. Ordem e modo entram imediatamente no store para o flush do fechamento.
- Main atual integrada, incluindo #268: preserva o pipeline de anexos já entregue. Testes do paste simples foram substituídos pela cobertura mais ampla de anexos da main.

## Imagens dos novos layouts

Renderizações dos **componentes reais com dados fictícios**, não screenshots do desktop nem evidência de macOS. Fonte Geist offline; omitem chrome/laterais e usam um cabeçalho de terminal da fixture. [Reprodução](https://github.com/jacobaraujo7/remote_pi/blob/f7373a345aa3d37cf8abb87541ea4727b4242961/cockpit/review/workspace-layouts/README.md).

### Boxes: lista, alça de arrasto e prévia

![Boxes](https://raw.githubusercontent.com/jacobaraujo7/remote_pi/f7373a345aa3d37cf8abb87541ea4727b4242961/cockpit/review/workspace-layouts/boxes.png)

### Grafo: conexões e prévia

![Grafo](https://raw.githubusercontent.com/jacobaraujo7/remote_pi/f7373a345aa3d37cf8abb87541ea4727b4242961/cockpit/review/workspace-layouts/graph.png)

### Inspector: configuração e ações explícitas

![Inspector](https://raw.githubusercontent.com/jacobaraujo7/remote_pi/f7373a345aa3d37cf8abb87541ea4727b4242961/cockpit/review/workspace-layouts/inspector.png)

## Validação

- Local: 58 regressões passaram após integrar a main, incluindo Ghostty/xterm, troca de modo, fechamento e anexos. Rodada adicional: 16 testes passaram, incluindo store real em disco, flush imediato, restauração nos três modos e isolamento de workspaces. Três renders passaram; análise dirigida e diff limpos.
- O teste do fechamento reproduziu o erro no host antigo e passou com o host estável nos dois motores.
- CI anterior em `523195ff`: [Windows passou; builds macOS ARM/Intel falharam por falta do certificado Developer ID](https://github.com/jacobaraujo7/remote_pi/actions/runs/40425724068). O workflow agora fornece ao xcodebuild as opções para build universal sem certificado de distribuição. **Resultado do novo SHA pendente.** A assinatura/publicação de releases não foi alterada.

## Notas para review

@jacobaraujo7, revisar especialmente identidade das views, foco da prévia/inspector, persistência e integração dos anexos.

- **Aceite real em macOS pendente:** sem Mac disponível para validar menus nativos, Cmd+C/V/F, trackpad, Retina e ciclo de janela. Builds/widget tests não substituem esse aceite.
- A verificação manual de fechar/reabrir a janela foi interrompida; a persistência acima foi verificada no store em disco. O fechamento imediato agora entra no caminho de flush.
- #257 permanece independente (status/Ctrl-Tab); conferir sobreposição antes do merge. Sem deploy ou alteração de produção.
