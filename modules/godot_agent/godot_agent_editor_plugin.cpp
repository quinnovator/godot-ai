/**************************************************************************/
/*  godot_agent_editor_plugin.cpp                                         */
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

#include "godot_agent_editor_plugin.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/crypto/crypto_core.h"
#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/io/json.h"
#include "core/io/resource.h"
#include "core/io/resource_importer.h"
#include "core/io/resource_loader.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/templates/hash_set.h"
#include "editor/editor_interface.h"
#include "editor/editor_log.h"
#include "editor/editor_node.h"
#include "editor/file_system/editor_file_system.h"
#include "editor/scene/3d/node_3d_editor_plugin.h"
#include "scene/2d/node_2d.h"
#include "scene/3d/camera_3d.h"
#include "scene/3d/node_3d.h"
#include "scene/3d/skeleton_3d.h"
#include "scene/3d/visual_instance_3d.h"
#include "scene/main/viewport.h"
#include "scene/resources/packed_scene.h"

static bool _is_safe_resource_path(const String &p_path, const String &p_extension) {
	if (!p_path.begins_with("res://") || p_path.contains("\\")) {
		return false;
	}
	const String relative = p_path.trim_prefix("res://");
	if (relative.is_empty() || relative.begins_with("/")) {
		return false;
	}
	String absolute = ProjectSettings::get_singleton()->globalize_path("res://").trim_suffix("/");
	Ref<DirAccess> filesystem = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);
	for (const String &segment : relative.split("/")) {
		if (segment.is_empty() || segment == "." || segment == "..") {
			return false;
		}
		absolute = absolute.path_join(segment);
		if (filesystem.is_valid() && filesystem->is_link(absolute)) {
			return false;
		}
	}
	return p_extension.is_empty() || p_path.get_extension().to_lower() == p_extension.to_lower();
}

static bool _scene_inheritance_reaches(const String &p_target_path, Node *p_node) {
	Node *candidate = p_node;
	Vector<Node *> expanded_instances;
	HashSet<String> visited_paths;
	bool found = false;
	while (candidate) {
		if (candidate->get_scene_file_path() == p_target_path) {
			found = true;
			break;
		}
		Ref<SceneState> inherited_state = candidate->get_scene_inherited_state();
		if (inherited_state.is_null()) {
			break;
		}
		const String inherited_path = inherited_state->get_path();
		if (inherited_path == p_target_path) {
			found = true;
			break;
		}
		if (inherited_path.is_empty() || visited_paths.has(inherited_path)) {
			break;
		}
		visited_paths.insert(inherited_path);
		Ref<PackedScene> inherited_scene = ResourceLoader::load(inherited_path);
		if (inherited_scene.is_null()) {
			break;
		}
		candidate = inherited_scene->instantiate(PackedScene::GEN_EDIT_STATE_INSTANCE);
		if (!candidate) {
			break;
		}
		expanded_instances.push_back(candidate);
	}
	for (Node *instance : expanded_instances) {
		memdelete(instance);
	}
	return found;
}

static bool _scene_dependency_reaches(const String &p_target_path, Node *p_node) {
	if (_scene_inheritance_reaches(p_target_path, p_node)) {
		return true;
	}
	for (int i = 0; i < p_node->get_child_count(); i++) {
		if (_scene_dependency_reaches(p_target_path, p_node->get_child(i))) {
			return true;
		}
	}
	return false;
}

static bool _is_editable_scene_node(Node *p_root, Node *p_node) {
	if (!p_root || !p_node) {
		return false;
	}
	if (p_node == p_root || p_node->get_owner() == p_root) {
		return true;
	}
	Node *owner = p_node->get_owner();
	return owner && p_root->is_editable_instance(owner);
}

static bool _is_string_value(const Variant &p_value) {
	return p_value.get_type() == Variant::STRING || p_value.get_type() == Variant::STRING_NAME;
}

static bool _is_integer_in_range(const Variant &p_value, int64_t p_minimum, int64_t p_maximum) {
	if (p_value.get_type() != Variant::INT && p_value.get_type() != Variant::FLOAT) {
		return false;
	}
	const double numeric_value = p_value;
	return numeric_value >= (double)p_minimum && numeric_value <= (double)p_maximum && numeric_value == (double)(int64_t)numeric_value;
}

static bool _is_viewport_index(const Variant &p_value) {
	return _is_integer_in_range(p_value, 0, 3);
}

static bool _is_safe_node_path(const String &p_path) {
	if (p_path == ".") {
		return true;
	}
	if (p_path.is_empty() || p_path.begins_with("/") || p_path.contains(":")) {
		return false;
	}
	for (const String &segment : p_path.split("/")) {
		if (segment.is_empty() || segment == "." || segment == ".." || segment.begins_with("%")) {
			return false;
		}
	}
	return true;
}

static bool _find_property_info(Object *p_object, const StringName &p_property, PropertyInfo &r_info) {
	List<PropertyInfo> properties;
	p_object->get_property_list(&properties);
	for (const PropertyInfo &property : properties) {
		if (property.name == p_property) {
			r_info = property;
			return true;
		}
	}
	return false;
}

static bool _object_matches_property(Object *p_object, const PropertyInfo &p_info) {
	if (!p_object) {
		return true;
	}
	String type_specification;
	if (p_info.hint == PROPERTY_HINT_RESOURCE_TYPE) {
		type_specification = p_info.hint_string;
	} else if (p_info.class_name != StringName()) {
		type_specification = p_info.class_name;
	}
	if (type_specification.is_empty()) {
		return true;
	}

	bool has_included_type = false;
	bool matches_included_type = false;
	for (String type : type_specification.split(",", false)) {
		type = type.strip_edges();
		const bool excluded = type.begins_with("-");
		if (excluded) {
			type = type.trim_prefix("-");
		}
		const bool matches = p_object->is_class(type) || EditorNode::get_singleton()->is_object_of_custom_type(p_object, type);
		if (excluded && matches) {
			return false;
		}
		if (!excluded) {
			has_included_type = true;
			matches_included_type |= matches;
		}
	}
	return !has_included_type || matches_included_type;
}

static String _parameter_schema(const String &p_method) {
	if (p_method == "agent.health" || p_method == "scene.validate" || p_method == "game.stop" || p_method == "game.status" || p_method == "runtime.status") {
		return String();
	}
	if (p_method == "scene.create") {
		return "path,type,name";
	}
	if (p_method == "scene.open" || p_method == "scene.save") {
		return "path";
	}
	if (p_method == "scene.get_tree") {
		return "max_depth,include_internal,include_warnings";
	}
	if (p_method == "scene.create_node") {
		return "parent_path,type,name,properties";
	}
	if (p_method == "scene.instantiate") {
		return "path,parent_path,name,properties";
	}
	if (p_method == "scene.set_property") {
		return "node_path,property,value";
	}
	if (p_method == "scene.delete_node") {
		return "node_path";
	}
	if (p_method == "scene.reparent_node") {
		return "node_path,new_parent_path,keep_global_transform";
	}
	if (p_method == "node.inspect") {
		return "node_path,properties";
	}
	if (p_method == "project.get_setting") {
		return "key";
	}
	if (p_method == "project.set_setting") {
		return "key,value,save";
	}
	if (p_method == "assets.scan") {
		return "paths";
	}
	if (p_method == "editor.focus_node" || p_method == "editor.preview_camera") {
		return "node_path,viewport";
	}
	if (p_method == "editor.capture") {
		return "path,viewport";
	}
	if (p_method == "rig.inspect") {
		return "node_path";
	}
	if (p_method == "game.play") {
		return "scene";
	}
	if (p_method == "runtime.command") {
		return "method,command_params,session_id";
	}
	if (p_method == "runtime.result") {
		return "id,consume";
	}
	return "*";
}

static int64_t _packed_array_size(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::PACKED_BYTE_ARRAY:
			return ((PackedByteArray)p_value).size();
		case Variant::PACKED_INT32_ARRAY:
			return ((PackedInt32Array)p_value).size();
		case Variant::PACKED_INT64_ARRAY:
			return ((PackedInt64Array)p_value).size();
		case Variant::PACKED_FLOAT32_ARRAY:
			return ((PackedFloat32Array)p_value).size();
		case Variant::PACKED_FLOAT64_ARRAY:
			return ((PackedFloat64Array)p_value).size();
		case Variant::PACKED_STRING_ARRAY:
			return ((PackedStringArray)p_value).size();
		case Variant::PACKED_VECTOR2_ARRAY:
			return ((PackedVector2Array)p_value).size();
		case Variant::PACKED_VECTOR3_ARRAY:
			return ((PackedVector3Array)p_value).size();
		case Variant::PACKED_COLOR_ARRAY:
			return ((PackedColorArray)p_value).size();
		case Variant::PACKED_VECTOR4_ARRAY:
			return ((PackedVector4Array)p_value).size();
		default:
			return -1;
	}
}

