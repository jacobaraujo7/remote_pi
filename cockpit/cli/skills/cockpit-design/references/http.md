# `.http` request files

REST Client / JetBrains HTTP Client syntax: `###` separates requests, `@name =
value` declares a file variable, `{{name}}` interpolates it. The app renders
the file as a request tab (editor + response) and the CLI runs it:
`cockpit http list <file>` / `cockpit http run <file> [--request <name|index>]`
(details in cockpit-cli, `references/verbs.md`).

```http
@baseUrl = https://api.example.com
@token = abc123

### List users
GET {{baseUrl}}/users?page=1
Accept: application/json
Authorization: Bearer {{token}}

### Create user
POST {{baseUrl}}/users
Content-Type: application/json

{"name": "Ana"}
```

Prefer a `.http` over a one-off `curl` whenever the human should see the
request too: they can re-run and tweak it from the tab. A 4xx/5xx is a normal
response, not an error: check `status`.

Scripts can run before a request or handle its response, either inline or
from JavaScript files. Paths are relative to the `.http` file (absolute paths
and quoted paths with spaces also work):

```http
### Prepare variables and check the response
< ./scripts/prepare.js
< {% client.log(request.variables.get('id')); %}
GET https://api.example.com/users/{{id}}
> ./scripts/check-response.js
```

Pre-request file references must precede the HTTP verb. After the verb,
`< ./file` imports the request body, including `.js` payloads. Multiple inline
and external scripts execute in declaration order and share a JavaScript
scope within each phase. External files have the same `request`, `client`
and `console` APIs as inline scripts; response handlers also receive
`response`. Files are read fresh on every run. Each phase has a 2 second
execution limit. A pre-request failure stops the request; a response handler
failure keeps the response available.

The editor closes JavaScript pairs inside both `< {% ... %}` and
`> {% ... %}`. In request bodies it uses the request's `Content-Type`:
JSON (`application/json`, `text/json`, and `+json` types) completes braces,
brackets, and double quotes; XML (`application/xml`, `text/xml`, and `+xml`
types) and HTML (`text/html`) complete tags and attribute quotes. Enter
indents paired blocks. HTML void elements such as `br`, `img`, and `input`
do not get closing tags. Headers, URLs, and other body types keep their
normal editing behavior.
