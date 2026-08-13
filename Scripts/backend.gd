extends Node
## HTTP API client for the FPS NITE backend (FastAPI at BACKEND_URL).
## Login is token-based: paste the token from Discord once, afterwards it's
## validated on every launch via /auth/me and stored in Settings.
## One-shot requests: each call spawns its own HTTPRequest child, so calls can
## overlap safely. Account state is mirrored so UI code can read it directly.

signal account_ready(player: Dictionary)  # token validated, profile loaded
signal auth_failed(code: String, message: String)

const BACKEND_URL := "http://127.0.0.1:8000"

var player_id := -1
var player_name := ""
var player_skin := 0
var auth_token := ""

## Validate a login token (first connect from the launcher AND every launch
## after; the launcher re-sends the stored token).
func login_with_token(token: String) -> void:
	auth_token = token.strip_edges()
	_send(HTTPClient.METHOD_POST, "/api/auth/me", {}, _on_account_response)

## Fire-and-forget skin sync; errors are logged, never surfaced in UI.
func update_skin(index: int) -> void:
	if player_id < 0:
		return
	_send(HTTPClient.METHOD_PATCH, "/api/players/%d" % player_id,
		{"skin_index": index}, func(_ok: bool) -> void: pass)

func clear_token() -> void:
	auth_token = ""
	player_id = -1
	player_name = ""
	player_skin = 0

func _on_account_response(success: bool, data: Variant) -> void:
	if not success:
		return
	if not data is Dictionary or not data.has("id"):
		auth_failed.emit("BAD_RESPONSE", "Server sent an unexpected response.")
		return
	player_id = data["id"]
	player_name = data.get("name", "")
	player_skin = data.get("skin_index", 0)
	account_ready.emit(data)

func _send(method: HTTPClient.Method, path: String, payload: Dictionary, on_done: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 10.0
	add_child(req)
	req.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		on_done.call(code >= 200 and code < 300, _parse_body(code, body))
		req.queue_free())

	var headers := PackedStringArray(["Content-Type: application/json"])
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	req.request(BACKEND_URL + path, headers, method, body)

func _parse_body(code: int, body: PackedByteArray) -> Variant:
	if body.is_empty():
		if code >= 200 and code < 300:
			return {}
		auth_failed.emit("HTTP_%d" % code, "Request failed (%s)." % _http_status_text(code))
		return null
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return null
	if code >= 200 and code < 300:
		return parsed
	var detail: Variant = parsed.get("detail", {})
	if detail is Dictionary and detail.has("code"):
		auth_failed.emit(detail["code"], detail.get("message", "Request failed."))
	else:
		auth_failed.emit("HTTP_%d" % code, "Request failed (%s)." % _http_status_text(code))
	return null

func _http_status_text(code: int) -> String:
	match code:
		400: return "Bad request"
		401: return "Invalid token"
		403: return "Forbidden"
		404: return "Not found"
		409: return "Conflict"
		422: return "Invalid input"
		500: return "Server error"
	return str(code)