GodotAgentEditorPlugin::GodotAgentEditorPlugin() {
	_register_methods();
	runtime_debugger.instantiate();
	set_process_internal(true);
}

GodotAgentEditorPlugin::~GodotAgentEditorPlugin() {
	_stop();
}

void GodotAgentEditorPlugin::_register_methods() {
	rpc.set_method("agent.health", callable_mp(this, &GodotAgentEditorPlugin::_rpc_health));
	rpc.set_method("scene.create", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_create));
	rpc.set_method("scene.open", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_open));
	rpc.set_method("scene.get_tree", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_get_tree));
	rpc.set_method("scene.create_node", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_create_node));
	rpc.set_method("scene.instantiate", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_instantiate));
	rpc.set_method("scene.set_property", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_set_property));
	rpc.set_method("scene.delete_node", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_delete_node));
	rpc.set_method("scene.reparent_node", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_reparent_node));
	rpc.set_method("scene.save", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_save));
	rpc.set_method("scene.validate", callable_mp(this, &GodotAgentEditorPlugin::_rpc_scene_validate));
	rpc.set_method("node.inspect", callable_mp(this, &GodotAgentEditorPlugin::_rpc_node_inspect));
	rpc.set_method("project.get_setting", callable_mp(this, &GodotAgentEditorPlugin::_rpc_project_get_setting));
	rpc.set_method("project.set_setting", callable_mp(this, &GodotAgentEditorPlugin::_rpc_project_set_setting));
	rpc.set_method("assets.scan", callable_mp(this, &GodotAgentEditorPlugin::_rpc_assets_scan));
	rpc.set_method("editor.focus_node", callable_mp(this, &GodotAgentEditorPlugin::_rpc_editor_focus_node));
	rpc.set_method("editor.preview_camera", callable_mp(this, &GodotAgentEditorPlugin::_rpc_editor_preview_camera));
	rpc.set_method("editor.capture", callable_mp(this, &GodotAgentEditorPlugin::_rpc_editor_capture));
	rpc.set_method("rig.inspect", callable_mp(this, &GodotAgentEditorPlugin::_rpc_rig_inspect));
	rpc.set_method("game.play", callable_mp(this, &GodotAgentEditorPlugin::_rpc_game_play));
	rpc.set_method("game.stop", callable_mp(this, &GodotAgentEditorPlugin::_rpc_game_stop));
	rpc.set_method("game.status", callable_mp(this, &GodotAgentEditorPlugin::_rpc_game_status));
	rpc.set_method("runtime.status", callable_mp(this, &GodotAgentEditorPlugin::_rpc_runtime_status));
	rpc.set_method("runtime.command", callable_mp(this, &GodotAgentEditorPlugin::_rpc_runtime_command));
	rpc.set_method("runtime.result", callable_mp(this, &GodotAgentEditorPlugin::_rpc_runtime_result));
}

void GodotAgentEditorPlugin::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			add_debugger_plugin(runtime_debugger);
		} break;
		case NOTIFICATION_INTERNAL_PROCESS: {
			if (!start_attempted && EditorNode::get_singleton()->is_editor_ready()) {
				start_attempted = true;
				_start();
			}
			if (started) {
				_poll();
			}
		} break;
		case NOTIFICATION_EXIT_TREE: {
			remove_debugger_plugin(runtime_debugger);
			_stop();
		} break;
	}
}

String GodotAgentEditorPlugin::_generate_token() const {
	uint8_t bytes[32];
	CryptoCore::RandomGenerator rng;
	if (rng.init() == OK && rng.get_random_bytes(bytes, sizeof(bytes)) == OK) {
		return String::hex_encode_buffer(bytes, sizeof(bytes));
	}
	return String();
}

void GodotAgentEditorPlugin::_start() {
	print_verbose("Godot Agent: starting local editor bridge");
	server.instantiate();
	const Error listen_error = server->listen(0, IPAddress("127.0.0.1"));
	if (listen_error != OK) {
		ERR_PRINT("Godot Agent bridge failed to bind: " + String(error_names[listen_error]));
		EditorNode::get_log()->add_message("Godot Agent bridge failed to bind: " + String(error_names[listen_error]), EditorLog::MSG_TYPE_ERROR);
		server.unref();
		return;
	}

	auth_token = _generate_token();
	if (auth_token.is_empty()) {
		ERR_PRINT("Godot Agent bridge could not obtain cryptographically secure authentication material");
		EditorNode::get_log()->add_message("Godot Agent bridge could not obtain cryptographically secure authentication material", EditorLog::MSG_TYPE_ERROR);
		server->stop();
		server.unref();
		return;
	}
	endpoint_path = ProjectSettings::get_singleton()->get_project_data_path().path_join("agent/endpoint.json");
	const Error endpoint_error = _write_endpoint();
	if (endpoint_error != OK) {
		ERR_PRINT("Godot Agent bridge could not write its endpoint file: " + String(error_names[endpoint_error]));
		EditorNode::get_log()->add_message("Godot Agent bridge could not write its endpoint file: " + String(error_names[endpoint_error]), EditorLog::MSG_TYPE_ERROR);
		server->stop();
		server.unref();
		return;
	}

	started = true;
	EditorNode::get_log()->add_message(vformat("Godot Agent bridge listening on 127.0.0.1:%d", server->get_local_port()), EditorLog::MSG_TYPE_EDITOR);
}

Error GodotAgentEditorPlugin::_write_endpoint() {
	const String absolute_path = ProjectSettings::get_singleton()->globalize_path(endpoint_path);
	const String temporary_nonce = _generate_token();
	ERR_FAIL_COND_V_MSG(temporary_nonce.is_empty(), ERR_CANT_CREATE, "Godot Agent could not obtain a secure endpoint filename");
	const String temporary_path = absolute_path + ".tmp-" + itos(OS::get_singleton()->get_process_id()) + "-" + temporary_nonce.left(16);
	const Error dir_error = DirAccess::make_dir_recursive_absolute(absolute_path.get_base_dir());
	ERR_FAIL_COND_V_MSG(dir_error != OK, dir_error, "Godot Agent could not create its endpoint directory");
#ifdef UNIX_ENABLED
	const Error dir_permissions_error = FileAccess::set_unix_permissions(absolute_path.get_base_dir(), 0700);
	ERR_FAIL_COND_V_MSG(dir_permissions_error != OK, dir_permissions_error, "Godot Agent could not restrict its endpoint directory permissions");
#endif

	// WRITE uses Godot's backup-save path, so the requested temporary path does
	// not exist until close. WRITE_READ creates the exact path while still
	// truncating it, which lets us restrict permissions before storing the token.
	Error open_error = OK;
	Ref<FileAccess> file = FileAccess::open(temporary_path, FileAccess::WRITE_READ, &open_error);
	ERR_FAIL_COND_V_MSG(file.is_null(), open_error, "Godot Agent could not create its temporary endpoint file");
#ifdef UNIX_ENABLED
	const Error file_permissions_error = FileAccess::set_unix_permissions(temporary_path, 0600);
	if (file_permissions_error != OK) {
		ERR_PRINT("Godot Agent could not restrict its endpoint file permissions: " + String(error_names[file_permissions_error]));
		file.unref();
		DirAccess::remove_absolute(temporary_path);
		return file_permissions_error;
	}
#endif

	Dictionary endpoint;
	endpoint["host"] = "127.0.0.1";
	endpoint["port"] = server->get_local_port();
	endpoint["token"] = auth_token;
	endpoint["protocol_version"] = PROTOCOL_VERSION;
	endpoint["pid"] = OS::get_singleton()->get_process_id();
	endpoint["project_path"] = ProjectSettings::get_singleton()->get_resource_path();
	endpoint["engine"] = Engine::get_singleton()->get_version_info();
	file->store_string(JSON::stringify(endpoint, "\t") + "\n");
	file->flush();
	const Error write_error = file->get_error();
	file.unref();
	if (write_error != OK) {
		ERR_PRINT("Godot Agent could not write its endpoint file: " + String(error_names[write_error]));
		DirAccess::remove_absolute(temporary_path);
		return write_error;
	}
	if (!FileAccess::exists(temporary_path)) {
		ERR_PRINT("Godot Agent temporary endpoint file disappeared before installation");
		return ERR_FILE_NOT_FOUND;
	}
#ifdef UNIX_ENABLED
	if (static_cast<int64_t>(FileAccess::get_unix_permissions(temporary_path)) != 0600) {
		ERR_PRINT("Godot Agent temporary endpoint file permissions changed before installation");
		DirAccess::remove_absolute(temporary_path);
		return ERR_UNAUTHORIZED;
	}
#endif
	if (FileAccess::exists(absolute_path)) {
		DirAccess::remove_absolute(absolute_path);
	}
	const Error rename_error = DirAccess::rename_absolute(temporary_path, absolute_path);
	if (rename_error != OK) {
		ERR_PRINT("Godot Agent could not atomically install its endpoint file: " + String(error_names[rename_error]));
		DirAccess::remove_absolute(temporary_path);
	}
	return rename_error;
}

