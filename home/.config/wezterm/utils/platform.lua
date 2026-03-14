local target = jit and jit.os or ""

return {
  is_windows = target == "Windows",
  is_linux = target == "Linux",
  is_macos = target == "OSX"
}

