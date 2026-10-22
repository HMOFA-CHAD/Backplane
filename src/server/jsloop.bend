import Base

# Which loop runs the program: "c" natively; on the JS target "bun" when
# effects/loop.js put the runtime on Bun's event loop (sockets, processes
# and timers through Bun's APIs, so a Windows build serves), "sync" under
# BACKPLANE_JS_LOOP=sync (the runtime's own select loop, POSIX only).
# Every main asks it first: loop.js is bundled only when a def it backs is
# reached.
def Rt.loop() -> IO(String):
  import "./effects/loop.c"
  import "./effects/loop.js"