void GodotAgentEditorPlugin::_remove_endpoint_if_owned() {
	if (endpoint_path.is_empty() || auth_token.is_empty()) {
		return;
	}
	const String absolute_path = ProjectSettings::get_singleton()->globalize_path(endpoint_path);
	if (!FileAccess::exists(absolute_path)) {
		return;
	}
	Ref<FileAccess> file = FileAccess::open(absolute_path, FileAccess::READ);
	if (file.is_null()) {
		return;
	}
	JSON json;
	if (json.parse(file->get_as_text()) != OK || json.get_data().get_type() != Variant::DICTIONARY) {
		return;
	}
	const Dictionary endpoint = json.get_data();
	if ((String)endpoint.get("token", "") != auth_token || (int64_t)endpoint.get("pid", -1) != OS::get_singleton()->get_process_id()) {
		return;
	}
	DirAccess::remove_absolute(absolute_path);
}

void GodotAgentEditorPlugin::_stop() {
	_clear_agent_previews();
	if (server.is_valid()) {
		for (Peer &peer : peers) {
			if (peer.connection.is_valid()) {
				peer.connection->disconnect_from_host();
			}
		}
		peers.clear();
		server->stop();
		server.unref();
	}
	_remove_endpoint_if_owned();
	auth_token.clear();
	endpoint_path.clear();
	started = false;
}

void GodotAgentEditorPlugin::_clear_agent_previews() {
	Node3DEditor *node_3d_editor = Node3DEditor::get_singleton();
	if (!node_3d_editor) {
		preview_viewport_mask = 0;
		return;
	}
	for (int i = 0; i < 4; i++) {
		if (preview_viewport_mask & (1 << i)) {
			node_3d_editor->get_editor_viewport(i)->stop_camera_preview();
		}
	}
	preview_viewport_mask = 0;
}

void GodotAgentEditorPlugin::_accept_connections() {
	while (server->is_connection_available()) {
		Ref<StreamPeerTCP> connection = server->take_connection();
		if (connection.is_null()) {
			break;
		}
		connection->set_no_delay(true);
		if (peers.size() >= MAX_PEERS) {
			connection->disconnect_from_host();
			continue;
		}
		Peer peer;
		peer.connection = connection;
		peer.last_activity_msec = OS::get_singleton()->get_ticks_msec();
		peers.push_back(peer);
	}
}

void GodotAgentEditorPlugin::_poll() {
	_accept_connections();
	for (int i = peers.size() - 1; i >= 0; i--) {
		Peer &peer = peers.write[i];
		peer.connection->poll();
		const StreamPeerTCP::Status status = peer.connection->get_status();
		const bool idle = OS::get_singleton()->get_ticks_msec() - peer.last_activity_msec > PEER_IDLE_TIMEOUT_MSEC;
		if (status != StreamPeerTCP::STATUS_CONNECTED || idle) {
			peer.connection->disconnect_from_host();
			peers.remove_at(i);
			continue;
		}
		const Error flush_error = _flush_peer_output(peer);
		if (flush_error != OK || (peer.close_after_output && peer.output.is_empty())) {
			peer.connection->disconnect_from_host();
			peers.remove_at(i);
			continue;
		}
		if (!peer.close_after_output && _poll_peer(peer) != OK) {
			peer.connection->disconnect_from_host();
			peers.remove_at(i);
		}
	}
}

Error GodotAgentEditorPlugin::_flush_peer_output(Peer &r_peer) {
	if (r_peer.output.is_empty()) {
		return OK;
	}
	int sent = 0;
	const Error send_error = r_peer.connection->put_partial_data(r_peer.output.ptr(), r_peer.output.size(), sent);
	if (send_error != OK) {
		return send_error;
	}
	if (sent > 0) {
		r_peer.output = r_peer.output.slice(sent);
		r_peer.last_activity_msec = OS::get_singleton()->get_ticks_msec();
	}
	return OK;
}

Error GodotAgentEditorPlugin::_poll_peer(Peer &r_peer) {
	const int available = r_peer.connection->get_available_bytes();
	if (available <= 0) {
		return OK;
	}
	if (r_peer.input.size() + available > MAX_MESSAGE_BYTES + 4096) {
		return ERR_OUT_OF_MEMORY;
	}

	PackedByteArray chunk;
	chunk.resize(available);
	int received = 0;
	const Error read_error = r_peer.connection->get_partial_data(chunk.ptrw(), available, received);
	if (read_error != OK) {
		return read_error;
	}
	if (received > 0) {
		r_peer.input.append_array(chunk.slice(0, received));
		r_peer.last_activity_msec = OS::get_singleton()->get_ticks_msec();
	}
	return _consume_messages(r_peer);
}

Error GodotAgentEditorPlugin::_consume_messages(Peer &r_peer) {
	while (true) {
		int header_end = -1;
		for (int i = 0; i + 3 < r_peer.input.size(); i++) {
			if (r_peer.input[i] == '\r' && r_peer.input[i + 1] == '\n' && r_peer.input[i + 2] == '\r' && r_peer.input[i + 3] == '\n') {
				header_end = i;
				break;
			}
		}
		if (header_end < 0) {
			return r_peer.input.size() > 4096 ? ERR_INVALID_DATA : OK;
		}

		const String header = String::utf8(reinterpret_cast<const char *>(r_peer.input.ptr()), header_end);
		int content_length = -1;
		for (const String &line : header.split("\r\n")) {
			if (line.to_lower().begins_with("content-length:")) {
				if (content_length >= 0) {
					return ERR_INVALID_DATA;
				}
				const String value = line.get_slice(":", 1).strip_edges();
				if (value.is_empty()) {
					return ERR_INVALID_DATA;
				}
				int64_t parsed_length = 0;
				for (int i = 0; i < value.length(); i++) {
					const char32_t character = value[i];
					if (character < '0' || character > '9') {
						return ERR_INVALID_DATA;
					}
					parsed_length = parsed_length * 10 + (character - '0');
					if (parsed_length > MAX_MESSAGE_BYTES) {
						return ERR_INVALID_DATA;
					}
				}
				content_length = parsed_length;
			}
		}
		if (content_length < 0 || content_length > MAX_MESSAGE_BYTES) {
			return ERR_INVALID_DATA;
		}

		const int body_start = header_end + 4;
		const int message_end = body_start + content_length;
		if (r_peer.input.size() < message_end) {
			return OK;
		}
		const String request = String::utf8(reinterpret_cast<const char *>(r_peer.input.ptr() + body_start), content_length);
		r_peer.input = r_peer.input.slice(message_end);
		const String response = _process_message(request);
		if (!response.is_empty()) {
			const Error send_error = _queue_message(r_peer, response);
			if (send_error != OK) {
				return send_error;
			}
			r_peer.close_after_output = true;
			return OK;
		}
	}
}

Error GodotAgentEditorPlugin::_queue_message(Peer &r_peer, const String &p_message) {
	PackedByteArray body = p_message.to_utf8_buffer();
	PackedByteArray output = vformat("Content-Length: %d\r\n\r\n", body.size()).to_utf8_buffer();
	output.append_array(body);
	if (r_peer.output.size() + output.size() > MAX_PEER_OUTPUT_BYTES) {
		return ERR_OUT_OF_MEMORY;
	}
	r_peer.output.append_array(output);
	r_peer.last_activity_msec = OS::get_singleton()->get_ticks_msec();
	return OK;
}

