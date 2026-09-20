/// Segura o sleep por **inatividade** do sistema (não da tela) enquanto o
/// Cockpit está servindo um host remoto. Contraparte do que um navegador faz
/// ao tocar vídeo, só que com a assertion de *sistema*: a tela pode apagar,
/// a máquina não dorme.
///
/// O que NÃO cobre (limite do SO, não nosso): fechar a tampa de um notebook é
/// sleep forçado, nenhuma assertion segura. Só clamshell com energia + monitor
/// externo, ou `pmset disablesleep` (root), passam por cima. A UI avisa.
library;

export 'src/keep_awake.dart';
export 'src/power_source.dart';
