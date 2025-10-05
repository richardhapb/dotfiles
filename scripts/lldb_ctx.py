import lldb

def ctx(debugger, command, result, internal_dict):
    cmds = [
        "register read",
        "disassemble --start-address $pc --count 12",
        "memory read --format hex --size 1 --count 64 $pc",
        "memory read --format hex --size 8 --count 8 $sp",
    ]
    for c in cmds:
        debugger.HandleCommand(c)

def __lldb_init_module(debugger, internal_dict):
    # Registers the 'ctx' command when this module is imported
    debugger.HandleCommand(f"command script add -f {__name__}.ctx ctx")
