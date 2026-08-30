/// Contratos de domínio do Cockpit Remote (plano 58, Wave 0: só Terminais).
library;

export 'src/terminal/terminal_service.dart';
export 'src/fs/file_service.dart';
export 'src/git/git_service.dart';
export 'src/db/db_service.dart';
export 'src/db/db_secret_store.dart';
// Motor de túnel SSH das conexões de banco (plano 54). Mora aqui, e não no
// app, porque quem abre o túnel é a máquina onde a conexão é aberta: o app num
// workspace local, o cockpit-server num remoto (plano 62, onda 2).
export 'src/ssh/ssh_tunnel_config.dart';
export 'src/ssh/ssh_tunnel.dart';
export 'src/ssh/ssh_tunnel_impl.dart';
export 'src/ssh/ssh_key_pem.dart';
export 'src/ssh/local_socks_server.dart';
export 'src/ssh/file_ssh_host_key_store.dart';
