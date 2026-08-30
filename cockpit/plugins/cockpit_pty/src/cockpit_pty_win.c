#include <stdio.h>
#include <string.h>
#include <Windows.h>
#include <TlHelp32.h>

#include "cockpit_pty.h"

#include "include/dart_api.h"
#include "include/dart_api_dl.h"
#include "include/dart_native_api.h"

// Monta a lpCommandLine do CreateProcessW.
//
// NB: NÃO prefixe o `executable` aqui. Chamamos o CreateProcessW com
// `lpApplicationName == NULL`, então o Windows tira o nome do programa da
// própria command line — ela tem que ser exatamente `argv[0] argv[1] ...`. E o
// `arguments[0]` JÁ é o executável: o lado Dart preenche argv[0] com ele,
// seguindo a convenção do execv (POSIX), que o caminho Unix deste mesmo pacote
// usa.
//
// Escrever o `executable` aqui também duplicava o nome em TODA command line
// (`pwsh.exe pwsh.exe`). Passou despercebido porque os shells comuns são
// tolerantes — o `powershell.exe` trata o token extra como comando e abre um
// shell aninhado, o `cmd.exe` descarta —, mas o `pwsh.exe` (PowerShell 7) tem
// parser estrito e recusa ("The argument 'pwsh.exe' is not recognized"), e um
// `wsl.exe -d <distro>` viraria `wsl.exe wsl.exe -d <distro>`, rodando a distro
// errada.
static LPWSTR build_command(char *executable, char **arguments)
{
    // Sem argv utilizável: cai no executável sozinho, senão a command line sairia
    // vazia e o CreateProcessW falharia.
    if (arguments == NULL || arguments[0] == NULL)
    {
        if (executable == NULL)
        {
            return NULL;
        }

        int length = (int)strlen(executable);
        LPWSTR command = malloc((length + 1) * sizeof(WCHAR));

        if (command != NULL)
        {
            for (int j = 0; j <= length; j++)
            {
                command[j] = (WCHAR)executable[j];
            }
        }

        return command;
    }

    int command_length = 0;

    {
        int i = 0;

        while (arguments[i] != NULL)
        {
            // +1 pelo espaço separador (sobra um byte no 1º, que não leva).
            command_length += (int)strlen(arguments[i]) + 1;
            i++;
        }
    }

    LPWSTR command = malloc((command_length + 1) * sizeof(WCHAR));

    if (command != NULL)
    {
        int i = 0;
        int j = 0;

        while (arguments[j] != NULL)
        {
            if (j > 0)
            {
                command[i++] = ' ';
            }

            int k = 0;

            while (arguments[j][k] != 0)
            {
                command[i] = (WCHAR)arguments[j][k];
                i++;
                k++;
            }

            j++;
        }

        command[i] = 0;
    }

    return command;
}

static LPWSTR build_environment(char **environment)
{
    LPWSTR environment_block = NULL;
    int environment_block_length = 0;

    if (environment != NULL)
    {
        int i = 0;

        while (environment[i] != NULL)
        {
            environment_block_length += (int)strlen(environment[i]) + 1;
            i++;
        }
    }

    environment_block = malloc((environment_block_length + 1) * sizeof(WCHAR));

    if (environment_block != NULL)
    {
        int i = 0;

        if (environment != NULL)
        {
            int j = 0;

            while (environment[j] != NULL)
            {
                int k = 0;

                while (environment[j][k] != 0)
                {
                    environment_block[i] = (WCHAR)environment[j][k];
                    i++;
                    k++;
                }

                environment_block[i++] = 0;

                j++;
            }
        }

        environment_block[i] = 0;
    }

    return environment_block;
}

