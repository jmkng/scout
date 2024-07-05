# Installation

```
zig fetch --save git+https://github.com/jmkng/scout
```

In `build.zig`:

```zig
const scout = b.dependency("scout", .{});
exe.root_module.addImport("scout", scout.module("scout"));
```
