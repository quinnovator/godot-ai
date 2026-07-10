/**************************************************************************/
/*  godot_agent_editor_plugin.h                                           */
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

#include "godot_agent_runtime_debugger.h"

#include "core/io/stream_peer_tcp.h"
#include "core/io/tcp_server.h"
#include "editor/plugins/editor_plugin.h"

#include "modules/jsonrpc/jsonrpc.h"

class Node;

class GodotAgentEditorPlugin : public EditorPlugin {
	GDCLASS(GodotAgentEditorPlugin, EditorPlugin);

	struct Peer {
		Ref<StreamPeerTCP> connection;
		PackedByteArray input;
		PackedByteArray output;
		uint64_t last_activity_msec = 0;
		bool close_after_output = false;
	};

	static constexpr int PROTOCOL_VERSION = 1;
	static constexpr int MAX_MESSAGE_BYTES = 8 * 1024 * 1024;
	static constexpr int MAX_PEER_OUTPUT_BYTES = MAX_MESSAGE_BYTES + 4096;
	static constexpr int MAX_PEERS = 8;
	static constexpr int MAX_TREE_NODES = 4096;
	static constexpr int MAX_ENCODED_CONTAINER_ITEMS = 4096;
	static constexpr int MAX_ENCODED_STRING_LENGTH = 256 * 1024;
	static constexpr uint64_t PEER_IDLE_TIMEOUT_MSEC = 5 * 1000;

	Ref<TCPServer> server;
	Vector<Peer> peers;
	JSONRPC rpc;
	Ref<GodotAgentRuntimeDebugger> runtime_debugger;
	String auth_token;
	String endpoint_path;
	uint8_t preview_viewport_mask = 0;
	bool start_attempted = false;
	bool started = false;

	void _register_methods();
	void _start();
	void _stop();
	void _clear_agent_previews();
	void _poll();
	void _accept_connections();
	Error _poll_peer(Peer &r_peer);
	Error _flush_peer_output(Peer &r_peer);
	Error _consume_messages(Peer &r_peer);
	Error _queue_message(Peer &r_peer, const String &p_message);
	String _process_message(const String &p_message);
	String _generate_token() const;
	Error _write_endpoint();
	void _remove_endpoint_if_owned();

	Dictionary _ok(const Variant &p_data = Variant()) const;
	Dictionary _fail(const String &p_code, const String &p_message, const Variant &p_details = Variant()) const;
	Variant _encode_variant(const Variant &p_value, int p_depth = 0) const;
	Variant _decode_variant(const Variant &p_value, int p_depth = 0, bool *r_valid = nullptr) const;
	Dictionary _set_node_property(Node *p_node, const StringName &p_property, const Variant &p_wire_value) const;
	Dictionary _apply_node_properties(Node *p_node, const Dictionary &p_properties) const;
	Node *_edited_root() const;
	Node *_find_node(const Dictionary &p_params, const StringName &p_key = "node_path") const;
	Dictionary _describe_node(Node *p_node, Node *p_root, bool p_include_warnings) const;
	Dictionary _describe_tree(Node *p_node, Node *p_root, int p_depth, int p_max_depth, bool p_include_internal, bool p_include_warnings, int &r_node_count) const;

	Dictionary _rpc_health(Dictionary p_params);
	Dictionary _rpc_scene_create(Dictionary p_params);
	Dictionary _rpc_scene_open(Dictionary p_params);
	Dictionary _rpc_scene_get_tree(Dictionary p_params);
	Dictionary _rpc_scene_create_node(Dictionary p_params);
	Dictionary _rpc_scene_instantiate(Dictionary p_params);
	Dictionary _rpc_scene_set_property(Dictionary p_params);
	Dictionary _rpc_scene_delete_node(Dictionary p_params);
	Dictionary _rpc_scene_reparent_node(Dictionary p_params);
	Dictionary _rpc_scene_save(Dictionary p_params);
	Dictionary _rpc_scene_validate(Dictionary p_params);
	Dictionary _rpc_node_inspect(Dictionary p_params);
	Dictionary _rpc_project_get_setting(Dictionary p_params);
	Dictionary _rpc_project_set_setting(Dictionary p_params);
	Dictionary _rpc_assets_scan(Dictionary p_params);
	Dictionary _rpc_editor_focus_node(Dictionary p_params);
	Dictionary _rpc_editor_preview_camera(Dictionary p_params);
	Dictionary _rpc_editor_capture(Dictionary p_params);
	Dictionary _rpc_rig_inspect(Dictionary p_params);
	Dictionary _rpc_game_play(Dictionary p_params);
	Dictionary _rpc_game_stop(Dictionary p_params);
	Dictionary _rpc_game_status(Dictionary p_params);
	Dictionary _rpc_runtime_status(Dictionary p_params);
	Dictionary _rpc_runtime_command(Dictionary p_params);
	Dictionary _rpc_runtime_result(Dictionary p_params);

protected:
	void _notification(int p_what);

public:
	GodotAgentEditorPlugin();
	~GodotAgentEditorPlugin();
};
