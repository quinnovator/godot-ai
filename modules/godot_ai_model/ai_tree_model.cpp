/**************************************************************************/
/*  ai_tree_model.cpp                                                     */
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

#include "ai_tree_model.h"

#include "core/io/file_access.h"
#include "core/io/marshalls.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/local_vector.h"

#include <limits>

namespace {

constexpr uint32_t XGB1_MAGIC = 0x31424758;
constexpr uint64_t XGB1_HEADER_BYTES = 5 * sizeof(uint32_t);
constexpr uint64_t MAX_MODEL_BYTES = 256 * 1024 * 1024;
constexpr uint32_t MAX_CLASSES = 65536;
constexpr uint32_t MAX_FEATURES = 65536;
constexpr uint32_t MAX_TREES = 16 * 1024 * 1024;
constexpr uint32_t MAX_NODES = 16 * 1024 * 1024;

class ByteReader {
	const uint8_t *data = nullptr;
	uint64_t size = 0;
	uint64_t offset = 0;

public:
	ByteReader(const uint8_t *p_data, uint64_t p_size) : data(p_data), size(p_size) {}

	uint64_t remaining() const {
		return size - offset;
	}

	bool read_u8(uint8_t &r_value) {
		if (remaining() < sizeof(uint8_t)) {
			return false;
		}
		r_value = data[offset++];
		return true;
	}

	bool read_u16(uint16_t &r_value) {
		if (remaining() < sizeof(uint16_t)) {
			return false;
		}
		r_value = decode_uint16(data + offset);
		offset += sizeof(uint16_t);
		return true;
	}

	bool read_u32(uint32_t &r_value) {
		if (remaining() < sizeof(uint32_t)) {
			return false;
		}
		r_value = decode_uint32(data + offset);
		offset += sizeof(uint32_t);
		return true;
	}

	bool read_i32(int32_t &r_value) {
		uint32_t value = 0;
		if (!read_u32(value)) {
			return false;
		}
		r_value = static_cast<int32_t>(value);
		return true;
	}

	bool read_float(float &r_value) {
		if (remaining() < sizeof(float)) {
			return false;
		}
		r_value = decode_float(data + offset);
		offset += sizeof(float);
		return true;
	}
};

bool checked_add(uint64_t p_a, uint64_t p_b, uint64_t &r_result) {
	if (p_b > std::numeric_limits<uint64_t>::max() - p_a) {
		return false;
	}
	r_result = p_a + p_b;
	return true;
}

bool checked_multiply(uint64_t p_a, uint64_t p_b, uint64_t &r_result) {
	if (p_a != 0 && p_b > std::numeric_limits<uint64_t>::max() / p_a) {
		return false;
	}
	r_result = p_a * p_b;
	return true;
}

} // namespace

void AITreeModel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_model", "path"), &AITreeModel::load_model);
	ClassDB::bind_method(D_METHOD("load_from_buffer", "data"), &AITreeModel::load_from_buffer);
	ClassDB::bind_method(D_METHOD("clear"), &AITreeModel::clear);
	ClassDB::bind_method(D_METHOD("predict", "features"), &AITreeModel::predict);
	ClassDB::bind_method(D_METHOD("is_loaded"), &AITreeModel::is_loaded);
	ClassDB::bind_method(D_METHOD("get_num_classes"), &AITreeModel::get_num_classes);
	ClassDB::bind_method(D_METHOD("get_num_features"), &AITreeModel::get_num_features);
	ClassDB::bind_method(D_METHOD("get_num_trees"), &AITreeModel::get_num_trees);
	ClassDB::bind_method(D_METHOD("get_last_error"), &AITreeModel::get_last_error);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "loaded", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "is_loaded");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "num_classes", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_num_classes");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "num_features", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_num_features");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "num_trees", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_num_trees");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "last_error", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY), "", "get_last_error");
}

Error AITreeModel::_set_load_error(const String &p_message) {
	model = ModelData();
	loaded = false;
	last_error_message = p_message;
	return ERR_FILE_CORRUPT;
}

void AITreeModel::clear() {
	model = ModelData();
	loaded = false;
	last_error_message.clear();
}