static LPWSTR build_working_directory(char *working_directory)
{
    // Vazio é o mesmo que ausente. O CreateProcessW recusa
    // `lpCurrentDirectory = L""` com ERROR_INVALID_NAME (123) e o processo não
    // nasce; NULL significa "herde o do pai", que é o que se quer. O lado
    // POSIX já tratava isso (testa strlen antes do chdir).
    if (working_directory == NULL || working_directory[0] == 0)
    {
        return NULL;
    }

    int working_directory_length = (int)strlen(working_directory);

    LPWSTR working_directory_block = malloc((working_directory_length + 1) * sizeof(WCHAR));

    if (working_directory_block == NULL)
    {
        return NULL;
    }

    int i = 0;

    while (working_directory[i] != 0)
    {
        // NB: keep the index increment in its own statement. Writing
        // `block[i] = src[i++]` reads and modifies `i` with no sequence point
        // between the two uses — undefined behavior. MSVC's ARM64 backend
        // evaluates it differently than x64/clang, corrupting the path so
        // CreateProcessW fails ("Failed to create process") on Windows ARM.
        working_directory_block[i] = (WCHAR)working_directory[i];
        i++;
    }

    working_directory_block[i] = 0;

    return working_directory_block;
}

typedef struct ReadLoopOptions
{
    HANDLE fd;

    Dart_Port port;

    HANDLE hMutex;

    BOOL ackRead;

} ReadLoopOptions;

static DWORD WINAPI read_loop(LPVOID arg)
{
    ReadLoopOptions *options = (ReadLoopOptions *)arg;

    char buffer[1024];

    while (1)
    {
        DWORD readlen = 0;

        if (options->ackRead)
        {
            WaitForSingleObject(options->hMutex, INFINITE);
        }

        BOOL ok = ReadFile(options->fd, buffer, sizeof(buffer), &readlen, NULL);

        if (!ok)
        {
            break;
        }

        if (readlen <= 0)
        {
            break;
        }

        Dart_CObject result;
        result.type = Dart_CObject_kTypedData;
        result.value.as_typed_data.type = Dart_TypedData_kUint8;
        result.value.as_typed_data.length = readlen;
        result.value.as_typed_data.values = (uint8_t *)buffer;

        Dart_PostCObject_DL(options->port, &result);
    }

    free(options);
    return 0;
}

static void start_read_thread(HANDLE fd, Dart_Port port, HANDLE mutex, BOOL ackRead)
{
    ReadLoopOptions *options = malloc(sizeof(ReadLoopOptions));

    options->fd = fd;
    options->port = port;
    options->hMutex = mutex;
    options->ackRead = ackRead;

    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, read_loop, options, 0, &thread_id);

    if (thread == NULL)
    {
        free(options);
    }
    else
    {
        // The running thread owns its lifetime; retaining this HANDLE leaks one
        // kernel object per terminal even after the thread exits.
        CloseHandle(thread);
    }
}

typedef struct WaitExitOptions
{
    HANDLE pid;

    Dart_Port port;

    HANDLE hMutex;

} WaitExitOptions;

static DWORD WINAPI wait_exit_thread(LPVOID arg)
{
    WaitExitOptions *options = (WaitExitOptions *)arg;

    DWORD exit_code = 0;

    WaitForSingleObject(options->pid, INFINITE);

    GetExitCodeProcess(options->pid, &exit_code);

    CloseHandle(options->pid);
    CloseHandle(options->hMutex);
    Dart_PostInteger_DL(options->port, exit_code);

    free(options);
    return 0;
}

static void start_wait_exit_thread(HANDLE pid, Dart_Port port, HANDLE mutex)
{
    WaitExitOptions *options = malloc(sizeof(WaitExitOptions));

    options->pid = pid;
    options->port = port;
    options->hMutex = mutex;
    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, wait_exit_thread, options, 0, &thread_id);

    if (thread == NULL)
    {
        free(options);
    }
    else
    {
        CloseHandle(thread);
    }
}

// --- Writer thread ----------------------------------------------------------
//
// pty_write é FFI síncrono na thread de plataforma (= thread de UI no Flutter
// Windows). Fazer I/O bloqueante ali congela a janela inteira: um
// FlushFileBuffers herdado do kyroon_pty bloqueava até o ConPTY consumir TUDO
// que foi escrito e travou a UI em produção (plano 58); e o próprio WriteFile
// bloqueia quando o buffer do pipe enche e o filho não drena (mesma classe de
// bug, só mais rara). Pipes anônimos não suportam overlapped I/O, então a
// saída é uma writer thread por PTY com fila FIFO: pty_write só copia o
// buffer, enfileira e sinaliza — nunca bloqueia.

