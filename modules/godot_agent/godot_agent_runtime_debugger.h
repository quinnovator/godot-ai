/**************************************************************************/
/*  godot_agent_runtime_debugger.h                                        */
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

#pragma once

#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "editor/debugger/editor_debugger_plugin.h"

class GodotAgentRuntimeDebugger : public EditorDebuggerPlugin {
	GDCLASS(GodotAgentRuntimeDebugger, EditorDebuggerPlugin);

	struct SessionMetadata {
		Dictionary hello;
		int64_t hello_received_at_msec = 0;
		int64_t started_at_msec = 0;
		int64_t stopped_at_msec = 0;
	};

	static constexpr int PROTOCOL_VERSION = 1;
	static constexpr int MAX_RETAINED_RESULTS = 256;
	static constexpr int64_t MAX_RUNTIME_COMMAND_BYTES = 1024 * 1024;
	static constexpr int64_t MAX_RUNTIME_RESPONSE_BYTES = 2 * 1024 * 1024;
	static constexpr int64_t MAX_RETAINED_PAYLOAD_BYTES = 16 * 1024 * 1024;
	static constexpr int64_t PENDING_TIMEOUT_MSEC = 30 * 1000;

	HashMap<int, SessionMetadata> session_metadata;
	HashMap<int64_t, Dictionary> results;
	Vector<int64_t> result_order;
	int64_t next_command_id = 1;
	int64_t evicted_result_count = 0;
	int64_t retained_payload_bytes = 0;

	Dictionary _ok(const Variant &p_data = Variant()) const;
	Dictionary _fail(const String &p_code, const String &p_message, const Variant &p_details = Variant()) const;
	Ref<EditorDebuggerSession> _session_at(int p_session_id);
	int _select_active_session(int p_session_id);
	void _expire_pending_results();
	void _trim_results();
	bool _make_payload_room(int64_t p_bytes, int64_t p_protected_id);
	void _erase_result(int64_t p_id);
	void _fail_pending_for_session(int p_session_id, const String &p_code, const String &p_message);
	void _session_started(int p_session_id);
	void _session_stopped(int p_session_id);
	bool _capture_hello(const Array &p_data, int p_session_id);
	bool _capture_response(const Array &p_data, int p_session_id);

protected:
	static void _bind_methods();

public:
	virtual bool has_capture(const String &p_capture) const override;
	virtual bool capture(const String &p_message, const Array &p_data, int p_session_id) override;
	virtual void setup_session(int p_session_id) override;

	Dictionary status();
	Dictionary send_command(const String &p_method, const Dictionary &p_params, int p_session_id = -1);
	Dictionary get_result(int64_t p_id, bool p_consume = false);
};