String GodotAgentEditorPlugin::_process_message(const String &p_message) {
	JSON json;
	if (json.parse(p_message) != OK) {
		return Variant(rpc.make_response_error(JSONRPC::PARSE_ERROR, "Parse error")).to_json_string();
	}
	if (json.get_data().get_type() != Variant::DICTIONARY) {
		return Variant(rpc.make_response_error(JSONRPC::INVALID_REQUEST, "Only individual request objects are supported")).to_json_string();
	}

	Dictionary request = json.get_data();
	const Variant id = request.get("id", Variant());
	const Variant params_value = request.get("params", Variant());
	if (params_value.get_type() != Variant::DICTIONARY) {
		return Variant(rpc.make_response_error(JSONRPC::INVALID_PARAMS, "params must be an object", id)).to_json_string();
	}
	Dictionary params = params_value;
	if ((String)params.get("token", "") != auth_token) {
		return Variant(rpc.make_response_error(-32001, "Unauthorized", id)).to_json_string();
	}
	params.erase("token");
	const String method = request.get("method", "");
	const String schema = _parameter_schema(method);
	if (schema != "*") {
		const PackedStringArray allowed = schema.split(",", false);
		for (const KeyValue<Variant, Variant> &entry : params) {
			const String key = entry.key;
			if (!allowed.has(key)) {
				return Variant(rpc.make_response_error(JSONRPC::INVALID_PARAMS, "Unknown parameter: " + key, id)).to_json_string();
			}
		}
	}
	request["params"] = params;

	const Variant response = rpc.process_action(request);
	if (response.get_type() == Variant::NIL) {
		return String();
	}
	const String serialized = response.to_json_string();
	if (serialized.to_utf8_buffer().size() > MAX_MESSAGE_BYTES) {
		return Variant(rpc.make_response_error(-32002, "Response exceeds the protocol size limit; narrow the query", id)).to_json_string();
	}
	return serialized;
}

Dictionary GodotAgentEditorPlugin::_ok(const Variant &p_data) const {
	Dictionary result;
	result["ok"] = true;
	if (p_data.get_type() != Variant::NIL) {
		result["data"] = p_data;
	}
	return result;
}

