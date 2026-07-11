/**************************************************************************/
/*  test_dualsense_effect_sdl.cpp                                        */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_dualsense_effect_sdl)

#include "drivers/sdl/dualsense_effect_sdl.h"

namespace TestDualSenseEffectSDL {

TEST_CASE("[SDL][DualSense] Official trigger effects encode into the SDL-owned common payload") {
	DualSenseEffectSDL::Payload payload;

	SUBCASE("Feedback applies only to the requested trigger") {
		CHECK(DualSenseEffectSDL::build_payload(
				payload,
				DualSenseEffectSDL::Trigger::LEFT,
				DualSenseEffectSDL::Effect::FEEDBACK,
				4,
				0,
				6,
				0));
		CHECK(payload.data[0] == 0x08);
		const uint8_t expected[] = { 0x21, 0xf0, 0x03, 0x00, 0xd0, 0xb6, 0x2d, 0x00, 0x00, 0x00, 0x00 };
		for (int index = 0; index < 11; index++) {
			CHECK(payload.data[21 + index] == expected[index]);
			CHECK(payload.data[10 + index] == 0x00);
		}
	}

	SUBCASE("Vibration matches the documented Steamworks example parameters") {
		CHECK(DualSenseEffectSDL::build_payload(
				payload,
				DualSenseEffectSDL::Trigger::RIGHT,
				DualSenseEffectSDL::Effect::VIBRATION,
				5,
				0,
				5,
				8));
		CHECK(payload.data[0] == 0x04);
		const uint8_t expected[] = { 0x26, 0xe0, 0x03, 0x00, 0x00, 0x92, 0x24, 0x00, 0x00, 0x08, 0x00 };
		for (int index = 0; index < 11; index++) {
			CHECK(payload.data[10 + index] == expected[index]);
		}
	}

	SUBCASE("Weapon and off effects remain bounded protocol commands") {
		CHECK(DualSenseEffectSDL::build_payload(
				payload,
				DualSenseEffectSDL::Trigger::RIGHT,
				DualSenseEffectSDL::Effect::WEAPON,
				2,
				7,
				8,
				0));
		const uint8_t expected_weapon[] = { 0x25, 0x84, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
		for (int index = 0; index < 11; index++) {
			CHECK(payload.data[10 + index] == expected_weapon[index]);
		}

		CHECK(DualSenseEffectSDL::build_payload(
				payload,
				DualSenseEffectSDL::Trigger::BOTH,
				DualSenseEffectSDL::Effect::OFF,
				0,
				0,
				0,
				0));
		CHECK(payload.data[0] == 0x0c);
		CHECK(payload.data[10] == 0x05);
		CHECK(payload.data[21] == 0x05);
	}
}

TEST_CASE("[SDL][DualSense] Invalid trigger effects fail closed") {
	DualSenseEffectSDL::Payload payload;
	for (uint8_t &byte : payload.data) {
		byte = 0xff;
	}

	CHECK_FALSE(DualSenseEffectSDL::build_payload(
			payload,
			DualSenseEffectSDL::Trigger::LEFT,
			DualSenseEffectSDL::Effect::FEEDBACK,
			10,
			0,
			4,
			0));
	for (uint8_t byte : payload.data) {
		CHECK(byte == 0x00);
	}

	CHECK_FALSE(DualSenseEffectSDL::build_payload(
			payload,
			DualSenseEffectSDL::Trigger::RIGHT,
			DualSenseEffectSDL::Effect::WEAPON,
			7,
			7,
			8,
			0));
	CHECK_FALSE(DualSenseEffectSDL::build_payload(
			payload,
			DualSenseEffectSDL::Trigger::RIGHT,
			DualSenseEffectSDL::Effect::VIBRATION,
			2,
			0,
			9,
			80));
}

} // namespace TestDualSenseEffectSDL
