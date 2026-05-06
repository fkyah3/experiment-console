class_name DeepSeekStreamClient
extends Node

signal reasoning_chunk(text: String)
signal content_chunk(text: String)
signal tool_call_chunk(data: Dictionary)
signal stream_finished()
signal usage_received(usage: Dictionary)
signal connection_error(msg: String)

var api_key: String = ""

var is_stream_connected: bool:
	get:
		return _client != null and _client.get_status() == HTTPClient.STATUS_BODY

var _client: HTTPClient
var _buffer: String = ""
var _should_run: bool = false
var _pending_messages: Array = []
var _request_sent: bool = false


func _ready() -> void:
	_client = HTTPClient.new()


func start_streaming(messages: Array) -> void:
	if _should_run:
		return
	_should_run = true
	_pending_messages = messages.duplicate(true)
	_request_sent = false
	_buffer = ""

	var err = _client.connect_to_host("api.deepseek.com", 443, TLSOptions.client())
	if err != OK:
		connection_error.emit("连接失败: " + _err_str(err))
		_should_run = false


func stop() -> void:
	_should_run = false
	_request_sent = false
	if _client:
		_client.close()
	_buffer = ""


func _process(_delta: float) -> void:
	if not _should_run:
		return

	_client.poll()

	match _client.get_status():
		HTTPClient.STATUS_CONNECTING:
			pass

		HTTPClient.STATUS_CONNECTED:
			if _request_sent:
				return
			_request_sent = true

			var post_body := JSON.stringify({
				"model": "deepseek-v4-pro",
				"messages": _pending_messages,
				"stream": true
			})

			var headers := PackedStringArray([
				"Content-Type: application/json",
				"Authorization: Bearer " + api_key,
				"Accept: text/event-stream",
			])
			var err = _client.request(HTTPClient.METHOD_POST, "/chat/completions", headers, post_body)
			if err != OK:
				connection_error.emit("请求失败: " + _err_str(err))
				stop()

		HTTPClient.STATUS_BODY:
			if not _client.has_response():
				return
			_read_chunks()

		HTTPClient.STATUS_DISCONNECTED:
			if _should_run:
				_should_run = false
				stream_finished.emit()

		HTTPClient.STATUS_CONNECTION_ERROR:
			connection_error.emit("连接出错")
			stop()

		_:
			pass


func _read_chunks() -> void:
	while _client.get_status() == HTTPClient.STATUS_BODY:
		var chunk = _client.read_response_body_chunk()
		if chunk.size() == 0:
			break
		_buffer += chunk.get_string_from_utf8()

		while "\n\n" in _buffer:
			var idx := _buffer.find("\n\n")
			var raw := _buffer.substr(0, idx)
			_buffer = _buffer.substr(idx + 2)
			_parse_event(raw.strip_edges())


func _parse_event(line: String) -> void:
	if not line.begins_with("data: "):
		return

	var data_str := line.substr(6).strip_edges()

	if data_str == "[DONE]":
		stream_finished.emit()
		stop()
		return

	var parsed = JSON.parse_string(data_str) as Dictionary
	if parsed == null:
		return

	if parsed.has("usage"):
		usage_received.emit(parsed["usage"] as Dictionary)
		return

	var choices = parsed.get("choices", [])
	if choices.is_empty():
		return

	var delta = choices[0].get("delta", {})
	if delta.has("reasoning_content") and delta["reasoning_content"] != null:
		reasoning_chunk.emit(delta["reasoning_content"])
	if delta.has("content") and delta["content"] != null:
		content_chunk.emit(delta["content"])
	if delta.has("tool_calls") and delta["tool_calls"] != null:
		tool_call_chunk.emit(delta["tool_calls"])


func _err_str(err: int) -> String:
	match err:
		ERR_CANT_CONNECT:
			return "无法连接"
		ERR_CANT_RESOLVE:
			return "DNS 解析失败"
		ERR_TIMEOUT:
			return "连接超时"
		_:
			return "错误码: " + str(err)


func _exit_tree() -> void:
	stop()
