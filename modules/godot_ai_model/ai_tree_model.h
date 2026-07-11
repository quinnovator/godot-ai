/**************************************************************************/
/*  ai_tree_model.h                                                       */
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

#include "core/object/ref_counted.h"
#include "core/templates/vector.h"
#include "core/variant/variant.h"

class AITreeModel : public RefCounted {
	GDCLASS(AITreeModel, RefCounted);

	enum Objective : uint32_t {
		OBJECTIVE_REGRESSION = 0,
		OBJECTIVE_SOFTMAX = 1,
	};

	struct ModelData {
		Objective objective = OBJECTIVE_REGRESSION;
		uint32_t class_count = 0;
		uint32_t feature_count = 0;
		Vector<float> base_scores;
		Vector<uint32_t> tree_classes;
		Vector<uint32_t> tree_offsets;
		Vector<uint32_t> tree_node_counts;
		Vector<int32_t> left_children;
		Vector<int32_t> right_children;
		Vector<float> values;
		Vector<uint16_t> feature_indices;
		Vector<uint8_t> default_left;
	};

	ModelData model;
	bool loaded = false;
	mutable String last_error_message;

	Error _load_buffer(const uint8_t *p_data, uint64_t p_size);
	Error _set_load_error(const String &p_message);
	bool _validate_tree(const ModelData &p_model, uint32_t p_tree, String &r_error) const;

protected:
	static void _bind_methods();

public:
	Error load_model(const String &p_path);
	Error load_from_buffer(const PackedByteArray &p_data);
	void clear();

	PackedFloat64Array predict(const PackedFloat32Array &p_features) const;

	bool is_loaded() const;
	int64_t get_num_classes() const;
	int64_t get_num_features() const;
	int64_t get_num_trees() const;
	String get_last_error() const;
};
