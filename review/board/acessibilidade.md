# Acessibilidade nativa do Canvas Board no Windows

Em 14/11/2026, a janela de documento do executável Windows Release abriu o fluxo `approval.board` em um desktop Win32 privado, com armazenamento de teste separado. Um segundo processo no mesmo desktop consultou as APIs de acessibilidade do Windows. O idioma da interface nessa execução era inglês e os rótulos do documento estavam em português.

| Objeto | Nome entregue por UI Automation | Tipo |
| --- | --- | --- |
| Primeira etapa | Process · Receber pedido | Button |
| Decisão | Decision · Pedido aprovado? | Button |
| Conexão de entrada | Connector · From Process · Receber pedido to Decision · Pedido aprovado? | Button |
| Conexão de saída | Connector · Sim · From Decision · Pedido aprovado? to Process · Liberar pagamento | Button |
| Última etapa | Process · Liberar pagamento | Button |

**Seleção.** Na primeira etapa, a ação padrão da interface MSAA alterou o estado de `0x300000` para `0x300002`. O bit acrescentado, `STATE_SYSTEM_SELECTED`, confirma que a seleção do Canvas chegou à camada nativa. Nenhuma tecla global foi enviada. A UIA ofereceu `InvokePattern` para o objeto, mas a invocação direta no desktop privado devolveu uma exceção Win32 (“Hot key is already registered”). O resultado de seleção acima veio da ação MSAA.

**Ativação da árvore.** Na primeira execução, 18 consultas UIA encontraram somente a moldura da janela e nenhum descendente em `FLUTTERVIEW`. Na segunda execução, o cliente solicitou também `AccessibleObjectFromWindow(OBJID_CLIENT)` do controle Flutter. Em seguida a mesma consulta por descendentes UIA encontrou os cinco objetos da tabela. O teste confirma o conteúdo exposto após ativação. A descoberta inicial por um leitor de tela real e o anúncio falado de seleção, foco e conectores ainda precisam de uma sessão com Narrador.

**Referência da execução.** Windows 10.0.26200.0, módulo Dart Release `data/app.so` com SHA-256 `E090E6420C051A8E67152B64B64BA28CD272A6365DCEC9C43A38D98AD6DF827F`. O processo de inspeção limitou a consulta às janelas do PID do teste. [Documento utilizado](../../cockpit/cli/skills/cockpit-canvas/templates/approval.board)

## Verificação da build 5558fc00

A nova compilação Release abriu a cópia local Aprovacao.board em janela visível. Em um desktop privado, outra instância abriu o exemplo da skill. A UI Automation expôs novamente as três formas e as duas conexões com os mesmos nomes da tabela. A primeira ação padrão MSAA em Receber pedido mudou o estado de 3145728 para 3145730. O módulo Dart verificado tem SHA-256 B7F551B0D3DA95D9C8C339C6AC30E3D54E73ACC3823741A291E98571ABFF1DAF. A DLL do motor no bundle foi reposta a partir do SDK Release após a compilação e conferida por hash. A leitura falada pelo Narrador continua pendente.
