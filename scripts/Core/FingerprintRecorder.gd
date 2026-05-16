class_name FingerprintRecorder
extends RefCounted


static func save_meta(batch_dir: String, index: int, usage: Dictionary) -> void:
	var meta: Dictionary = {
		"index": index,
		"system_fingerprint": usage.get("system_fingerprint", ""),
		"prompt_tokens": usage.get("prompt_tokens", 0),
		"completion_tokens": usage.get("completion_tokens", 0),
		"total_tokens": usage.get("total_tokens", 0),
		"reasoning_tokens": usage.get("completion_tokens_details", {}).get("reasoning_tokens", 0),
		"timestamp": Time.get_datetime_string_from_system(),
	}

	var fname := "batch_%03d_meta.json" % index
	var fpath := batch_dir.path_join(fname)
	var file := FileAccess.open(fpath, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(meta, "\t"))
		file.close()
