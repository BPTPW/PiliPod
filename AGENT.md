# PiliPod agent instructions

## Build verification

The Xcode MCP server (`xcode-mcp`) is configured for this project. After Swift
or Xcode project changes, prefer the Xcode MCP diagnostics/build/test tools for
verification. Do not treat shell `xcodebuild` as the default path unless the
MCP tools are unavailable in the current session or the user specifically asks
for shell output.