typedef struct WriteChunk
{
    struct WriteChunk *next;

    int length;

    char data[1]; // alocado com sizeof(WriteChunk) + length

} WriteChunk;

typedef struct WriteQueue
{
    HANDLE fd;

    CRITICAL_SECTION lock;

    CONDITION_VARIABLE hasData;

    WriteChunk *head;

    WriteChunk *tail;

    // WriteFile falhou (pipe fechado) — writes futuros são descartados.
    BOOL broken;

} WriteQueue;

static DWORD WINAPI write_loop(LPVOID arg)
{
    WriteQueue *queue = (WriteQueue *)arg;

    while (1)
    {
        EnterCriticalSection(&queue->lock);

        while (queue->head == NULL)
        {
            SleepConditionVariableCS(&queue->hasData, &queue->lock, INFINITE);
        }

        WriteChunk *chunk = queue->head;
        queue->head = chunk->next;

        if (queue->head == NULL)
        {
            queue->tail = NULL;
        }

        LeaveCriticalSection(&queue->lock);

        DWORD bytesWritten;

        BOOL ok = WriteFile(queue->fd, chunk->data, chunk->length, &bytesWritten, NULL);

        free(chunk);

        if (!ok)
        {
            // Pipe fechado (ConPTY/filho encerrou). Marca, descarta o que
            // sobrou e sai. A WriteQueue em si vive até o fim do processo —
            // mesmo ciclo de vida do PtyHandle e do read_loop, que também
            // não têm caminho de destruição.
            EnterCriticalSection(&queue->lock);

            queue->broken = TRUE;

            WriteChunk *pending = queue->head;
            queue->head = NULL;
            queue->tail = NULL;

            LeaveCriticalSection(&queue->lock);

            while (pending != NULL)
            {
                WriteChunk *next = pending->next;
                free(pending);
                pending = next;
            }

            return 0;
        }
    }
}

static WriteQueue *start_write_thread(HANDLE fd)
{
    WriteQueue *queue = malloc(sizeof(WriteQueue));

    if (queue == NULL)
    {
        return NULL;
    }

    queue->fd = fd;
    queue->head = NULL;
    queue->tail = NULL;
    queue->broken = FALSE;

    InitializeCriticalSection(&queue->lock);
    InitializeConditionVariable(&queue->hasData);

    DWORD thread_id;

    HANDLE thread = CreateThread(NULL, 0, write_loop, queue, 0, &thread_id);

    if (thread == NULL)
    {
        DeleteCriticalSection(&queue->lock);
        free(queue);
        return NULL;
    }

    // Mesma razão do start_read_thread: a thread é dona da própria vida;
    // reter o HANDLE só vazaria um objeto de kernel por terminal.
    CloseHandle(thread);

    return queue;
}

typedef struct PtyHandle
{
    PHANDLE inputWriteSide;

    PHANDLE outputReadSide;

    HPCON hPty;

    DWORD dwProcessId;

    BOOL ackRead;

    HANDLE hMutex;

    // Job Object que contém o shell e TODA a sua descendência.
    //
    // No Windows não há sinal nem process group: `TerminateProcess` mata só o
    // processo alvo, e os filhos do shell (mais o conhost do ConPTY) viravam
    // órfãos em "Processos em segundo plano" — issue #163, relatada com
    // PowerShell 7.
    //
    // Criado com JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, o que resolve dois casos
    // de uma vez: `pty_kill` encerra a árvore inteira, e se o processo dono
    // morrer (inclusive por crash, sem chance de rodar código de limpeza) o
    // Windows fecha o job e mata todo mundo sozinho.
    //
    // O handle só é fechado quando o processo dono morre (o plugin não tem
    // `pty_destroy`): fechá-lo antes mataria a árvore, que é exatamente o
    // efeito do KILL_ON_JOB_CLOSE. Custo: um handle de kernel por terminal
    // aberto, devolvido ao SO na saída do processo.
    HANDLE hJob;


    WriteQueue *writeQueue;

} PtyHandle;

char *error_message = NULL;