Dictionary GodotAgentEditorPlugin::_fail(const String &p_code, const String &p_message, const Variant &p_details) const {
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

Variant GodotAgentEditorPlugin::_encode_variant(const Variant &p_value, int p_depth) const {
	if (p_depth > Variant::MAX_RECURSION_DEPTH) {
		return Variant();
	}
	switch (p_value.get_type()) {
		case Variant::NIL:
		case Variant::BOOL:
		case Variant::INT:
		case Variant::FLOAT:
			return p_value;
		case Variant::STRING: {
			const String string_value = p_value;
			if (string_value.length() <= MAX_ENCODED_STRING_LENGTH) {
				return string_value;
			}
			Dictionary truncated;
			truncated["@type"] = "String";
			truncated["length"] = string_value.length();
			truncated["preview"] = string_value.left(MAX_ENCODED_STRING_LENGTH);
			truncated["truncated"] = true;
			return truncated;
		}
		case Variant::STRING_NAME:
		case Variant::NODE_PATH:
			return String(p_value);
		case Variant::OBJECT: {
			Object *object = p_value.get_validated_object();
			if (!object) {
				return Variant();
			}
			if (Resource *resource = Object::cast_to<Resource>(object)) {
				if (_is_safe_resource_path(resource->get_path(), "")) {
					Dictionary resource_ref;
					resource_ref["@type"] = "Resource";
					resource_ref["class"] = object->get_class();
					resource_ref["path"] = resource->get_path();
					return resource_ref;
				}
			}
			Dictionary ref;
			ref["@type"] = "ObjectRef";
			ref["class"] = object->get_class();
			ref["instance_id"] = (uint64_t)object->get_instance_id();
			return ref;
		}
		case Variant::ARRAY: {
			Array encoded;
			const Array source = p_value;
			const int limit = MIN(source.size(), MAX_ENCODED_CONTAINER_ITEMS);
			for (int i = 0; i < limit; i++) {
				encoded.push_back(_encode_variant(source[i], p_depth + 1));
			}
			if (source.size() > limit) {
				Dictionary truncated;
				truncated["@truncated"] = source.size() - limit;
				encoded.push_back(truncated);
			}
			return encoded;
		}
		case Variant::DICTIONARY: {
			Dictionary encoded;
			int count = 0;
			for (const KeyValue<Variant, Variant> &entry : (Dictionary)p_value) {
				if (count >= MAX_ENCODED_CONTAINER_ITEMS) {
					encoded["@truncated"] = ((Dictionary)p_value).size() - count;
					break;
				}
				encoded[String(entry.key)] = _encode_variant(entry.value, p_depth + 1);
				count++;
			}
			return encoded;
		}
		default: {
			const int64_t packed_size = _packed_array_size(p_value);
			if (packed_size > MAX_ENCODED_CONTAINER_ITEMS) {
				Dictionary truncated;
				truncated["@type"] = Variant::get_type_name(p_value.get_type());
				truncated["size"] = packed_size;
				truncated["truncated"] = true;
				return truncated;
			}
			Variant encoded = JSON::from_native(p_value);
			if (encoded.get_type() == Variant::DICTIONARY) {
				Dictionary tagged = encoded;
				if (tagged.has("type")) {
					tagged["@type"] = tagged["type"];
					tagged.erase("type");
				}
				return tagged;
			}
			return encoded;
		}
	}
}

Variant GodotAgentEditorPlugin::_decode_variant(const Variant &p_value, int p_depth, bool *r_valid) const {
	if (r_valid) {
		*r_valid = true;
	}
	if (p_depth > Variant::MAX_RECURSION_DEPTH) {
		if (r_valid) {
			*r_valid = false;
		}
		return Variant();
	}
	if (p_value.get_type() == Variant::DICTIONARY) {
		const Dictionary dict = p_value;
		if ((String)dict.get("@type", "") == "Resource") {
			const String path = dict.get("path", "");
			if (!_is_safe_resource_path(path, "") || !ResourceLoader::exists(path)) {
				if (r_valid) {
					*r_valid = false;
				}
				return Variant();
			}
			Ref<Resource> resource = ResourceLoader::load(path);
			if (resource.is_null()) {
				if (r_valid) {
					*r_valid = false;
				}
				return Variant();
			}
			return resource;
		}
		if (dict.has("@type") && (String)dict["@type"] != "ObjectRef") {
			const Variant::Type expected_type = Variant::get_type_by_name(dict["@type"]);
			if (expected_type == Variant::VARIANT_MAX || expected_type == Variant::NIL || expected_type == Variant::BOOL || expected_type == Variant::INT ||
					expected_type == Variant::FLOAT || expected_type == Variant::STRING || expected_type == Variant::OBJECT) {
				if (r_valid) {
					*r_valid = false;
				}
				return Variant();
			}
			Dictionary native_tag = dict.duplicate();
			native_tag["type"] = native_tag["@type"];
			native_tag.erase("@type");
			Variant decoded = JSON::to_native(native_tag, false);
			if (decoded.get_type() != expected_type) {
				if (r_valid) {
					*r_valid = false;
				}
				return Variant();
			}
			return decoded;
		}
		Dictionary decoded;
		for (const KeyValue<Variant, Variant> &entry : dict) {
			bool child_valid = true;
			decoded[entry.key] = _decode_variant(entry.value, p_depth + 1, &child_valid);
			if (!child_valid && r_valid) {
				*r_valid = false;
			}
		}
		return decoded;
	}
	if (p_value.get_type() == Variant::ARRAY) {
		Array decoded;
		for (const Variant &item : (Array)p_value) {
			bool child_valid = true;
			decoded.push_back(_decode_variant(item, p_depth + 1, &child_valid));
			if (!child_valid && r_valid) {
				*r_valid = false;
			}
		}
		return decoded;
	}
	return p_value;
}

Dictionary GodotAgentEditorPlugin::_set_node_property(Node *p_node, const StringName &p_property, const Variant &p_wire_value) const {
	if (p_property == SNAME("owner") || p_property == SNAME("scene_file_path")) {
		return _fail("property_blocked", "This structural scene property cannot be changed through the agent bridge", String(p_property));
	}
	PropertyInfo info;
	if (!_find_property_info(p_node, p_property, info)) {
		return _fail("property_not_found", "Property does not exist", String(p_property));
	}
	if (info.usage & PROPERTY_USAGE_READ_ONLY) {
		return _fail("property_read_only", "Property is read-only", String(p_property));
	}

	bool decoded_valid = true;
	const Variant decoded = _decode_variant(p_wire_value, 0, &decoded_valid);
	const bool variant_property = info.type == Variant::NIL && (info.usage & PROPERTY_USAGE_NIL_IS_VARIANT);
	if (!decoded_valid || (!variant_property && !Variant::can_convert_strict(decoded.get_type(), info.type))) {
		Dictionary details;
		details["property"] = p_property;
		details["value_type"] = Variant::get_type_name(decoded.get_type());
		details["expected_type"] = Variant::get_type_name(info.type);
		return _fail("property_type_mismatch", "Property value has an incompatible type", details);
	}
	if (decoded.get_type() == Variant::OBJECT && !_object_matches_property(decoded.get_validated_object(), info)) {
		Dictionary details;
		details["property"] = p_property;
		details["expected_class"] = info.hint == PROPERTY_HINT_RESOURCE_TYPE ? info.hint_string : String(info.class_name);
		Object *object = decoded.get_validated_object();
		details["value_class"] = object ? object->get_class() : String();
		return _fail("property_class_mismatch", "Object value does not match the property's required class", details);
	}

	bool set_valid = false;
	p_node->set(p_property, decoded, &set_valid);
	if (!set_valid) {
		return _fail("property_set_rejected", "The node rejected the property assignment", String(p_property));
	}
	Dictionary result_data;
	result_data["property"] = p_property;
	result_data["value"] = _encode_variant(p_node->get(p_property));
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_apply_node_properties(Node *p_node, const Dictionary &p_properties) const {
	if (p_properties.has("script")) {
		Dictionary script_result = _set_node_property(p_node, SNAME("script"), p_properties["script"]);
		if (!(bool)script_result.get("ok", false)) {
			return script_result;
		}
	}
	for (const KeyValue<Variant, Variant> &entry : p_properties) {
		const StringName property = entry.key;
		if (property == SNAME("script")) {
			continue;
		}
		Dictionary property_result = _set_node_property(p_node, property, entry.value);
		if (!(bool)property_result.get("ok", false)) {
			return property_result;
		}
	}
	return _ok();
}

Node *GodotAgentEditorPlugin::_edited_root() const {
	return EditorInterface::get_singleton()->get_edited_scene_root();
}

Node *GodotAgentEditorPlugin::_find_node(const Dictionary &p_params, const StringName &p_key) const {
	Node *root = _edited_root();
	if (!root) {
		return nullptr;
	}
	const String path = p_params.get(p_key, ".");
	if (path == ".") {
		return root;
	}
	if (!_is_safe_node_path(path)) {
		return nullptr;
	}
	return root->get_node_or_null(NodePath(path));
}

Dictionary GodotAgentEditorPlugin::_describe_node(Node *p_node, Node *p_root, bool p_include_warnings) const {
	Dictionary result_data;
	result_data["path"] = p_node == p_root ? "." : String(p_root->get_path_to(p_node));
	result_data["name"] = String(p_node->get_name());
	result_data["type"] = p_node->get_class();
	result_data["child_count"] = p_node->get_child_count(false);
	if (!p_node->get_scene_file_path().is_empty()) {
		result_data["scene_file_path"] = p_node->get_scene_file_path();
	}
	if (p_node->has_meta(SNAME("extras"))) {
		Dictionary node_metadata;
		node_metadata["extras"] = _encode_variant(p_node->get_meta(SNAME("extras")));
		result_data["metadata"] = node_metadata;
	}
	if (p_node->get_owner()) {
		result_data["owner_path"] = p_node->get_owner() == p_root ? "." : String(p_root->get_path_to(p_node->get_owner()));
	}
	if (Node3D *node_3d = Object::cast_to<Node3D>(p_node)) {
		result_data["visible"] = node_3d->is_visible_in_tree();
		result_data["transform"] = _encode_variant(node_3d->get_transform());
		result_data["global_transform"] = _encode_variant(node_3d->get_global_transform());
	}
	if (Node2D *node_2d = Object::cast_to<Node2D>(p_node)) {
		result_data["visible"] = node_2d->is_visible_in_tree();
		result_data["transform"] = _encode_variant(node_2d->get_transform());
		result_data["global_transform"] = _encode_variant(node_2d->get_global_transform());
	}
	if (VisualInstance3D *visual = Object::cast_to<VisualInstance3D>(p_node)) {
		result_data["local_aabb"] = _encode_variant(visual->get_aabb());
	}
	if (Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(p_node)) {
		result_data["bone_count"] = skeleton->get_bone_count();
	}
	if (p_include_warnings) {
		result_data["warnings"] = p_node->get_configuration_warnings();
	}
	return result_data;
}

Dictionary GodotAgentEditorPlugin::_describe_tree(Node *p_node, Node *p_root, int p_depth, int p_max_depth, bool p_include_internal, bool p_include_warnings, int &r_node_count) const {
	r_node_count++;
	Dictionary result_data = _describe_node(p_node, p_root, p_include_warnings);
	if (p_depth >= p_max_depth) {
		result_data["truncated"] = p_node->get_child_count(p_include_internal) > 0;
		return result_data;
	}
	Array children;
	for (int i = 0; i < p_node->get_child_count(p_include_internal); i++) {
		if (r_node_count >= MAX_TREE_NODES) {
			result_data["truncated"] = true;
			break;
		}
		Node *child = p_node->get_child(i, p_include_internal);
		children.push_back(_describe_tree(child, p_root, p_depth + 1, p_max_depth, p_include_internal, p_include_warnings, r_node_count));
	}
	result_data["children"] = children;
	return result_data;
}

Dictionary GodotAgentEditorPlugin::_rpc_health(Dictionary p_params) {
	Dictionary result_data;
	result_data["protocol_version"] = PROTOCOL_VERSION;
	result_data["engine"] = Engine::get_singleton()->get_version_info();
	result_data["project_path"] = ProjectSettings::get_singleton()->get_resource_path();
	result_data["scene_path"] = _edited_root() ? _edited_root()->get_scene_file_path() : String();
	result_data["playing"] = EditorInterface::get_singleton()->is_playing_scene();
	Array capabilities;
	capabilities.push_back("project_settings");
	capabilities.push_back("scene_crud");
	capabilities.push_back("scene_snapshot");
	capabilities.push_back("scene_validation");
	capabilities.push_back("asset_scan");
	capabilities.push_back("viewport_capture");
	capabilities.push_back("rig_inspection");
	capabilities.push_back("game_control");
	capabilities.push_back("runtime_probe");
	result_data["capabilities"] = capabilities;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_create(Dictionary p_params) {
	if (_edited_root()) {
		return _fail("scene_already_open", "Close the current scene before creating a new root");
	}
	for (const StringName &key : { SNAME("path"), SNAME("type"), SNAME("name") }) {
		if (p_params.has(key) && !_is_string_value(p_params[key])) {
			return _fail("invalid_params", String(key) + " must be a string");
		}
	}
	const String path = p_params.get("path", "");
	if (!path.is_empty() && !_is_safe_resource_path(path, "tscn")) {
		return _fail("invalid_scene_path", "Scene path must be a project-local res:// .tscn path", path);
	}
	const String type = p_params.get("type", "Node3D");
	Object *object = ClassDB::instantiate(type);
	Node *root = Object::cast_to<Node>(object);
	if (!root) {
		if (object) {
			memdelete(object);
		}
		return _fail("invalid_node_type", "Class is not an instantiable Node", type);
	}
	root->set_name((String)p_params.get("name", "Main"));
	EditorInterface::get_singleton()->add_root_node(root);
	if (!path.is_empty()) {
		const Error save_error = EditorNode::get_singleton()->save_scene_to_path_with_result(path, false);
		if (save_error != OK) {
			return _fail("save_failed", String(error_names[save_error]), path);
		}
	}
	return _ok(_describe_node(root, root, true));
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_open(Dictionary p_params) {
	if (!p_params.has("path") || !_is_string_value(p_params["path"])) {
		return _fail("invalid_params", "path is required and must be a string");
	}
	const String path = p_params.get("path", "");
	if (!_is_safe_resource_path(path, "tscn")) {
		return _fail("invalid_scene_path", "Scene path must be a project-local res:// .tscn path", path);
	}
	if (!FileAccess::exists(path)) {
		return _fail("scene_not_found", "Scene does not exist", path);
	}
	EditorInterface::get_singleton()->open_scene_from_path(path);
	Dictionary result_data;
	result_data["path"] = path;
	result_data["accepted"] = true;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_get_tree(Dictionary p_params) {
	Node *root = _edited_root();
	if (!root) {
		return _fail("no_edited_scene", "No scene is open");
	}
	const Variant max_depth_value = p_params.get("max_depth", 32);
	const Variant include_internal_value = p_params.get("include_internal", false);
	const Variant include_warnings_value = p_params.get("include_warnings", true);
	if (!_is_integer_in_range(max_depth_value, 0, 128) || include_internal_value.get_type() != Variant::BOOL || include_warnings_value.get_type() != Variant::BOOL) {
		return _fail("invalid_params", "max_depth must be an integer from 0 to 128 and include flags must be booleans");
	}
	const int max_depth = max_depth_value;
	const bool include_internal = include_internal_value;
	const bool include_warnings = include_warnings_value;
	int node_count = 0;
	Dictionary snapshot = _describe_tree(root, root, 0, max_depth, include_internal, include_warnings, node_count);
	snapshot["snapshot_node_count"] = node_count;
	snapshot["snapshot_truncated"] = node_count >= MAX_TREE_NODES;
	return _ok(snapshot);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_create_node(Dictionary p_params) {
	Node *root = _edited_root();
	if (!root) {
		return _fail("no_edited_scene", "No scene is open");
	}
	if (!p_params.has("type") || !_is_string_value(p_params["type"]) || (p_params.has("parent_path") && !_is_string_value(p_params["parent_path"])) || (p_params.has("name") && !_is_string_value(p_params["name"]))) {
		return _fail("invalid_params", "type is required and type, parent_path, and name must be strings");
	}
	Node *parent = _find_node(p_params, "parent_path");
	if (!parent) {
		return _fail("parent_not_found", "Parent node was not found", p_params.get("parent_path", "."));
	}
	if (!_is_editable_scene_node(root, parent)) {
		return _fail("node_not_editable", "Cannot add a child below a non-editable scene instance node", p_params.get("parent_path", "."));
	}
	const String type = p_params.get("type", "");
	Object *object = ClassDB::instantiate(type);
	Node *node = Object::cast_to<Node>(object);
	if (!node) {
		if (object) {
			memdelete(object);
		}
		return _fail("invalid_node_type", "Class is not an instantiable Node", type);
	}
	if (p_params.has("name")) {
		node->set_name((String)p_params["name"]);
	}

	const Variant properties_value = p_params.get("properties", Dictionary());
	if (properties_value.get_type() != Variant::DICTIONARY) {
		memdelete(node);
		return _fail("invalid_params", "properties must be an object");
	}
	const Dictionary properties = properties_value;
	Dictionary properties_result = _apply_node_properties(node, properties);
	if (!(bool)properties_result.get("ok", false)) {
		memdelete(node);
		return properties_result;
	}
	parent->add_child(node, true);
	node->set_owner(root);
	EditorInterface::get_singleton()->mark_scene_as_unsaved();
	Dictionary result_data = _describe_node(node, root, true);
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_instantiate(Dictionary p_params) {
	Node *root = _edited_root();
	if (!root) {
		return _fail("no_edited_scene", "No scene is open");
	}
	if (!p_params.has("path") || p_params["path"].get_type() != Variant::STRING) {
		return _fail("invalid_params", "path is required and must be a string");
	}
	if ((p_params.has("parent_path") && !_is_string_value(p_params["parent_path"])) || (p_params.has("name") && !_is_string_value(p_params["name"]))) {
		return _fail("invalid_params", "parent_path and name must be strings");
	}
	const String path = p_params["path"];
	if (!_is_safe_resource_path(path, "")) {
		return _fail("invalid_scene_path", "Scene path must be a project-local res:// resource without symlink traversal", path);
	}
	Node *parent = _find_node(p_params, "parent_path");
	if (!parent) {
		return _fail("parent_not_found", "Parent node was not found", p_params.get("parent_path", "."));
	}
	if (!_is_editable_scene_node(root, parent)) {
		return _fail("node_not_editable", "Cannot instantiate below a non-editable scene instance node", p_params.get("parent_path", "."));
	}
	Ref<PackedScene> packed_scene = ResourceLoader::load(path);
	if (packed_scene.is_null()) {
		return _fail("scene_load_failed", "Resource is not an importable PackedScene", path);
	}
	if (!root->get_scene_file_path().is_empty() && path == root->get_scene_file_path()) {
		return _fail("cyclic_scene", "The edited scene cannot instantiate itself", path);
	}
	Node *instance = packed_scene->instantiate(PackedScene::GEN_EDIT_STATE_INSTANCE);
	if (!instance) {
		return _fail("scene_instantiate_failed", "PackedScene could not be instantiated", path);
	}
	if (!root->get_scene_file_path().is_empty() && _scene_dependency_reaches(root->get_scene_file_path(), instance)) {
		memdelete(instance);
		return _fail("cyclic_scene", "The requested scene depends on the edited scene", path);
	}
	instance->set_scene_file_path(ProjectSettings::get_singleton()->localize_path(path));
	if (p_params.has("name")) {
		if (p_params["name"].get_type() != Variant::STRING && p_params["name"].get_type() != Variant::STRING_NAME) {
			memdelete(instance);
			return _fail("invalid_params", "name must be a string");
		}
		instance->set_name((String)p_params["name"]);
	}
	const Variant properties_value = p_params.get("properties", Dictionary());
	if (properties_value.get_type() != Variant::DICTIONARY) {
		memdelete(instance);
		return _fail("invalid_params", "properties must be an object");
	}
	Dictionary properties_result = _apply_node_properties(instance, properties_value);
	if (!(bool)properties_result.get("ok", false)) {
		memdelete(instance);
		return properties_result;
	}
	parent->add_child(instance, true);
	instance->set_owner(root);
	EditorInterface::get_singleton()->mark_scene_as_unsaved();
	Dictionary result_data = _describe_node(instance, root, true);
	result_data["resource_path"] = path;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_set_property(Dictionary p_params) {
	if (!p_params.has("node_path") || !_is_string_value(p_params["node_path"])) {
		return _fail("invalid_params", "node_path is required and must be a string");
	}
	Node *node = _find_node(p_params);
	Node *root = _edited_root();
	if (!node) {
		return _fail("node_not_found", "Node was not found", p_params.get("node_path", "."));
	}
	if (!_is_editable_scene_node(root, node)) {
		return _fail("node_not_editable", "Cannot mutate a non-editable scene instance node", p_params.get("node_path", "."));
	}
	if (!p_params.has("property") || !_is_string_value(p_params["property"])) {
		return _fail("invalid_params", "property is required and must be a string");
	}
	const StringName property = p_params["property"];
	if (property == StringName() || !p_params.has("value")) {
		return _fail("invalid_params", "property and value are required");
	}
	Dictionary property_result = _set_node_property(node, property, p_params["value"]);
	if (!(bool)property_result.get("ok", false)) {
		return property_result;
	}
	EditorInterface::get_singleton()->mark_scene_as_unsaved();
	Dictionary result_data = property_result["data"];
	result_data["node_path"] = p_params.get("node_path", ".");
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_delete_node(Dictionary p_params) {
	if (!p_params.has("node_path") || !_is_string_value(p_params["node_path"])) {
		return _fail("invalid_params", "node_path is required and must be a string");
	}
	Node *node = _find_node(p_params);
	Node *root = _edited_root();
	if (!node) {
		return _fail("node_not_found", "Node was not found", p_params.get("node_path", "."));
	}
	if (node == root) {
		return _fail("cannot_delete_root", "The edited scene root cannot be deleted");
	}
	if (!_is_editable_scene_node(root, node)) {
		return _fail("node_not_editable", "Cannot delete a non-editable scene instance node", p_params.get("node_path", "."));
	}
	const String path = String(root->get_path_to(node));
	node->get_parent()->remove_child(node);
	memdelete(node);
	EditorInterface::get_singleton()->mark_scene_as_unsaved();
	Dictionary result_data;
	result_data["deleted_path"] = path;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_reparent_node(Dictionary p_params) {
	if (!p_params.has("node_path") || !p_params.has("new_parent_path")) {
		return _fail("invalid_params", "node_path and new_parent_path are required");
	}
	if (!_is_string_value(p_params["node_path"]) || !_is_string_value(p_params["new_parent_path"])) {
		return _fail("invalid_params", "node_path and new_parent_path must be strings");
	}
	const Variant keep_global_transform = p_params.get("keep_global_transform", true);
	if (keep_global_transform.get_type() != Variant::BOOL) {
		return _fail("invalid_params", "keep_global_transform must be a boolean");
	}
	Node *node = _find_node(p_params);
	Node *new_parent = _find_node(p_params, "new_parent_path");
	Node *root = _edited_root();
	if (!node || !new_parent) {
		return _fail("node_not_found", "Node or new parent was not found");
	}
	if (!_is_editable_scene_node(root, node) || !_is_editable_scene_node(root, new_parent)) {
		return _fail("node_not_editable", "Cannot reparent a non-editable scene instance node or move a node below one");
	}
	if (node == root || node->is_ancestor_of(new_parent)) {
		return _fail("invalid_reparent", "Cannot reparent the root or create a cycle");
	}
	node->reparent(new_parent, keep_global_transform);
	node->set_owner(root);
	EditorInterface::get_singleton()->mark_scene_as_unsaved();
	return _ok(_describe_node(node, root, true));
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_save(Dictionary p_params) {
	Node *root = _edited_root();
	if (!root) {
		return _fail("no_edited_scene", "No scene is open");
	}
	if (p_params.has("path") && !_is_string_value(p_params["path"])) {
		return _fail("invalid_params", "path must be a string");
	}
	const String path = p_params.get("path", "");
	if (!path.is_empty()) {
		if (!_is_safe_resource_path(path, "tscn")) {
			return _fail("invalid_scene_path", "Scene path must be a project-local res:// .tscn path", path);
		}
		const Error error = EditorNode::get_singleton()->save_scene_to_path_with_result(path, false);
		if (error != OK) {
			return _fail("save_failed", String(error_names[error]), path);
		}
	} else {
		const String current_path = root->get_scene_file_path();
		if (current_path.is_empty()) {
			return _fail("save_failed", "The edited scene has no path");
		}
		if (!_is_safe_resource_path(current_path, "tscn")) {
			return _fail("invalid_scene_path", "The edited scene path is not a project-local res:// .tscn path", current_path);
		}
		const Error error = EditorNode::get_singleton()->save_scene_to_path_with_result(current_path, false);
		if (error != OK) {
			return _fail("save_failed", String(error_names[error]));
		}
	}
	Dictionary result_data;
	result_data["path"] = path.is_empty() ? root->get_scene_file_path() : path;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_scene_validate(Dictionary p_params) {
	Node *root = _edited_root();
	if (!root) {
		return _fail("no_edited_scene", "No scene is open");
	}
	Array warnings;
	List<Node *> pending;
	pending.push_back(root);
	while (!pending.is_empty()) {
		Node *node = pending.front()->get();
		pending.pop_front();
		for (const String &warning : node->get_configuration_warnings()) {
			Dictionary item;
			item["node_path"] = node == root ? "." : String(root->get_path_to(node));
			item["message"] = warning;
			warnings.push_back(item);
		}
		for (int i = 0; i < node->get_child_count(false); i++) {
			pending.push_back(node->get_child(i, false));
		}
	}
	Dictionary result_data;
	result_data["valid"] = warnings.is_empty();
	result_data["warnings"] = warnings;
	result_data["warning_count"] = warnings.size();
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_node_inspect(Dictionary p_params) {
	if (!p_params.has("node_path") || !_is_string_value(p_params["node_path"])) {
		return _fail("invalid_params", "node_path is required and must be a string");
	}
	Node *node = _find_node(p_params);
	if (!node) {
		return _fail("node_not_found", "Node was not found", p_params.get("node_path", "."));
	}
	Dictionary values;
	Array property_schema;
	List<PropertyInfo> properties;
	node->get_property_list(&properties);
	const Variant requested_value = p_params.get("properties", Array());
	if (requested_value.get_type() != Variant::ARRAY) {
		return _fail("invalid_params", "properties must be an array of names");
	}
	const Array requested = requested_value;
	HashSet<StringName> requested_names;
	for (const Variant &name : requested) {
		if (!_is_string_value(name)) {
			return _fail("invalid_params", "properties entries must be strings");
		}
		requested_names.insert(StringName(name));
	}
	for (const PropertyInfo &property : properties) {
		if (!requested_names.is_empty() && !requested_names.has(property.name)) {
			continue;
		}
		if (requested_names.is_empty() && !(property.usage & PROPERTY_USAGE_STORAGE)) {
			continue;
		}
		Dictionary info;
		info["name"] = property.name;
		info["type"] = Variant::get_type_name(property.type);
		info["usage"] = property.usage;
		info["hint"] = property.hint;
		info["hint_string"] = property.hint_string;
		property_schema.push_back(info);
		values[property.name] = _encode_variant(node->get(property.name));
	}
	Dictionary result_data = _describe_node(node, _edited_root(), true);
	result_data["property_schema"] = property_schema;
	result_data["properties"] = values;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_project_get_setting(Dictionary p_params) {
	if (!p_params.has("key") || !_is_string_value(p_params["key"])) {
		return _fail("invalid_params", "key is required and must be a string");
	}
	const StringName key = p_params.get("key", "");
	if (key == StringName()) {
		return _fail("invalid_params", "key is required");
	}
	if (!ProjectSettings::get_singleton()->has_setting(key)) {
		return _fail("setting_not_found", "Project setting does not exist", String(key));
	}
	Dictionary result_data;
	result_data["key"] = key;
	result_data["value"] = _encode_variant(ProjectSettings::get_singleton()->get_setting(key));
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_project_set_setting(Dictionary p_params) {
	if (!p_params.has("key") || !_is_string_value(p_params["key"])) {
		return _fail("invalid_params", "key is required and must be a string");
	}
	const StringName key = p_params.get("key", "");
	if (key == StringName() || !p_params.has("value")) {
		return _fail("invalid_params", "key and value are required");
	}
	bool decoded_valid = true;
	const Variant decoded = _decode_variant(p_params["value"], 0, &decoded_valid);
	if (!decoded_valid) {
		return _fail("invalid_value", "Project setting value contains an invalid typed value");
	}
	const Variant save_value = p_params.get("save", true);
	if (save_value.get_type() != Variant::BOOL) {
		return _fail("invalid_params", "save must be a boolean");
	}
	ProjectSettings::get_singleton()->set_setting(key, decoded);
	if (save_value) {
		const Error save_error = ProjectSettings::get_singleton()->save();
		if (save_error != OK) {
			return _fail("save_failed", String(error_names[save_error]));
		}
	}
	Dictionary result_data;
	result_data["key"] = key;
	result_data["value"] = _encode_variant(ProjectSettings::get_singleton()->get_setting(key));
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_assets_scan(Dictionary p_params) {
	EditorFileSystem *filesystem = EditorInterface::get_singleton()->get_resource_filesystem();
	PackedStringArray requested_paths;
	PackedStringArray reimported_paths;
	if (p_params.has("paths")) {
		if (p_params["paths"].get_type() != Variant::ARRAY) {
			return _fail("invalid_params", "paths must be an array of project-local res:// paths");
		}
		const Array paths = p_params["paths"];
		for (const Variant &path : paths) {
			if (!_is_string_value(path)) {
				return _fail("invalid_params", "paths entries must be strings");
			}
			const String resource_path = path;
			if (!_is_safe_resource_path(resource_path, "")) {
				return _fail("invalid_asset_path", "Asset path must stay inside the project", resource_path);
			}
			requested_paths.push_back(resource_path);
			if (ResourceFormatImporter::get_singleton()->get_importer_by_file(resource_path).is_valid()) {
				reimported_paths.push_back(resource_path);
			}
		}
		if (!reimported_paths.is_empty()) {
			filesystem->reimport_files(reimported_paths);
		}
	}
	// Script and text-resource changes are discovered by scanning, while only
	// source formats backed by an importer may be passed to reimport_files().
	filesystem->scan_changes();
	Dictionary result_data;
	result_data["scanning"] = filesystem->is_scanning();
	result_data["requested_paths"] = requested_paths;
	result_data["reimported_paths"] = reimported_paths;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_editor_focus_node(Dictionary p_params) {
	if (!p_params.has("node_path") || !_is_string_value(p_params["node_path"])) {
		return _fail("invalid_params", "node_path is required and must be a string");
	}
	const Variant viewport_value = p_params.get("viewport", 0);
	if (!_is_viewport_index(viewport_value)) {
		return _fail("invalid_params", "viewport must be an integer from 0 to 3");
	}
	Node *node = _find_node(p_params);
	Node3D *node_3d = Object::cast_to<Node3D>(node);
	if (!node_3d) {
		return _fail("not_a_node_3d", "node_path must identify a Node3D", p_params.get("node_path", "."));
	}
	const int viewport_index = viewport_value;
	EditorInterface::get_singleton()->set_main_screen_editor("3D");
	EditorSelection *selection = EditorInterface::get_singleton()->get_selection();
	selection->clear();
	selection->add_node(node_3d);
	EditorInterface::get_singleton()->edit_node(node_3d);
	Node3DEditor::get_singleton()->get_editor_viewport(viewport_index)->focus_selection();
	Dictionary result_data;
	result_data["node_path"] = p_params.get("node_path", ".");
	result_data["viewport"] = viewport_index;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_editor_preview_camera(Dictionary p_params) {
	if (!p_params.has("node_path") || !_is_string_value(p_params["node_path"])) {
		return _fail("invalid_params", "node_path is required and must be a string; use an empty string to clear the preview");
	}
	const Variant viewport_value = p_params.get("viewport", 0);
	if (!_is_viewport_index(viewport_value)) {
		return _fail("invalid_params", "viewport must be an integer from 0 to 3");
	}
	const int viewport_index = viewport_value;
	EditorInterface::get_singleton()->set_main_screen_editor("3D");
	Node3DEditorViewport *viewport = Node3DEditor::get_singleton()->get_editor_viewport(viewport_index);
	const String node_path = p_params.get("node_path", "");
	if (node_path.is_empty()) {
		viewport->stop_camera_preview();
		preview_viewport_mask &= ~(1 << viewport_index);
		Dictionary result_data;
		result_data["cleared"] = true;
		result_data["viewport"] = viewport_index;
		return _ok(result_data);
	}
	Node *node = _find_node(p_params);
	Camera3D *camera = Object::cast_to<Camera3D>(node);
	if (!camera) {
		return _fail("not_a_camera", "node_path must identify a Camera3D", p_params.get("node_path", "."));
	}
	viewport->stop_camera_preview();
	viewport->start_camera_preview(camera);
	preview_viewport_mask |= 1 << viewport_index;
	Dictionary result_data;
	result_data["node_path"] = p_params.get("node_path", ".");
	result_data["viewport"] = viewport_index;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_editor_capture(Dictionary p_params) {
	const Variant viewport_value = p_params.get("viewport", 0);
	if (!_is_viewport_index(viewport_value)) {
		return _fail("invalid_params", "viewport must be an integer from 0 to 3");
	}
	if (p_params.has("path") && !_is_string_value(p_params["path"])) {
		return _fail("invalid_params", "path must be a string");
	}
	const int viewport_index = viewport_value;
	SubViewport *viewport = EditorInterface::get_singleton()->get_editor_viewport_3d(viewport_index);
	if (!viewport || viewport->get_texture().is_null()) {
		return _fail("viewport_unavailable", "The requested 3D editor viewport is unavailable");
	}
	Ref<Image> image = viewport->get_texture()->get_image();
	if (image.is_null() || image->is_empty()) {
		return _fail("capture_failed", "The viewport returned no pixels; use a GPU-backed editor session");
	}
	String path = p_params.get("path", "");
	if (path.is_empty()) {
		path = ProjectSettings::get_singleton()->get_project_data_path().path_join("agent/captures/capture-" + uitos(OS::get_singleton()->get_ticks_msec()) + ".png");
	}
	if (!_is_safe_resource_path(path, "png")) {
		return _fail("invalid_capture_path", "Capture path must be a project-local res:// .png path", path);
	}
	const String absolute_path = ProjectSettings::get_singleton()->globalize_path(path);
	const Error dir_error = DirAccess::make_dir_recursive_absolute(absolute_path.get_base_dir());
	if (dir_error != OK) {
		return _fail("capture_failed", String(error_names[dir_error]));
	}
	const Error save_error = image->save_png(absolute_path);
	if (save_error != OK) {
		return _fail("capture_failed", String(error_names[save_error]));
	}
	Dictionary result_data;
	result_data["path"] = path;
	result_data["absolute_path"] = absolute_path;
	result_data["width"] = image->get_width();
	result_data["height"] = image->get_height();
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_rig_inspect(Dictionary p_params) {
	if (!p_params.has("node_path") || !_is_string_value(p_params["node_path"])) {
		return _fail("invalid_params", "node_path is required and must be a string");
	}
	Node *node = _find_node(p_params);
	Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(node);
	if (!skeleton) {
		return _fail("not_a_skeleton", "node_path must identify a Skeleton3D", p_params.get("node_path", "."));
	}
	Array bones;
	for (int i = 0; i < skeleton->get_bone_count(); i++) {
		Dictionary bone;
		bone["index"] = i;
		bone["name"] = skeleton->get_bone_name(i);
		bone["parent"] = skeleton->get_bone_parent(i);
		bone["enabled"] = skeleton->is_bone_enabled(i);
		bone["rest"] = _encode_variant(skeleton->get_bone_rest(i));
		bone["global_rest"] = _encode_variant(skeleton->get_bone_global_rest(i));
		bone["pose"] = _encode_variant(skeleton->get_bone_pose(i));
		bones.push_back(bone);
	}
	Dictionary result_data;
	result_data["node_path"] = p_params.get("node_path", ".");
	result_data["bone_count"] = bones.size();
	result_data["bones"] = bones;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_game_play(Dictionary p_params) {
	if (p_params.has("scene") && !_is_string_value(p_params["scene"])) {
		return _fail("invalid_params", "scene must be a string");
	}
	const String scene = p_params.get("scene", "");
	if (!scene.is_empty()) {
		if (!_is_safe_resource_path(scene, "tscn")) {
			return _fail("invalid_scene_path", "scene must be a project-local res:// .tscn path", scene);
		}
		EditorInterface::get_singleton()->play_custom_scene(scene);
	} else if (_edited_root()) {
		EditorInterface::get_singleton()->play_current_scene();
	} else {
		EditorInterface::get_singleton()->play_main_scene();
	}
	Dictionary result_data;
	result_data["accepted"] = true;
	result_data["scene"] = scene;
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_game_stop(Dictionary p_params) {
	EditorInterface::get_singleton()->stop_playing_scene();
	return _ok();
}

Dictionary GodotAgentEditorPlugin::_rpc_game_status(Dictionary p_params) {
	Dictionary result_data;
	result_data["playing"] = EditorInterface::get_singleton()->is_playing_scene();
	result_data["scene"] = EditorInterface::get_singleton()->get_playing_scene();
	return _ok(result_data);
}

Dictionary GodotAgentEditorPlugin::_rpc_runtime_status(Dictionary p_params) {
	return (Dictionary)_encode_variant(runtime_debugger->status());
}

Dictionary GodotAgentEditorPlugin::_rpc_runtime_command(Dictionary p_params) {
	if (!p_params.has("method") || !_is_string_value(p_params["method"])) {
		return _fail("invalid_params", "method is required and must be a string");
	}
	const String method = p_params.get("method", "");
	const Variant command_params_value = p_params.get("command_params", Dictionary());
	if (method.strip_edges().is_empty() || command_params_value.get_type() != Variant::DICTIONARY) {
		return _fail("invalid_params", "method and an object-valued command_params are required");
	}
	bool decoded_valid = true;
	const Variant decoded = _decode_variant(command_params_value, 0, &decoded_valid);
	if (!decoded_valid || decoded.get_type() != Variant::DICTIONARY) {
		return _fail("invalid_value", "command_params contains an invalid typed value");
	}
	const Variant session_id_value = p_params.get("session_id", -1);
	if ((session_id_value.get_type() != Variant::INT && session_id_value.get_type() != Variant::FLOAT) || (double)(int64_t)session_id_value != (double)session_id_value || (double)session_id_value < -1.0 || (double)session_id_value > INT32_MAX) {
		return _fail("invalid_params", "session_id must be -1 or a non-negative integer");
	}
	const int session_id = session_id_value;
	return (Dictionary)_encode_variant(runtime_debugger->send_command(method, decoded, session_id));
}

Dictionary GodotAgentEditorPlugin::_rpc_runtime_result(Dictionary p_params) {
	const Variant id_value = p_params.get("id", Variant());
	if ((id_value.get_type() != Variant::INT && id_value.get_type() != Variant::FLOAT) || (double)id_value <= 0.0 || (double)(int64_t)id_value != (double)id_value) {
		return _fail("invalid_params", "id must be a positive integer");
	}
	const int64_t id = id_value;
	const Variant consume_value = p_params.get("consume", false);
	if (consume_value.get_type() != Variant::BOOL) {
		return _fail("invalid_params", "consume must be a boolean");
	}
	const bool consume = consume_value;
	return (Dictionary)_encode_variant(runtime_debugger->get_result(id, consume));
}
