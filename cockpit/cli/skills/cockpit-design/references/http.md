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
