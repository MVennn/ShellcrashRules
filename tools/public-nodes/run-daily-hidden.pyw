"""Task Scheduler entry point that never shows a console window.

`run-daily.cmd` is still the single source of truth for the job itself (log
rotation, UTF-8 env, python invocation). This wrapper only changes how it is
started: pythonw.exe is a GUI-subsystem binary, so no console is created, and
CREATE_NO_WINDOW keeps the cmd.exe child from allocating one either. Launching
cmd.exe directly from Task Scheduler always brings a window along, and with
Windows Terminal as the default terminal host that window is a visible tab.

Keep this file ASCII-only, like run-daily.cmd. Exit code is propagated so
Task Scheduler still reports the real result.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CMD = os.path.join(HERE, "run-daily.cmd")

CREATE_NO_WINDOW = 0x08000000

if not os.path.isfile(CMD):
    sys.exit("run-daily.cmd not found next to this launcher: " + CMD)

proc = subprocess.run(
    [os.environ.get("COMSPEC", r"C:\Windows\System32\cmd.exe"), "/c", CMD],
    creationflags=CREATE_NO_WINDOW,
)
sys.exit(proc.returncode)
