using System.Net;
using System.Net.Sockets;
using System.Text;

// Independent HTTP server without external NuGet dependencies. Use the
// current worktree path to make cross-project output/routing errors visible.
var server = new TcpListener(IPAddress.Loopback, 0);
server.Start();
Console.WriteLine($"PORT:{((IPEndPoint)server.LocalEndpoint).Port}");
_ = Task.Run(async () => {
    while (true) {
        using var client = await server.AcceptTcpClientAsync();
        // Consume the HTTP request before closing the socket. Leaving unread
        // request bytes can cause a TCP reset instead of a complete response.
        using var request = new StreamReader(client.GetStream(), Encoding.ASCII,
            false, 1024, leaveOpen: true);
        while (await request.ReadLineAsync() is { Length: > 0 }) { }
        var body = Encoding.UTF8.GetBytes(Directory.GetCurrentDirectory());
        var header = Encoding.ASCII.GetBytes($"HTTP/1.1 200 OK\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n");
        await client.GetStream().WriteAsync(header);
        await client.GetStream().WriteAsync(body);
    }
});
while (Console.ReadLine() is { } line) {
    Console.WriteLine(line == "build" ? "BUILDING" : "READY");
}
server.Stop();