// Backing storage for formatted error messages (e.g. CreateProcessW's
// GetLastError code). pty_error() returns this so the exact Win32 failure
// surfaces in the Dart exception instead of only a printf the GUI swallows.
static char error_buf[512];

// Serializa a troca dos std handles do processo: eles são GLOBAIS, e o app
// abre várias abas de uma vez (na restauração de layout, três PTYs nascem no
// mesmo instante). Sem o lock, um spawn restaura os handles enquanto o outro
// ainda depende deles estarem limpos.
static INIT_ONCE spawn_lock_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION spawn_lock;

static BOOL CALLBACK init_spawn_lock(PINIT_ONCE once, PVOID param, PVOID *ctx)
{
    (void)once;
    (void)param;
    (void)ctx;
    InitializeCriticalSection(&spawn_lock);
    return TRUE;
}

// Cria o processo com os std handles DESTE processo temporariamente zerados.
//
// O filho não pode herdar o stdio do host: sob `flutter run` isso o mandaria
// pro console do terminal em vez do ConPTY, e dentro do cockpit-server o
// mandaria pros PIPES do servidor — que a GUI drena, então nenhum byte chega à
// aba, e o shell lê EOF no stdin e morre. Foi assim que todo terminal local do
// Windows ficou vazio quando o sidecar passou a criar os PTYs.
//
// Zerar com SetStdHandle NÃO é o mesmo que declarar STARTF_USESTDHANDLES com
// NULL: aqui o filho simplesmente não tem o que herdar, e quem preenche seu
// stdio é o pseudoconsole — então o PowerShell segue vendo console de verdade
// e o PSReadLine carrega. A checagem antiga (`GetConsoleWindow()`) respondia
// "tenho janela de console?", quando a pergunta é "meus handles estão
// limpos?" — o sidecar não tem janela E tem handles sujos, o caso que faltava.
static BOOL spawn_with_clean_std_handles(LPWSTR command,
                                         LPWSTR environment_block,
                                         LPWSTR working_directory,
                                         STARTUPINFOEXW *startupInfo,
                                         PROCESS_INFORMATION *processInfo)
{
    InitOnceExecuteOnce(&spawn_lock_once, init_spawn_lock, NULL, NULL);
    EnterCriticalSection(&spawn_lock);

    HANDLE previous_in = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE previous_out = GetStdHandle(STD_OUTPUT_HANDLE);
    HANDLE previous_err = GetStdHandle(STD_ERROR_HANDLE);

    SetStdHandle(STD_INPUT_HANDLE, NULL);
    SetStdHandle(STD_OUTPUT_HANDLE, NULL);
    SetStdHandle(STD_ERROR_HANDLE, NULL);

    BOOL ok = CreateProcessW(NULL,
                             command,
                             NULL,
                             NULL,
                             FALSE,
                             EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                             environment_block,
                             working_directory,
                             &startupInfo->StartupInfo,
                             processInfo);

    DWORD last_error = GetLastError();

    // Restaura SEMPRE, inclusive no erro: o host continua precisando do seu
    // próprio stdio (o cockpit-server escreve log no stderr).
    SetStdHandle(STD_INPUT_HANDLE, previous_in);
    SetStdHandle(STD_OUTPUT_HANDLE, previous_out);
    SetStdHandle(STD_ERROR_HANDLE, previous_err);

    LeaveCriticalSection(&spawn_lock);

    SetLastError(last_error);
    return ok;
}