Error AITreeModel::load_model(const String &p_path) {
	clear();

	Error open_error = OK;
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ, &open_error);
	if (file.is_null()) {
		last_error_message = vformat("Unable to open XGB1 model '%s': %s.", p_path, error_names[open_error]);
		return open_error;
	}

	const uint64_t length = file->get_length();
	if (length > MAX_MODEL_BYTES) {
		last_error_message = vformat("XGB1 model is too large (%d bytes; limit is %d bytes).", length, MAX_MODEL_BYTES);
		return ERR_OUT_OF_MEMORY;
	}

	PackedByteArray data;
	data.resize(length);
	if (length > 0 && file->get_buffer(data.ptrw(), length) != length) {
		last_error_message = vformat("Unable to read the complete XGB1 model '%s'.", p_path);
		return ERR_FILE_CANT_READ;
	}

	return load_from_buffer(data);
}

Error AITreeModel::load_from_buffer(const PackedByteArray &p_data) {
	clear();
	if (p_data.size() > static_cast<int64_t>(MAX_MODEL_BYTES)) {
		last_error_message = vformat("XGB1 model is too large (%d bytes; limit is %d bytes).", p_data.size(), MAX_MODEL_BYTES);
		return ERR_OUT_OF_MEMORY;
	}
	return _load_buffer(p_data.ptr(), p_data.size());
}

