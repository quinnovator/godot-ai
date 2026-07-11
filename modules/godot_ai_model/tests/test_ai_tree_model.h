/**************************************************************************/
/*  test_ai_tree_model.h                                                  */
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

#include "../ai_tree_model.h"

#include "core/io/marshalls.h"
#include "tests/test_macros.h"

namespace TestAITreeModel {

void append_u8(PackedByteArray &r_data, uint8_t p_value) {
	r_data.push_back(p_value);
}

void append_u16(PackedByteArray &r_data, uint16_t p_value) {
	const int64_t offset = r_data.size();
	r_data.resize(offset + sizeof(uint16_t));
	encode_uint16(p_value, r_data.ptrw() + offset);
}

void append_u32(PackedByteArray &r_data, uint32_t p_value) {
	const int64_t offset = r_data.size();
	r_data.resize(offset + sizeof(uint32_t));
	encode_uint32(p_value, r_data.ptrw() + offset);
}

void append_i32(PackedByteArray &r_data, int32_t p_value) {
	append_u32(r_data, static_cast<uint32_t>(p_value));
}

void append_float(PackedByteArray &r_data, float p_value) {
	const int64_t offset = r_data.size();
	r_data.resize(offset + sizeof(float));
	encode_float(p_value, r_data.ptrw() + offset);
}

PackedByteArray make_regression_fixture() {
	PackedByteArray data;
	append_u32(data, 0x31424758); // XGB1.
	append_u32(data, 0); // Regression.
	append_u32(data, 2); // Trees.
	append_u32(data, 1); // Classes.
	append_u32(data, 2); // Features.
	append_float(data, 0.25f); // Base score.
	append_u32(data, 0);
	append_u32(data, 0); // Tree classes.
	append_u32(data, 3);
	append_u32(data, 1); // Node counts.

	// Tree zero splits feature 0 at 1.5. Tree one is a constant leaf.
	for (int32_t value : { 1, -1, -1, -1 }) {
		append_i32(data, value);
	}
	for (int32_t value : { 2, -1, -1, -1 }) {
		append_i32(data, value);
	}
	for (float value : { 1.5f, -0.5f, 2.0f, 0.25f }) {
		append_float(data, value);
	}
	for (uint16_t value : { 0, 0, 0, 0 }) {
		append_u16(data, value);
	}
	for (uint8_t value : { 1, 0, 0, 0 }) {
		append_u8(data, value);
	}
	return data;
}

PackedByteArray make_softmax_fixture() {
	PackedByteArray data;
	append_u32(data, 0x31424758); // XGB1.
	append_u32(data, 1); // Softmax.
	append_u32(data, 2); // Trees.
	append_u32(data, 2); // Classes.
	append_u32(data, 1); // Features.
	append_float(data, 0.1f);
	append_float(data, -0.2f); // Base scores.
	append_u32(data, 0);
	append_u32(data, 1); // Tree classes.
	append_u32(data, 1);
	append_u32(data, 1); // Node counts.
	append_i32(data, -1);
	append_i32(data, -1); // Left.
	append_i32(data, -1);
	append_i32(data, -1); // Right.
	append_float(data, 0.3f);
	append_float(data, 0.9f); // Leaf values.
	append_u16(data, 0);
	append_u16(data, 0);
	append_u8(data, 0);
	append_u8(data, 0);
	return data;
}

TEST_CASE("[AITreeModel] Regression, strict split, and missing direction") {
	Ref<AITreeModel> model;
	model.instantiate();
	CHECK(model->load_from_buffer(make_regression_fixture()) == OK);
	CHECK(model->is_loaded());
	CHECK(model->get_num_classes() == 1);
	CHECK(model->get_num_features() == 2);
	CHECK(model->get_num_trees() == 2);

	PackedFloat32Array features;
	features.push_back(1.0f);
	features.push_back(100.0f);
	PackedFloat64Array prediction = model->predict(features);
	REQUIRE(prediction.size() == 1);
	CHECK(prediction[0] == doctest::Approx(0.0));

	features.set(0, 1.5f); // Strict less-than goes right at equality.
	prediction = model->predict(features);
	CHECK(prediction[0] == doctest::Approx(2.5));

	features.set(0, Math::NaN);
	prediction = model->predict(features);
	CHECK(prediction[0] == doctest::Approx(0.0));
	CHECK(model->get_last_error().is_empty());
}

TEST_CASE("[AITreeModel] Stable multi-class softmax") {
	Ref<AITreeModel> model;
	model.instantiate();
	CHECK(model->load_from_buffer(make_softmax_fixture()) == OK);

	PackedFloat32Array features;
	features.push_back(0.0f);
	const PackedFloat64Array prediction = model->predict(features);
	REQUIRE(prediction.size() == 2);
	CHECK(prediction[0] == doctest::Approx(0.4255574832));
	CHECK(prediction[1] == doctest::Approx(0.5744425168));
	CHECK(prediction[0] + prediction[1] == doctest::Approx(1.0));
}

TEST_CASE("[AITreeModel] Rejects corrupt input and wrong feature count") {
	Ref<AITreeModel> model;
	model.instantiate();
	CHECK(model->load_from_buffer(make_regression_fixture()) == OK);

	PackedByteArray corrupt = make_regression_fixture();
	corrupt.set(0, 0);
	CHECK(model->load_from_buffer(corrupt) == ERR_FILE_CORRUPT);
	CHECK_FALSE(model->is_loaded());
	CHECK(model->get_last_error().contains("magic"));

	CHECK(model->load_from_buffer(make_regression_fixture()) == OK);
	PackedFloat32Array too_short;
	too_short.push_back(0.0f);
	CHECK(model->predict(too_short).is_empty());
	CHECK(model->get_last_error().contains("Expected 2 features"));
}

TEST_CASE("[AITreeModel] Rejects invalid tree structure and trailing data") {
	Ref<AITreeModel> model;
	model.instantiate();

	PackedByteArray invalid_feature = make_regression_fixture();
	// Header (20), base score (4), tree classes (8), node counts (8),
	// left/right/value arrays (48): the root feature index starts at byte 88.
	invalid_feature.set(88, 2);
	CHECK(model->load_from_buffer(invalid_feature) == ERR_FILE_CORRUPT);
	CHECK(model->get_last_error().contains("references feature 2"));

	PackedByteArray cycle = make_regression_fixture();
	// The first left-child entry starts at byte 40. Pointing it at the root
	// gives the root a parent and would otherwise make prediction loop forever.
	cycle.set(40, 0);
	cycle.set(41, 0);
	cycle.set(42, 0);
	cycle.set(43, 0);
	CHECK(model->load_from_buffer(cycle) == ERR_FILE_CORRUPT);
	CHECK(model->get_last_error().contains("root has a parent"));

	PackedByteArray trailing_data = make_regression_fixture();
	trailing_data.push_back(0);
	CHECK(model->load_from_buffer(trailing_data) == ERR_FILE_CORRUPT);
	CHECK(model->get_last_error().contains("wrong size"));
}

} // namespace TestAITreeModel
