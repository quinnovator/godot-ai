/**************************************************************************/
/*  dualsense_effect_sdl.h                                                */
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

#include "core/typedefs.h"

// Builds the common 47-byte DualSense output state accepted by SDL's PS5
// driver's SendEffect callback. SDL remains responsible for transport report
// IDs, Bluetooth framing, CRCs, enhanced-mode negotiation, and device I/O.
// Raw output bytes are deliberately kept private to the SDL driver boundary.
class DualSenseEffectSDL {
public:
	enum class Trigger {
		LEFT,
		RIGHT,
		BOTH,
	};

	enum class Effect {
		OFF,
		FEEDBACK,
		WEAPON,
		VIBRATION,
	};

	static constexpr int PAYLOAD_SIZE = 47;

	struct Payload {
		uint8_t data[PAYLOAD_SIZE] = {};
	};

	// All positions use the ten official trigger control zones (0 through 9),
	// strengths/amplitudes use 0 through 8, and frequency uses hertz (0 through
	// 255). Zero strength, amplitude, or frequency safely resolves to OFF.
	static bool build_payload(Payload &r_payload, Trigger p_trigger, Effect p_effect, int p_start_position, int p_end_position, int p_strength, int p_frequency_hz);

private:
	static bool _encode_effect(uint8_t *r_effect, Effect p_effect, int p_start_position, int p_end_position, int p_strength, int p_frequency_hz);
};
