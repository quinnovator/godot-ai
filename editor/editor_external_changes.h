/**************************************************************************/
/*  editor_external_changes.h                                             */
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

#include "core/config/project_settings.h"
#include "core/io/config_file.h"

enum class EditorExternalChangeAction {
	NONE,
	PROMPT,
	AUTO_RELOAD,
};

class EditorExternalChanges {
public:
	static bool is_project_settings_config_safe(const Ref<ConfigFile> &p_config) {
		if (p_config.is_null()) {
			return false;
		}

		// ConfigFile proves that the text is syntactically valid, but
		// ProjectSettings::setup() also rejects projects written by a newer
		// config format. Check that constraint before setup() is allowed to
		// mutate the live singleton.
		const Variant config_version = p_config->get_value(String(), "config_version", 0);
		if (config_version.get_type() != Variant::INT) {
			return false;
		}
		const int64_t version = config_version;
		return version >= 0 && version <= ProjectSettings::CONFIG_VERSION;
	}

	static constexpr EditorExternalChangeAction decide_action(bool p_changes_detected, bool p_auto_reload_enabled, bool p_has_unsaved_conflict, bool p_disk_data_valid) {
		if (!p_changes_detected) {
			return EditorExternalChangeAction::NONE;
		}
		if (p_auto_reload_enabled && !p_has_unsaved_conflict && p_disk_data_valid) {
			return EditorExternalChangeAction::AUTO_RELOAD;
		}
		return EditorExternalChangeAction::PROMPT;
	}
};
