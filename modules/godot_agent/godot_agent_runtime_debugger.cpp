/**************************************************************************/
/*  godot_agent_runtime_debugger.cpp                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "godot_agent_runtime_debugger.h"

#include "core/io/json.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/os.h"

void GodotAgentRuntimeDebugger::_bind_methods() {
	ClassDB::bind_method(D_METHOD("status"), &GodotAgentRuntimeDebugger::status);
	ClassDB::bind_method(D_METHOD("send_command", "method", "params", "session_id"), &GodotAgentRuntimeDebugger::send_command, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("get_result", "id", "consume"), &GodotAgentRuntimeDebugger::get_result, DEFVAL(false));
}

Dictionary GodotAgentRuntimeDebugger::_ok(const Variant &p_data) const {
	Dictionary result;
	result["ok"] = true;
	if (p_data.get_type() != Variant::NIL) {
		result["data"] = p_data;
	}
	return result;
}

Dictionary GodotAgentRuntimeDebugger::_fail(const String &p_code, const String &p_message, const Variant &p_details) const {
	Dictionary error;
	error["code"] = p_code;
	error["message"] = p_message;
	if (p_details.get_type() != Variant::NIL) {
		error["details"] = p_details;
	}

	Dictionary result;
	result["ok"] = false;
	result["error"] = error;
	return result;
}

Ref<EditorDebuggerSession> GodotAgentRuntimeDebugger::_session_at(int p_session_id) {
	const Array sessions = get_sessions();
	if (p_session_id < 0 || p_session_id >= sessions.size()) {
		return Ref<EditorDebuggerSession>();
	}
	return sessions[p_session_id];
}

int GodotAgentRuntimeDebugger::_select_active_session(int p_session_id) {
	if (p_session_id >= 0) {
		Ref<EditorDebuggerSession> session = _session_at(p_session_id);
		return session.is_valid() && session->is_active() ? p_session_id : -1;
	}

	const Array sessions = get_sessions();
	int first_active = -1;
	for (int i = 0; i < sessions.size(); i++) {
		Ref<EditorDebuggerSession> session = sessions[i];
		if (session.is_null() || !session->is_active()) {
			continue;
		}
		if (first_active < 0) {
			first_active = i;
		}
		const SessionMetadata *metadata = session_metadata.getptr(i);
		if (metadata && !metadata->hello.is_empty()) {
			return i;
		}
	}
	return first_active;
}

void GodotAgentRuntimeDebugger::_expire_pending_results() {
	const int64_t now = OS::get_singleton()->get_ticks_msec();
	for (int64_t id : result_order) {
		Dictionary *result = results.getptr(id);
		if (!result || (String)result->get("status", "") != "pending") {
			continue;
		}
		const int64_t expires_at = result->get("expires_at_msec", 0);
		if (now < expires_at) {
			continue;
		}

		Dictionary error;
		error["code"] = "runtime_timeout";
		error["message"] = "The runtime did not respond before the command timeout; execution may still complete";
		Dictionary details;
		details["execution_state"] = "unknown";
		details["retry_safe"] = false;
		error["details"] = details;
		(*result)["status"] = "timed_out";
		(*result)["ok"] = false;
		(*result)["error"] = error;
		(*result)["completed_at_msec"] = now;
	}
}

void GodotAgentRuntimeDebugger::_trim_results() {
	while (result_order.size() > MAX_RETAINED_RESULTS) {
		int removable_index = -1;
		for (int i = 0; i < result_order.size(); i++) {
			const Dictionary *result = results.getptr(result_order[i]);
			if (result && (String)result->get("status", "") != "pending") {
				removable_index = i;
				break;
			}
		}
		if (removable_index < 0) {
			break;
		}
		const int64_t id = result_order[removable_index];
		_erase_result(id);
		evicted_result_count++;
	}
}

bool GodotAgentRuntimeDebugger::_make_payload_room(int64_t p_bytes, int64_t p_protected_id) {
	while (retained_payload_bytes + p_bytes > MAX_RETAINED_PAYLOAD_BYTES) {
		int64_t removable_id = -1;
		for (int64_t id : result_order) {
			const Dictionary *result = results.getptr(id);
			if (id != p_protected_id && result && (String)result->get("status", "") != "pending") {
				removable_id = id;
				break;
			}
		}
		if (removable_id < 0) {
			return false;
		}
		_erase_result(removable_id);
		evicted_result_count++;
	}
	return true;
}

void GodotAgentRuntimeDebugger::_erase_result(int64_t p_id) {
	const Dictionary *result = results.getptr(p_id);
	if (result) {
		retained_payload_bytes -= (int64_t)result->get("payload_bytes", 0);
		retained_payload_bytes = MAX(retained_payload_bytes, (int64_t)0);
	}
	results.erase(p_id);
	const int index = result_order.find(p_id);
	if (index >= 0) {
		result_order.remove_at(index);
	}
}

void GodotAgentRuntimeDebugger::_fail_pending_for_session(int p_session_id, const String &p_code, const String &p_message) {
	const int64_t now = OS::get_singleton()->get_ticks_msec();
	for (int64_t id : result_order) {
		Dictionary *result = results.getptr(id);
		if (!result || (String)result->get("status", "") != "pending" || (int)result->get("session_id", -1) != p_session_id) {
			continue;
		}

		Dictionary error;
		error["code"] = p_code;
		error["message"] = p_message;
		(*result)["status"] = "failed";
		(*result)["ok"] = false;
		(*result)["error"] = error;
		(*result)["completed_at_msec"] = now;
	}
}

void GodotAgentRuntimeDebugger::_session_started(int p_session_id) {
	SessionMetadata &metadata = session_metadata[p_session_id];
	metadata.hello.clear();
	metadata.hello_received_at_msec = 0;
	metadata.started_at_msec = OS::get_singleton()->get_ticks_msec();
	metadata.stopped_at_msec = 0;
}

void GodotAgentRuntimeDebugger::_session_stopped(int p_session_id) {
	_expire_pending_results();
	SessionMetadata &metadata = session_metadata[p_session_id];
	metadata.stopped_at_msec = OS::get_singleton()->get_ticks_msec();
	_fail_pending_for_session(p_session_id, "runtime_stopped", "The runtime stopped before responding to the command");
}

bool GodotAgentRuntimeDebugger::_capture_hello(const Array &p_data, int p_session_id) {
	if (p_data.size() != 1 || p_data[0].get_type() != Variant::DICTIONARY) {
		return true;
	}

	SessionMetadata &metadata = session_metadata[p_session_id];
	metadata.hello = p_data[0];
	metadata.hello_received_at_msec = OS::get_singleton()->get_ticks_msec();
	return true;
}

bool GodotAgentRuntimeDebugger::_capture_response(const Array &p_data, int p_session_id) {
	_expire_pending_results();
	if (p_data.size() != 1 || p_data[0].get_type() != Variant::DICTIONARY) {
		return true;
	}

	const Dictionary response = p_data[0];
	const Variant id_value = response.get("id", Variant());
	if (id_value.get_type() != Variant::INT) {
		return true;
	}

	const int64_t id = id_value;
	Dictionary *result = results.getptr(id);
	if (!result || (String)result->get("status", "") != "pending" || (int)result->get("session_id", -1) != p_session_id) {
		return true;
	}

	const int64_t now = OS::get_singleton()->get_ticks_msec();
	const String serialized_response = Variant(JSON::from_native(response)).to_json_string();
	const int64_t response_bytes = serialized_response.to_utf8_buffer().size();
	if (response_bytes > MAX_RUNTIME_RESPONSE_BYTES) {
		Dictionary error;
		error["code"] = "runtime_response_too_large";
		error["message"] = "Runtime response exceeds the retained-result size limit";
		Dictionary details;
		details["response_bytes"] = response_bytes;
		details["max_response_bytes"] = MAX_RUNTIME_RESPONSE_BYTES;
		error["details"] = details;
		(*result)["status"] = "failed";
		(*result)["ok"] = false;
		(*result)["error"] = error;
		(*result)["completed_at_msec"] = now;
		return true;
	}
	if (!_make_payload_room(response_bytes, id)) {
		Dictionary error;
		error["code"] = "runtime_result_storage_full";
		error["message"] = "Completed runtime results exhausted the retained payload budget";
		(*result)["status"] = "failed";
		(*result)["ok"] = false;
		(*result)["error"] = error;
		(*result)["completed_at_msec"] = now;
		return true;
	}
	const Variant ok_value = response.get("ok", Variant());
	if (ok_value.get_type() != Variant::BOOL) {
		Dictionary error;
		error["code"] = "invalid_runtime_response";
		error["message"] = "Runtime response is missing a boolean 'ok' field";
		(*result)["status"] = "failed";
		(*result)["ok"] = false;
		(*result)["error"] = error;
		(*result)["completed_at_msec"] = now;
		return true;
	}

	const bool ok = ok_value;
	(*result)["status"] = "completed";
	(*result)["ok"] = ok;
	(*result)["completed_at_msec"] = now;
	(*result)["payload_bytes"] = response_bytes;
	retained_payload_bytes += response_bytes;
	if (ok) {
		(*result)["data"] = response.get("data", Variant());
	} else {
		(*result)["error"] = response.get("error", "Runtime command failed");
	}
	return true;
}

bool GodotAgentRuntimeDebugger::has_capture(const String &p_capture) const {
	return p_capture == "godot_ai";
}

bool GodotAgentRuntimeDebugger::capture(const String &p_message, const Array &p_data, int p_session_id) {
	if (_session_at(p_session_id).is_null()) {
		return false;
	}
	if (p_message == "godot_ai:hello") {
		return _capture_hello(p_data, p_session_id);
	}
	if (p_message == "godot_ai:response") {
		return _capture_response(p_data, p_session_id);
	}
	return false;
}

void GodotAgentRuntimeDebugger::setup_session(int p_session_id) {
	Ref<EditorDebuggerSession> session = _session_at(p_session_id);
	ERR_FAIL_COND(session.is_null());

	session_metadata.insert(p_session_id, SessionMetadata());
	session->connect("started", callable_mp(this, &GodotAgentRuntimeDebugger::_session_started).bind(p_session_id));
	session->connect("stopped", callable_mp(this, &GodotAgentRuntimeDebugger::_session_stopped).bind(p_session_id));
}

Dictionary GodotAgentRuntimeDebugger::status() {
	_expire_pending_results();

	Dictionary data;
	data["protocol_version"] = PROTOCOL_VERSION;
	data["pending_timeout_ms"] = PENDING_TIMEOUT_MSEC;
	data["max_retained_results"] = MAX_RETAINED_RESULTS;
	data["max_retained_payload_bytes"] = MAX_RETAINED_PAYLOAD_BYTES;
	data["retained_result_count"] = results.size();
	data["retained_payload_bytes"] = retained_payload_bytes;
	data["evicted_result_count"] = evicted_result_count;
	data["next_command_id"] = next_command_id;

	int pending_count = 0;
	for (int64_t id : result_order) {
		const Dictionary *result = results.getptr(id);
		if (result && (String)result->get("status", "") == "pending") {
			pending_count++;
		}
	}
	data["pending_result_count"] = pending_count;

	Array session_statuses;
	int active_count = 0;
	int ready_count = 0;
	const Array sessions = get_sessions();
	for (int i = 0; i < sessions.size(); i++) {
		Ref<EditorDebuggerSession> session = sessions[i];
		const bool active = session.is_valid() && session->is_active();
		const SessionMetadata *metadata = session_metadata.getptr(i);
		const bool has_hello = metadata && !metadata->hello.is_empty();

		Dictionary session_status;
		session_status["session_id"] = i;
		session_status["active"] = active;
		session_status["ready"] = active && has_hello;
		if (metadata) {
			session_status["started_at_msec"] = metadata->started_at_msec;
			session_status["stopped_at_msec"] = metadata->stopped_at_msec;
			session_status["hello_received_at_msec"] = metadata->hello_received_at_msec;
			if (has_hello) {
				session_status["hello"] = metadata->hello;
			}
		}
		session_statuses.push_back(session_status);
		active_count += active ? 1 : 0;
		ready_count += active && has_hello ? 1 : 0;
	}
	data["session_count"] = sessions.size();
	data["active_session_count"] = active_count;
	data["ready_session_count"] = ready_count;
	data["sessions"] = session_statuses;
	return _ok(data);
}

Dictionary GodotAgentRuntimeDebugger::send_command(const String &p_method, const Dictionary &p_params, int p_session_id) {
	_expire_pending_results();
	_trim_results();
	if (p_method.strip_edges().is_empty()) {
		return _fail("invalid_runtime_method", "Runtime command method must not be empty");
	}
	if (p_session_id < -1) {
		return _fail("invalid_runtime_session", "Runtime session ID must be -1 or a non-negative integer", p_session_id);
	}

	const int selected_session_id = _select_active_session(p_session_id);
	if (selected_session_id < 0) {
		if (p_session_id >= 0 && _session_at(p_session_id).is_null()) {
			return _fail("invalid_runtime_session", "The requested runtime session does not exist", p_session_id);
		}
		if (p_session_id >= 0) {
			return _fail("inactive_runtime_session", "The requested runtime session is not active", p_session_id);
		}
		return _fail("runtime_not_running", "No active runtime debugger session is available");
	}

	Ref<EditorDebuggerSession> session = _session_at(selected_session_id);
	if (session.is_null() || !session->is_active()) {
		return _fail("runtime_not_running", "The runtime debugger session became inactive before the command was sent", selected_session_id);
	}
	const SessionMetadata *metadata = session_metadata.getptr(selected_session_id);
	if (!metadata || metadata->hello.is_empty()) {
		return _fail("runtime_not_ready", "The active debugger session has not announced a Godot AI runtime probe", selected_session_id);
	}
	if (next_command_id == INT64_MAX) {
		return _fail("runtime_command_id_exhausted", "Runtime command IDs have been exhausted");
	}
	if (results.size() >= MAX_RETAINED_RESULTS) {
		return _fail("runtime_command_queue_full", "All retained runtime result slots are pending; wait for or consume a result");
	}
	Dictionary command_size_probe;
	command_size_probe["protocol_version"] = PROTOCOL_VERSION;
	command_size_probe["method"] = p_method;
	command_size_probe["params"] = p_params;
	const int64_t command_bytes = Variant(JSON::from_native(command_size_probe)).to_json_string().to_utf8_buffer().size();
	if (command_bytes > MAX_RUNTIME_COMMAND_BYTES) {
		Dictionary details;
		details["command_bytes"] = command_bytes;
		details["max_command_bytes"] = MAX_RUNTIME_COMMAND_BYTES;
		return _fail("runtime_command_too_large", "Runtime command exceeds the debugger transport size limit", details);
	}

	const int64_t id = next_command_id++;
	const int64_t created_at = OS::get_singleton()->get_ticks_msec();
	Dictionary retained_result;
	retained_result["id"] = id;
	retained_result["session_id"] = selected_session_id;
	retained_result["method"] = p_method;
	retained_result["status"] = "pending";
	retained_result["created_at_msec"] = created_at;
	retained_result["timeout_ms"] = PENDING_TIMEOUT_MSEC;
	retained_result["expires_at_msec"] = created_at + PENDING_TIMEOUT_MSEC;
	results.insert(id, retained_result);
	result_order.push_back(id);

	Dictionary command;
	command["id"] = id;
	command["protocol_version"] = PROTOCOL_VERSION;
	command["method"] = p_method;
	command["params"] = p_params;
	Array payload;
	payload.push_back(command);
	session->send_message("godot_ai:command", payload);

	Dictionary data;
	data["id"] = id;
	data["session_id"] = selected_session_id;
	data["status"] = "pending";
	data["timeout_ms"] = PENDING_TIMEOUT_MSEC;
	return _ok(data);
}

Dictionary GodotAgentRuntimeDebugger::get_result(int64_t p_id, bool p_consume) {
	_expire_pending_results();
	const Dictionary *stored_result = results.getptr(p_id);
	if (!stored_result) {
		return _fail("runtime_result_not_found", "No retained runtime command result has this ID", p_id);
	}

	const Dictionary result = *stored_result;
	if (p_consume) {
		_erase_result(p_id);
	}
	return _ok(result);
}
