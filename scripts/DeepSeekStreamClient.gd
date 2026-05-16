class_name DeepSeekStreamClient
extends Node

signal reasoning_chunk(text: String)
signal content_chunk(text: String)
signal tool_call_chunk(data: Dictionary)
signal tool_calls_done(tool_calls: Array)
signal stream_finished()
signal usage_received(usage: Dictionary)
signal connection_error(msg: String)

var api_key: String = ""
var api_host: String = "api.deepseek.com"
var api_port: int = 443
var api_path: String = "/chat/completions"

var is_stream_connected: bool:
	get:
		return _client != null and _client.get_status() == HTTPClient.STATUS_BODY

var _client: HTTPClient
var _buffer: String = ""
var _should_run: bool = false
var _request_sent: bool = false
var _body_str: String = ""
var _tool_call_buf: Array[Dictionary] = []
var _had_tool_calls: bool = false


func _ready() -> void:
	_client = HTTPClient.new()


func start_streaming(body_str: String) -> void:
	if _should_run:
		return
	_should_run = true
	_body_str = body_str
	_request_sent = false
	_buffer = ""
	_tool_call_buf.clear()
	_had_tool_calls = false

	var err = _client.connect_to_host(api_host, api_port, TLSOptions.client())
	if err != OK:
		connection_error.emit("连接失败: " + api_host + " " + _err_str(err))
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

			var post_body := _body_str

			var headers := PackedStringArray([
				"Content-Type: application/json",
				"Authorization: Bearer " + api_key,
				"Accept: text/event-stream",
			])
			var err = _client.request(HTTPClient.METHOD_POST, api_path, headers, post_body)
			if err != OK:
				connection_error.emit("请求失败: " + _err_str(err))
				stop()

		HTTPClient.STATUS_BODY:
			if not _client.has_response():
				return
			if _client.get_response_code() != 200:
				var err_body := _client.read_response_body_chunk().get_string_from_utf8()
				connection_error.emit("API " + str(_client.get_response_code()) + ": " + err_body.left(200))
				stop()
				return
			_read_chunks()

		HTTPClient.STATUS_DISCONNECTED:
			if _should_run:
				_should_run = false
				if not _tool_call_buf.is_empty():
					tool_calls_done.emit(_tool_call_buf)
				else:
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
	if api_host != "api.deepseek.com":
		print("[SSE RAW] ", data_str)

	if data_str == "[DONE]":
		if not _tool_call_buf.is_empty():
			tool_calls_done.emit(_tool_call_buf)
		else:
			stream_finished.emit()
		stop()
		return

	var parsed = JSON.parse_string(data_str)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return

	if parsed.has("usage"):
		var u = parsed["usage"]
		if typeof(u) == TYPE_DICTIONARY:
			usage_received.emit(u)
		return

	var choices = parsed.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return

	var delta = choices[0].get("delta", {})

	if delta.has("reasoning_content") and delta["reasoning_content"] != null:
		reasoning_chunk.emit(delta["reasoning_content"])
	if delta.has("content") and delta["content"] != null:
		content_chunk.emit(delta["content"])

	# 部分 API（如 OpenCode Go）可能一次性下发完整 message 而非流式 delta
	if not delta.has("content") or delta["content"] == null:
		var msg = choices[0].get("message", {})
		if msg.has("content") and msg["content"] != null and not str(msg["content"]).is_empty():
			content_chunk.emit(str(msg["content"]))
		if msg.has("reasoning_content") and msg["reasoning_content"] != null and not str(msg["reasoning_content"]).is_empty():
			reasoning_chunk.emit(str(msg["reasoning_content"]))
	if delta.has("tool_calls") and delta["tool_calls"] != null:
		_had_tool_calls = true
		var tc_array: Array = delta["tool_calls"]
		for tc in tc_array:
			var idx: int = tc.get("index", 0)
			while _tool_call_buf.size() <= idx:
				_tool_call_buf.append({"id": "", "name": "", "arguments": ""})
			if tc.has("id"):
				_tool_call_buf[idx]["id"] = tc["id"]
			var func_data = tc.get("function")
			if func_data != null:
				if func_data.has("name"):
					_tool_call_buf[idx]["name"] = func_data["name"]
				if func_data.has("arguments"):
					_tool_call_buf[idx]["arguments"] += func_data["arguments"]
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
