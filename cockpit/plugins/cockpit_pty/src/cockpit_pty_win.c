#include <stdio.h>
#include <Windows.h>

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
    if (working_directory == NULL)
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
}

typedef struct PtyHandle
{
    PHANDLE inputWriteSide;

    PHANDLE outputReadSide;

    HPCON hPty;

    DWORD dwProcessId;

    BOOL ackRead;

    HANDLE hMutex;

} PtyHandle;

char *error_message = NULL;

// Backing storage for formatted error messages (e.g. CreateProcessW's
// GetLastError code). pty_error() returns this so the exact Win32 failure
// surfaces in the Dart exception instead of only a printf the GUI swallows.
static char error_buf[512];

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

    STARTUPINFOEX startupInfo;

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.StartupInfo.cb = sizeof(startupInfo);

    // Clear the child's inherited std handles (STARTF_USESTDHANDLES with NULL)
    // ONLY when this host process itself owns a real console (e.g. `flutter
    // run`, launched from a terminal). There, without it, the child would
    // inherit the host's real console instead of the ConPTY and its output
    // would never reach our pipe — the terminal view stays blank.
    //
    // In a GUI build (release, no console) the hack is both unnecessary and
    // harmful: NULL std handles make console programs see their stdio as
    // *redirected*, so PowerShell disables PSReadLine ("console is running
    // without PSReadLine"). Without the hack, the pseudoconsole attribute plus
    // bInheritHandles=FALSE already route all I/O through the ConPTY — the
    // canonical ConPTY pattern — and PSReadLine loads normally.
    if (GetConsoleWindow() != NULL)
    {
        startupInfo.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
        startupInfo.StartupInfo.hStdInput = NULL;
        startupInfo.StartupInfo.hStdOutput = NULL;
        startupInfo.StartupInfo.hStdError = NULL;
    }

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

    ok = CreateProcessW(NULL,
                        command,
                        NULL,
                        NULL,
                        FALSE,
                        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                        environment_block,
                        working_directory,
                        &startupInfo.StartupInfo,
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

    return pty;
}

FFI_PLUGIN_EXPORT void pty_write(PtyHandle *handle, char *buffer, int length)
{
    DWORD bytesWritten;

    WriteFile(handle->inputWriteSide, buffer, length, &bytesWritten, NULL);

    FlushFileBuffers(handle->inputWriteSide);

    return;
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

FFI_PLUGIN_EXPORT int pty_getpid(PtyHandle *handle)
{
    return (int)handle->dwProcessId;
}

FFI_PLUGIN_EXPORT char *pty_error()
{
    return error_message;
}
