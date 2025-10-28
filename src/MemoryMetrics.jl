module MemoryMetrics

mutable struct SimplifiedMemoryMetrics
    # Number of allocated bytes since the last collection (reset on every GC cycle)
    julia_gc_num_allocd::UInt64
    # Internal GC metric used to keep track of allocated bytes within a
    # `gc_disable/gc_enable` block (reset on every GC cycle)
    # NOTE: this metric will always be zero in case of no use of `gc_disable/gc_enable`
    # blocks
    julia_gc_num_deferred_alloc::UInt64
    # Internal GC metric used to keep track of number of freed bytes in the current
    # collection (reset on every GC cycle)
    # NOTE: this metric is mainly used for GC internal purposes: it's incremented as
    # memory is reclaimed on a collection, used to gather some statistics
    # within the collection itself and reset at the end of a GC cycle.
    # So it's basically zero for external purposes
    # TODO: a metric to track total number of freed bytes should be added as well
    julia_gc_num_freed::UInt64
    # Number of `malloc/calloc` calls (never reset by the runtime)
    julia_gc_num_malloc::UInt64
    # Number of `realloc` calls (never reset by the runtime)
    julia_gc_num_realloc::UInt64
    # Number of pool allocation calls (never reset by the runtime)
    # NOTE: Julia uses an internal (pool) allocator for objects up to 2032 bytes.
    # Larger objects are allocated through `malloc/calloc`. See julia/src/gc.c
    julia_gc_num_poolalloc::UInt64
    # Number of allocations for "big objects" (non-array objects larger than 2032 bytes)
    # (never reset by the runtime)
    # NOTE: `malloc'd` arrays are not included in what Julia denotes "big objects".
    # The number of allocations for `malloc'd` objects should be tracked by
    # `julia_gc_num_malloc`. See julia/src/gc.c
    julia_gc_num_bigalloc::UInt64
    # Number of `free` calls (never reset by the runtime)
    julia_gc_num_freecall::UInt64
    # Number of allocated bytes for objects (never reset by the runtime)
    # NOTE: Julia keeps a count of bytes over allocated objects, rather than doing it
    # over allocated pages, so this metric may eviate from RSS
    julia_gc_num_total_allocd::UInt64
    # Sweep time (in ns) of the last collection
    julia_gc_num_sweep_time::UInt64
    # Mark time (in ns) of the last collection
    julia_gc_num_mark_time::UInt64
    # Sum of sweep times (in ns) over all collections
    julia_gc_num_total_sweep_time::UInt64
    # Time spent on page walk during sweep
    julia_gc_num_total_sweep_page_walk_time::UInt64
    # Time spent on madvise during sweep
    julia_gc_num_total_sweep_madvise_time::UInt64
    # Time spent on free during sweep
    julia_gc_num_total_sweep_free_mallocd_memory_time::UInt64
    # Sum of mark times (in ns) over all collections
    julia_gc_num_total_mark_time::UInt64
    # Track pool allocation statistics: each page virtual mapping is 64M and is never
    # released back. Physical poolmem GC pages are allocated at 16 KiB granularity and
    # are freed using MADV_FREE/DONTNEED once all objects on the page are sweeped.
    julia_poolmem_bytes_allocated::UInt64
    # Logical total size of Julia objects allocated on GC poolmem pages. It includes neither
    # poolmem overhead due to fragmentation nor big Julia allocations like arrays and strings
    # that go through malloc.
    julia_poolmem_live_bytes::UInt64
    # Bytes wasted due to fragmentation in pool memory pages
    julia_bytes_wasted_due_to_pool_fragmentation::UInt64
    # Program size reported by linux /proc subsystem.
    # Converted to bytes by assuming 4K pages.
    program_rss_bytes::UInt64
    # Default constructor initializing all fields to zero
    function SimplifiedMemoryMetrics()
        new(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    end
end

metrics = SimplifiedMemoryMetrics()

function update_memory_metrics!()
    @info "Updated Memory Metrics: $(metrics)"

    global metrics
    gc_stats = Base.gc_num()

    page_size = ccall(:getpagesize, Cint, ())
    if Sys.islinux() && page_size > 0
        open("/proc/self/statm") do io
            metrics.program_rss_bytes = parse(Int64, readuntil(io, ' ')) * page_size
        end
    end

    metrics.julia_gc_num_allocd = gc_stats.allocd
    metrics.julia_gc_num_deferred_alloc = gc_stats.deferred_alloc
    metrics.julia_gc_num_freed = gc_stats.freed
    metrics.julia_gc_num_malloc = gc_stats.malloc
    metrics.julia_gc_num_realloc = gc_stats.realloc
    metrics.julia_gc_num_poolalloc = gc_stats.poolalloc
    metrics.julia_gc_num_bigalloc = gc_stats.bigalloc
    metrics.julia_gc_num_freecall = gc_stats.freecall
    metrics.julia_gc_num_total_allocd = gc_stats.total_allocd
    metrics.julia_gc_num_sweep_time = gc_stats.sweep_time
    metrics.julia_gc_num_mark_time = gc_stats.mark_time
    metrics.julia_gc_num_total_sweep_time = gc_stats.total_sweep_time
    metrics.julia_gc_num_total_sweep_page_walk_time = gc_stats.total_sweep_page_walk_time
    metrics.julia_gc_num_total_sweep_madvise_time = gc_stats.total_sweep_madvise_time
    metrics.julia_gc_num_total_sweep_free_mallocd_memory_time = gc_stats.total_sweep_free_mallocd_memory_time
    metrics.julia_gc_num_total_mark_time = gc_stats.total_mark_time
    metrics.julia_poolmem_bytes_allocated = ccall(:jl_poolmem_bytes_allocated, UInt64, ())
    metrics.julia_poolmem_live_bytes = ccall(:jl_gc_pool_live_bytes, Int64, ())
    metrics.julia_bytes_wasted_due_to_pool_fragmentation = metrics.julia_poolmem_bytes_allocated - metrics.julia_poolmem_live_bytes
end

function spawn_periodic_metrics_task(interval_secs::Int)
    Threads.@spawn begin
        while true
            sleep(interval_secs)
            update_memory_metrics!()
        end
    end
end

end # module MemoryMetrics