FFI_PLUGIN_EXPORT PtyHandle *pty_create(PtyOptions *options)
{
    HANDLE inputReadSide = NULL;
    HANDLE inputWriteSide = NULL;

    HANDLE outputReadSide = NULL;
    HANDLE outputWriteSide = NULL;

    if (!CreatePipe(&inputReadSide, &inputWriteSide, NULL, 0))
    {
        error_message = "Failed to create input pipe";
        return NULL;
    }

    if (!CreatePipe(&outputReadSide, &outputWriteSide, NULL, 0))
    {
        error_message = "Failed to create output pipe";
        return NULL;
    }

    COORD size;

    size.X = options->cols;
    size.Y = options->rows;

    HPCON hPty;

    HRESULT result = CreatePseudoConsole(size, inputReadSide, outputWriteSide, 0, &hPty);

    if (FAILED(result))
    {
        error_message = "Failed to create pseudo console";
        return NULL;
    }

    // Explicitamente a variante WIDE: sem o sufixo, `STARTUPINFOEX` vira a
    // ANSI quando a unidade não é compilada com UNICODE, e o CreateProcessW
    // recebe um ponteiro do tipo errado (aviso C4133). Os layouts coincidem,
    // então funcionava por acidente.
    STARTUPINFOEXW startupInfo;

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.StartupInfo.cb = sizeof(startupInfo);

    // Sem STARTF_USESTDHANDLES: o atributo do pseudoconsole é quem preenche o
    // stdio do filho. Declarar handles NULL explicitamente faz o PowerShell
    // enxergar stdio REDIRECIONADO e desligar o PSReadLine — foi o motivo de
    // 6ec33f2. O que o filho não pode é herdar o stdio DESTE processo; disso
    // cuida `spawn_with_clean_std_handles`, logo abaixo.

    SIZE_T bytesRequired;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytesRequired);
    startupInfo.lpAttributeList = (PPROC_THREAD_ATTRIBUTE_LIST)malloc(bytesRequired);

    BOOL ok = InitializeProcThreadAttributeList(startupInfo.lpAttributeList, 1, 0, &bytesRequired);

    if (!ok)
    {
        error_message = "Failed to initialize proc thread attribute list";
        return NULL;
    }

    ok = UpdateProcThreadAttribute(startupInfo.lpAttributeList,
                                   0,
                                   PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                   hPty,
                                   sizeof(hPty),
                                   NULL,
                                   NULL);

    if (!ok)
    {
        error_message = "Failed to update proc thread attribute list";
        return NULL;
    }

    LPWSTR command = build_command(options->executable, options->arguments);

    LPWSTR environment_block = build_environment(options->environment);

    LPWSTR working_directory = build_working_directory(options->working_directory);

    PROCESS_INFORMATION processInfo;
    ZeroMemory(&processInfo, sizeof(processInfo));

    // NOTE: a blocking Sleep(1000) used to sit here. pty_create runs
    // synchronously on the Dart main isolate (FFI), so that froze the whole UI
    // for a full second on every spawn. ConPTY is ready as soon as the pseudo
    // console + attribute list are set up above, so the wait is unnecessary.

    ok = spawn_with_clean_std_handles(command,
                                      environment_block,
                                      working_directory,
                                      &startupInfo,
                                      &processInfo);

    if (command != NULL)
    {
        free(command);
    }

    if (environment_block != NULL)
    {
        free(environment_block);
    }

    if (working_directory != NULL)
    {
        free(working_directory);
    }

    if (!ok)
    {
        DWORD error = GetLastError();
        snprintf(error_buf, sizeof(error_buf),
                 "CreateProcessW failed: GetLastError=%lu (exe=\"%s\", cwd=\"%s\")",
                 error,
                 options->executable != NULL ? options->executable : "(null)",
                 options->working_directory != NULL ? options->working_directory : "(null)");
        error_message = error_buf;
        return NULL;
    }

    // Job Object: garante que o shell morra junto com o dono (o
    // KILL_ON_JOB_CLOSE cobre até crash, sem chance de rodar limpeza).
    //
    // NÃO é o mecanismo que alcança a descendência: medido no Windows 10 com
    // PowerShell 7, o job ficava com `assigned=1` mesmo com um filho vivo — os
    // filhos do shell não estavam herdando o job. Quem encerra a árvore é a
    // varredura explícita em `pty_kill`. Falhar aqui não impede nada.
    HANDLE hJob = CreateJobObjectW(NULL, NULL);
    if (hJob != NULL)
    {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
        limits.BasicLimitInformation.LimitFlags =
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        if (!SetInformationJobObject(hJob,
                                     JobObjectExtendedLimitInformation,
                                     &limits,
                                     sizeof(limits)) ||
            !AssignProcessToJobObject(hJob, processInfo.hProcess))
        {
            CloseHandle(hJob);
            hJob = NULL;
        }
    }

    // CreatePseudoConsole duplicated inputReadSide / outputWriteSide into conhost,
    // so the parent must release its own copies now. Keeping outputWriteSide open
    // would prevent the read loop from ever seeing EOF when the child exits (the
    // pipe still has a live writer — this host). Closing both leaves the ConPTY
    // as the sole owner, which is what the Microsoft sample does.
    CloseHandle(inputReadSide);
    CloseHandle(outputWriteSide);

    DeleteProcThreadAttributeList(startupInfo.lpAttributeList);
    free(startupInfo.lpAttributeList);

    CloseHandle(processInfo.hThread);

    HANDLE mutex = CreateSemaphore(
        NULL, // default security attributes
        1,    // initial count
        1,    // maximum count
        NULL);

    start_read_thread(outputReadSide, options->stdout_port, mutex, options->ackRead);

    start_wait_exit_thread(processInfo.hProcess, options->exit_port, mutex);

    PtyHandle *pty = malloc(sizeof(PtyHandle));

    if (pty == NULL)
    {
        error_message = "Failed to allocate pty handle";
        return NULL;
    }

    pty->inputWriteSide = inputWriteSide;
    pty->outputReadSide = outputReadSide;
    pty->hPty = hPty;
    pty->dwProcessId = processInfo.dwProcessId;
    pty->ackRead = options->ackRead;
    pty->hMutex = mutex;
    pty->hJob = hJob;
    pty->writeQueue = start_write_thread(inputWriteSide);

    return pty;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length)
{
    // NB: NADA de I/O síncrono aqui. Esta função roda na thread de plataforma
    // (UI) via FFI — a escrita real acontece na writer thread (ver o bloco
    // "Writer thread" acima). Em particular, NÃO reintroduza FlushFileBuffers:
    // em pipe ele bloqueia até o consumidor ler tudo e congelou a UI em
    // produção (plano 58).

    if (length <= 0)
    {
        return;
    }

    WriteQueue *queue = handle->writeQueue;

    if (queue == NULL)
    {
        // Writer thread não subiu (falha rara no spawn): escreve direto em
        // vez de perder input. Pode bloquear com o pipe cheio, mas é o
        // degradê menos ruim.
        DWORD bytesWritten;
        WriteFile(handle->inputWriteSide, buffer, length, &bytesWritten, NULL);
        return;
    }

    WriteChunk *chunk = malloc(sizeof(WriteChunk) + (size_t)length);

    if (chunk == NULL)
    {
        return;
    }

    chunk->next = NULL;
    chunk->length = length;
    memcpy(chunk->data, buffer, (size_t)length);

    EnterCriticalSection(&queue->lock);

    if (queue->broken)
    {
        LeaveCriticalSection(&queue->lock);
        free(chunk);
        return;
    }

    if (queue->tail != NULL)
    {
        queue->tail->next = chunk;
    }
    else
    {
        queue->head = chunk;
    }

    queue->tail = chunk;

    LeaveCriticalSection(&queue->lock);

    WakeConditionVariable(&queue->hasData);
}