Error AITreeModel::_load_buffer(const uint8_t *p_data, uint64_t p_size) {
	if (p_size < XGB1_HEADER_BYTES) {
		return _set_load_error("XGB1 data is shorter than its 20-byte header.");
	}

	ByteReader reader(p_data, p_size);
	uint32_t magic = 0;
	uint32_t objective_raw = 0;
	uint32_t tree_count = 0;
	uint32_t class_count = 0;
	uint32_t feature_count = 0;
	if (!reader.read_u32(magic) || !reader.read_u32(objective_raw) || !reader.read_u32(tree_count) || !reader.read_u32(class_count) || !reader.read_u32(feature_count)) {
		return _set_load_error("XGB1 header is truncated.");
	}
	if (magic != XGB1_MAGIC) {
		return _set_load_error(vformat("Invalid XGB1 magic 0x%08x.", magic));
	}
	if (objective_raw > OBJECTIVE_SOFTMAX) {
		return _set_load_error(vformat("Unsupported XGB1 objective %d.", objective_raw));
	}
	if (class_count == 0 || class_count > MAX_CLASSES) {
		return _set_load_error(vformat("Invalid XGB1 class count %d.", class_count));
	}
	if (feature_count > MAX_FEATURES) {
		return _set_load_error(vformat("Invalid XGB1 feature count %d.", feature_count));
	}
	if (tree_count > MAX_TREES) {
		return _set_load_error(vformat("Invalid XGB1 tree count %d.", tree_count));
	}

	uint64_t base_score_bytes = 0;
	uint64_t tree_metadata_bytes = 0;
	uint64_t fixed_bytes = 0;
	if (!checked_multiply(class_count, sizeof(float), base_score_bytes) ||
			!checked_multiply(tree_count, sizeof(uint32_t) * 2, tree_metadata_bytes) ||
			!checked_add(base_score_bytes, tree_metadata_bytes, fixed_bytes) || fixed_bytes > reader.remaining()) {
		return _set_load_error("XGB1 metadata arrays are truncated or overflow their declared sizes.");
	}

	ModelData parsed;
	parsed.objective = static_cast<Objective>(objective_raw);
	parsed.class_count = class_count;
	parsed.feature_count = feature_count;
	parsed.base_scores.resize(class_count);
	parsed.tree_classes.resize(tree_count);
	parsed.tree_node_counts.resize(tree_count);
	parsed.tree_offsets.resize(tree_count);

	for (uint32_t i = 0; i < class_count; i++) {
		float score = 0.0f;
		if (!reader.read_float(score)) {
			return _set_load_error("XGB1 base score array is truncated.");
		}
		if (!Math::is_finite(score)) {
			return _set_load_error(vformat("XGB1 base score %d is not finite.", i));
		}
		parsed.base_scores.write[i] = score;
	}

	for (uint32_t i = 0; i < tree_count; i++) {
		uint32_t tree_class = 0;
		if (!reader.read_u32(tree_class)) {
			return _set_load_error("XGB1 tree-class array is truncated.");
		}
		if (tree_class >= class_count) {
			return _set_load_error(vformat("XGB1 tree %d targets class %d, but the model has %d classes.", i, tree_class, class_count));
		}
		parsed.tree_classes.write[i] = tree_class;
	}

	uint64_t total_nodes = 0;
	for (uint32_t i = 0; i < tree_count; i++) {
		uint32_t node_count = 0;
		if (!reader.read_u32(node_count)) {
			return _set_load_error("XGB1 node-count array is truncated.");
		}
		if (node_count == 0) {
			return _set_load_error(vformat("XGB1 tree %d has no root node.", i));
		}
		parsed.tree_offsets.write[i] = static_cast<uint32_t>(total_nodes);
		parsed.tree_node_counts.write[i] = node_count;
		if (!checked_add(total_nodes, node_count, total_nodes) || total_nodes > MAX_NODES) {
			return _set_load_error(vformat("XGB1 total node count exceeds the %d-node limit.", MAX_NODES));
		}
	}

	uint64_t node_bytes = 0;
	if (!checked_multiply(total_nodes, sizeof(int32_t) * 2 + sizeof(float) + sizeof(uint16_t) + sizeof(uint8_t), node_bytes) || node_bytes != reader.remaining()) {
		return _set_load_error(vformat("XGB1 node arrays have the wrong size (expected %d bytes, found %d bytes).", node_bytes, reader.remaining()));
	}

	parsed.left_children.resize(total_nodes);
	parsed.right_children.resize(total_nodes);
	parsed.values.resize(total_nodes);
	parsed.feature_indices.resize(total_nodes);
	parsed.default_left.resize(total_nodes);

	for (uint64_t i = 0; i < total_nodes; i++) {
		if (!reader.read_i32(parsed.left_children.write[i])) {
			return _set_load_error("XGB1 left-child array is truncated.");
		}
	}
	for (uint64_t i = 0; i < total_nodes; i++) {
		if (!reader.read_i32(parsed.right_children.write[i])) {
			return _set_load_error("XGB1 right-child array is truncated.");
		}
	}
	for (uint64_t i = 0; i < total_nodes; i++) {
		if (!reader.read_float(parsed.values.write[i])) {
			return _set_load_error("XGB1 value array is truncated.");
		}
		if (!Math::is_finite(parsed.values[i])) {
			return _set_load_error(vformat("XGB1 node %d has a non-finite threshold or leaf value.", i));
		}
	}
	for (uint64_t i = 0; i < total_nodes; i++) {
		if (!reader.read_u16(parsed.feature_indices.write[i])) {
			return _set_load_error("XGB1 feature-index array is truncated.");
		}
	}
	for (uint64_t i = 0; i < total_nodes; i++) {
		if (!reader.read_u8(parsed.default_left.write[i])) {
			return _set_load_error("XGB1 default-direction array is truncated.");
		}
		if (parsed.default_left[i] > 1) {
			return _set_load_error(vformat("XGB1 node %d has invalid default-left value %d.", i, parsed.default_left[i]));
		}
	}

	for (uint32_t tree = 0; tree < tree_count; tree++) {
		String validation_error;
		if (!_validate_tree(parsed, tree, validation_error)) {
			return _set_load_error(validation_error);
		}
	}

	model = parsed;
	loaded = true;
	last_error_message.clear();
	return OK;
}

