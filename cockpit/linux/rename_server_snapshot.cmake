# Dart >= 3.14 no Linux: `dart build cli` gera o runtime em bin/<pkg> e o
# snapshot AOT em lib/libdartaot<pkg>.so, resolvido pelo BASENAME do executável
# (runtime/bin/main_impl.cc, ResolveCliSnapshotPath). Como batizamos o exe de
# `cockpit-server`, o snapshot precisa acompanhar; senão o runtime não acha o
# .so e trata o primeiro argumento (`--socket ...`) como snapshot:
# "<sock> is not an AOT snapshot, it cannot be run with 'dartaotruntime'".
# Em Dart < 3.14 o exe é um AOT auto-contido e o .so não existe: no-op.
#
# Uso: cmake -DBUNDLE_DIR=<dir> -P rename_server_snapshot.cmake
set(_old "${BUNDLE_DIR}/lib/libdartaotcockpit_server.so")
set(_new "${BUNDLE_DIR}/lib/libdartaotcockpit-server.so")
if(EXISTS "${_old}")
  file(RENAME "${_old}" "${_new}")
  message(STATUS "cockpit-server: snapshot renomeado para ${_new}")
endif()
