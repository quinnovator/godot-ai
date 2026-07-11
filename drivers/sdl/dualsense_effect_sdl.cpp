/**************************************************************************/
/*  dualsense_effect_sdl.cpp                                              */
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

#include "dualsense_effect_sdl.h"

#include <cstring>

namespace {

constexpr int ENABLE_BITS_1_OFFSET = 0;
constexpr int RIGHT_TRIGGER_OFFSET = 10;
constexpr int LEFT_TRIGGER_OFFSET = 21;
constexpr int TRIGGER_EFFECT_SIZE = 11;

constexpr uint8_t ENABLE_RIGHT_TRIGGER = 0x04;
constexpr uint8_t ENABLE_LEFT_TRIGGER = 0x08;

// Official DualSense firmware effect commands. The public Godot API exposes
// semantic enums and validated parameters, never these protocol values.
constexpr uint8_t EFFECT_OFF = 0x05;
constexpr uint8_t EFFECT_FEEDBACK = 0x21;
constexpr uint8_t EFFECT_WEAPON = 0x25;
constexpr uint8_t EFFECT_VIBRATION = 0x26;

void encode_off(uint8_t *r_effect) {
	memset(r_effect, 0, TRIGGER_EFFECT_SIZE);
	r_effect[0] = EFFECT_OFF;
}

} // namespace

bool DualSenseEffectSDL::build_payload(Payload &r_payload, Trigger p_trigger, Effect p_effect, int p_start_position, int p_end_position, int p_strength, int p_frequency_hz) {
	memset(r_payload.data, 0, PAYLOAD_SIZE);

	uint8_t effect[TRIGGER_EFFECT_SIZE] = {};
	if (!_encode_effect(effect, p_effect, p_start_position, p_end_position, p_strength, p_frequency_hz)) {
		return false;
	}

	switch (p_trigger) {
		case Trigger::LEFT:
			r_payload.data[ENABLE_BITS_1_OFFSET] = ENABLE_LEFT_TRIGGER;
			memcpy(&r_payload.data[LEFT_TRIGGER_OFFSET], effect, TRIGGER_EFFECT_SIZE);
			break;
		case Trigger::RIGHT:
			r_payload.data[ENABLE_BITS_1_OFFSET] = ENABLE_RIGHT_TRIGGER;
			memcpy(&r_payload.data[RIGHT_TRIGGER_OFFSET], effect, TRIGGER_EFFECT_SIZE);
			break;
		case Trigger::BOTH:
			r_payload.data[ENABLE_BITS_1_OFFSET] = ENABLE_LEFT_TRIGGER | ENABLE_RIGHT_TRIGGER;
			memcpy(&r_payload.data[LEFT_TRIGGER_OFFSET], effect, TRIGGER_EFFECT_SIZE);
			memcpy(&r_payload.data[RIGHT_TRIGGER_OFFSET], effect, TRIGGER_EFFECT_SIZE);
			break;
		default:
			memset(r_payload.data, 0, PAYLOAD_SIZE);
			return false;
	}

	return true;
}

bool DualSenseEffectSDL::_encode_effect(uint8_t *r_effect, Effect p_effect, int p_start_position, int p_end_position, int p_strength, int p_frequency_hz) {
	memset(r_effect, 0, TRIGGER_EFFECT_SIZE);

	switch (p_effect) {
		case Effect::OFF:
			encode_off(r_effect);
			return true;

		case Effect::FEEDBACK:
		case Effect::VIBRATION: {
			if (p_start_position < 0 || p_start_position > 9 || p_strength < 0 || p_strength > 8 || p_frequency_hz < 0 || p_frequency_hz > 255) {
				return false;
			}
			if (p_strength == 0 || (p_effect == Effect::VIBRATION && p_frequency_hz == 0)) {
				encode_off(r_effect);
				return true;
			}

			const uint32_t zone_value = static_cast<uint32_t>((p_strength - 1) & 0x07);
			uint16_t active_zones = 0;
			uint32_t strength_zones = 0;
			for (int zone = p_start_position; zone < 10; zone++) {
				active_zones |= static_cast<uint16_t>(1U << zone);
				strength_zones |= zone_value << (zone * 3);
			}

			r_effect[0] = p_effect == Effect::FEEDBACK ? EFFECT_FEEDBACK : EFFECT_VIBRATION;
			r_effect[1] = static_cast<uint8_t>(active_zones);
			r_effect[2] = static_cast<uint8_t>(active_zones >> 8);
			r_effect[3] = static_cast<uint8_t>(strength_zones);
			r_effect[4] = static_cast<uint8_t>(strength_zones >> 8);
			r_effect[5] = static_cast<uint8_t>(strength_zones >> 16);
			r_effect[6] = static_cast<uint8_t>(strength_zones >> 24);
			if (p_effect == Effect::VIBRATION) {
				r_effect[9] = static_cast<uint8_t>(p_frequency_hz);
			}
			return true;
		}

		case Effect::WEAPON: {
			if (p_start_position < 2 || p_start_position > 7 || p_end_position <= p_start_position || p_end_position > 8 || p_strength < 0 || p_strength > 8) {
				return false;
			}
			if (p_strength == 0) {
				encode_off(r_effect);
				return true;
			}

			const uint16_t active_zones = static_cast<uint16_t>((1U << p_start_position) | (1U << p_end_position));
			r_effect[0] = EFFECT_WEAPON;
			r_effect[1] = static_cast<uint8_t>(active_zones);
			r_effect[2] = static_cast<uint8_t>(active_zones >> 8);
			r_effect[3] = static_cast<uint8_t>(p_strength - 1);
			return true;
		}

		default:
			return false;
	}
}

static_assert(sizeof(DualSenseEffectSDL::Payload) == DualSenseEffectSDL::PAYLOAD_SIZE, "DualSense common effect payload must remain 47 bytes.");