bool AITreeModel::_validate_tree(const ModelData &p_model, uint32_t p_tree, String &r_error) const {
	const uint32_t base = p_model.tree_offsets[p_tree];
	const uint32_t count = p_model.tree_node_counts[p_tree];
	Vector<uint32_t> parent_counts;
	parent_counts.resize(count);
	parent_counts.fill(0);

	for (uint32_t local = 0; local < count; local++) {
		const uint32_t global = base + local;
		const int32_t left = p_model.left_children[global];
		const int32_t right = p_model.right_children[global];
		if (left == -1) {
			if (right != -1) {
				r_error = vformat("XGB1 tree %d node %d is a leaf with a non-leaf right child.", p_tree, local);
				return false;
			}
			continue;
		}
		if (left < 0 || right < 0 || static_cast<uint32_t>(left) >= count || static_cast<uint32_t>(right) >= count) {
			r_error = vformat("XGB1 tree %d node %d has an out-of-range child.", p_tree, local);
			return false;
		}
		if (p_model.feature_indices[global] >= p_model.feature_count) {
			r_error = vformat("XGB1 tree %d node %d references feature %d, but the model has %d features.", p_tree, local, p_model.feature_indices[global], p_model.feature_count);
			return false;
		}
		parent_counts.write[left]++;
		parent_counts.write[right]++;
	}

	if (parent_counts[0] != 0) {
		r_error = vformat("XGB1 tree %d root has a parent.", p_tree);
		return false;
	}
	for (uint32_t local = 1; local < count; local++) {
		if (parent_counts[local] != 1) {
			r_error = vformat("XGB1 tree %d node %d has %d parents; exactly one is required.", p_tree, local, parent_counts[local]);
			return false;
		}
	}

	Vector<uint8_t> visited;
	visited.resize(count);
	visited.fill(0);
	LocalVector<uint32_t> stack;
	stack.push_back(0);
	uint32_t visited_count = 0;
	while (!stack.is_empty()) {
		const uint32_t local = stack[stack.size() - 1];
		stack.resize(stack.size() - 1);
		if (visited[local]) {
			r_error = vformat("XGB1 tree %d contains a cycle or shared child at node %d.", p_tree, local);
			return false;
		}
		visited.write[local] = 1;
		visited_count++;
		const int32_t left = p_model.left_children[base + local];
		if (left != -1) {
			stack.push_back(static_cast<uint32_t>(p_model.right_children[base + local]));
			stack.push_back(static_cast<uint32_t>(left));
		}
	}
	if (visited_count != count) {
		r_error = vformat("XGB1 tree %d has %d unreachable nodes.", p_tree, count - visited_count);
		return false;
	}
	return true;
}

PackedFloat64Array AITreeModel::predict(const PackedFloat32Array &p_features) const {
	PackedFloat64Array output;
	if (!loaded) {
		last_error_message = "No XGB1 model is loaded.";
		return output;
	}
	if (p_features.size() != model.feature_count) {
		last_error_message = vformat("Expected %d features, received %d.", model.feature_count, p_features.size());
		return output;
	}

	output.resize(model.class_count);
	double *margins = output.ptrw();
	for (uint32_t class_index = 0; class_index < model.class_count; class_index++) {
		margins[class_index] = static_cast<double>(model.base_scores[class_index]);
	}

	const float *features = p_features.ptr();
	for (uint32_t tree = 0; tree < model.tree_classes.size(); tree++) {
		const uint32_t base = model.tree_offsets[tree];
		uint32_t local = 0;
		while (model.left_children[base + local] != -1) {
			const uint32_t global = base + local;
			const float feature = features[model.feature_indices[global]];
			if (Math::is_nan(feature)) {
				local = static_cast<uint32_t>(model.default_left[global] ? model.left_children[global] : model.right_children[global]);
			} else {
				local = static_cast<uint32_t>(feature < model.values[global] ? model.left_children[global] : model.right_children[global]);
			}
		}
		margins[model.tree_classes[tree]] += static_cast<double>(model.values[base + local]);
	}

	if (model.objective == OBJECTIVE_SOFTMAX) {
		double maximum = -std::numeric_limits<double>::infinity();
		for (uint32_t class_index = 0; class_index < model.class_count; class_index++) {
			maximum = MAX(maximum, margins[class_index]);
		}
		double sum = 0.0;
		for (uint32_t class_index = 0; class_index < model.class_count; class_index++) {
			margins[class_index] = Math::exp(margins[class_index] - maximum);
			sum += margins[class_index];
		}
		for (uint32_t class_index = 0; class_index < model.class_count; class_index++) {
			margins[class_index] /= sum;
		}
	}

	last_error_message.clear();
	return output;
}

bool AITreeModel::is_loaded() const {
	return loaded;
}

int64_t AITreeModel::get_num_classes() const {
	return loaded ? model.class_count : 0;
}

int64_t AITreeModel::get_num_features() const {
	return loaded ? model.feature_count : 0;
}

int64_t AITreeModel::get_num_trees() const {
	return loaded ? model.tree_classes.size() : 0;
}

String AITreeModel::get_last_error() const {
	return last_error_message;
}