FFI_PLUGIN_EXPORT void pty_ack_read(PtyHandle *handle)
{
    if (handle->ackRead)
    {
        ReleaseSemaphore(handle->hMutex, 1, NULL);
    }
}

FFI_PLUGIN_EXPORT int pty_resize(PtyHandle *handle, int rows, int cols)
{
    COORD size;

    size.X = cols;
    size.Y = rows;

    return ResizePseudoConsole(handle->hPty, size);
}

/// Preenche [out] com os descendentes de [root] (filhos, netos, ...), em
/// largura, e devolve quantos foram encontrados. O próprio [root] fica de fora:
/// quem o encerra é o chamador.
///
/// Um único snapshot serve para toda a varredura — o mapa pai→filho é
/// percorrido em memória, então a árvore fica consistente mesmo que processos
/// nasçam ou morram durante a operação.
static DWORD collect_descendants(DWORD root, DWORD *out, DWORD capacity)
{
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
    {
        return 0;
    }

    // Tabela plana (pid, ppid) do snapshot; 4096 cobre com folga qualquer
    // máquina real, e estourar só significa varrer menos, nunca corromper.
    static const DWORD kMaxProcesses = 4096;
    DWORD *pids = (DWORD *)malloc(kMaxProcesses * sizeof(DWORD));
    DWORD *parents = (DWORD *)malloc(kMaxProcesses * sizeof(DWORD));
    if (pids == NULL || parents == NULL)
    {
        free(pids);
        free(parents);
        CloseHandle(snapshot);
        return 0;
    }

    DWORD total = 0;
    PROCESSENTRY32W entry;
    entry.dwSize = sizeof(entry);
    if (Process32FirstW(snapshot, &entry))
    {
        do
        {
            if (total >= kMaxProcesses)
            {
                break;
            }
            pids[total] = entry.th32ProcessID;
            parents[total] = entry.th32ParentProcessID;
            total++;
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);

    // BFS com `out` servindo de fila: `head` é quem está sendo expandido,
    // `found` é o fim. Descartar pid 0 e o próprio root impede ciclo — no
    // Windows o ppid é reciclável e uma entrada degenerada poderia apontar de
    // volta para dentro da árvore.
    DWORD found = 0;
    DWORD head = 0;
    DWORD parent = root;
    for (;;)
    {
        for (DWORD i = 0; i < total && found < capacity; i++)
        {
            if (parents[i] == parent && pids[i] != 0 && pids[i] != root)
            {
                out[found++] = pids[i];
            }
        }
        if (head >= found || found >= capacity)
        {
            break;
        }
        parent = out[head++];
    }

    free(pids);
    free(parents);
    return found;
}

/// Encerra o shell e TUDO o que ele criou.
///
/// Duas camadas, ambas necessárias: `TerminateJobObject` (o shell e o que o
/// Windows tiver de fato colocado no job) **e** a varredura explícita da árvore
/// de descendentes — ver o comentário no corpo sobre por que o job sozinho não
/// resolveu a issue #163 nesta plataforma.
///
/// Devolve 0 em caso de sucesso. Sem job (a criação falhou), encerra ao menos o
/// shell, que é o comportamento antigo.
FFI_PLUGIN_EXPORT int pty_kill(PtyHandle *handle)
{
    if (handle == NULL)
    {
        return -1;
    }
    // A ÁRVORE É ENUMERADA ANTES de qualquer kill. Depois de o shell morrer, o
    // vínculo pai→filho é inútil: o campo ppid do órfão segue apontando para um
    // pid morto, que o Windows pode reciclar — matar por ele arriscaria acertar
    // um processo alheio.
    DWORD descendants[256];
    DWORD found = collect_descendants(handle->dwProcessId, descendants, 256);

    BOOL ok;
    if (handle->hJob != NULL)
    {
        ok = TerminateJobObject(handle->hJob, 1);
    }
    else
    {
        HANDLE process =
            OpenProcess(PROCESS_TERMINATE, FALSE, handle->dwProcessId);
        if (process == NULL)
        {
            return -1;
        }
        ok = TerminateProcess(process, 1);
        CloseHandle(process);
    }

    // Varredura da árvore, SEMPRE — não é plano B do job.
    //
    // O job sozinho não basta: medido no Windows 10 com PowerShell 7, o job
    // criado em `pty_create` continha apenas o shell (`assigned=1`) mesmo com um
    // filho vivo, e o `TerminateJobObject` devolvia sucesso deixando o
    // descendente órfão — o sintoma exato da issue #163, que a correção anterior
    // não eliminou. A herança automática de job não se confirmou aqui, então
    // encerrar quem já era descendente é o que fecha o caso de verdade.
    for (DWORD i = 0; i < found; i++)
    {
        HANDLE child = OpenProcess(PROCESS_TERMINATE, FALSE, descendants[i]);
        if (child != NULL)
        {
            TerminateProcess(child, 1);
            CloseHandle(child);
        }
    }
    return ok ? 0 : -1;
}

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return (int)handle->dwProcessId;
}

FFI_PLUGIN_EXPORT char *pty_error()
{
    return error_message;
}
