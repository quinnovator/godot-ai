/**************************************************************************/
/*  test_editor_external_changes.cpp                                      */
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

#include "editor/editor_external_changes.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_editor_external_changes)

TEST_CASE("[Editor] External changes only auto-reload when safe") {
	CHECK(EditorExternalChanges::decide_action(false, true, false, true) == EditorExternalChangeAction::NONE);
	CHECK(EditorExternalChanges::decide_action(true, false, false, true) == EditorExternalChangeAction::PROMPT);
	CHECK(EditorExternalChanges::decide_action(true, true, true, true) == EditorExternalChangeAction::PROMPT);
	CHECK(EditorExternalChanges::decide_action(true, true, false, false) == EditorExternalChangeAction::PROMPT);
	CHECK(EditorExternalChanges::decide_action(true, true, false, true) == EditorExternalChangeAction::AUTO_RELOAD);

	Ref<ConfigFile> project_config;
	project_config.instantiate();

	CHECK(project_config->parse("config_version=5\n[application]\nconfig/name=\"Compatible\"\n") == OK);
	CHECK(EditorExternalChanges::is_project_settings_config_safe(project_config));

	project_config->clear();
	CHECK(project_config->parse("config_version=999\n") == OK);
	CHECK_FALSE(EditorExternalChanges::is_project_settings_config_safe(project_config));

	project_config->clear();
	CHECK(project_config->parse("config_version=\"5\"\n") == OK);
	CHECK_FALSE(EditorExternalChanges::is_project_settings_config_safe(project_config));

	project_config->clear();
	CHECK(project_config->parse("[application]\nconfig/name=\"Legacy without a version\"\n") == OK);
	CHECK(EditorExternalChanges::is_project_settings_config_safe(project_config));

	project_config->clear();
	ERR_PRINT_OFF;
	const Error malformed_parse_error = project_config->parse("config_version={\n");
	ERR_PRINT_ON;
	CHECK(malformed_parse_error != OK);
}
