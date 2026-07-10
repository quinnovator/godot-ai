def can_build(env, platform):
    return env.editor_build


def configure(env):
    env.module_add_dependencies("godot_agent", ["jsonrpc"], True)
