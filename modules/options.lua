newoption {
    trigger = "arch",
    value = "CPU_ARCHITECTURE",
    description = "Specify target processor architecture",
    allowed = {
        {"x64", "For x86_64 targets"},
        {"arm64", "For ARM64 targets"}
    },
    default = "x64"
}
