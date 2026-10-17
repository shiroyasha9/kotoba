// Does the allocator give freed memory back? Allocates 150 MB in blocks of <size> bytes, frees all but one in <keep>,
// and prints phys_footprint before and after `malloc_zone_pressure_relief`. Results: docs/research/memory-spike.md,
// "Memory after use". Usage: xcrun swiftc -O main.swift -o retention && ./retention 300 50
// and again with MallocSpaceEfficient=1 in the environment.
import Darwin
func fp() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return Double(info.phys_footprint) / 1_048_576
}
let size = Int(CommandLine.arguments[1]) ?? 300
let keepEvery = Int(CommandLine.arguments[2]) ?? 50
print("start", fp())
var ptrs: [UnsafeMutableRawPointer] = []
for _ in 0..<(150_000_000 / size) { let p = malloc(size)!; memset(p, 1, size); ptrs.append(p) }
print("allocated", fp())
var kept: [UnsafeMutableRawPointer] = []
for (i, p) in ptrs.enumerated() { if i % keepEvery == 0 { kept.append(p) } else { free(p) } }
ptrs = []
print("freed (kept 1/\(keepEvery))", fp())
sleep(2)
print("after 2 s", fp())
print("relief released KB", malloc_zone_pressure_relief(nil, 0) / 1024)
print("after relief", fp())
