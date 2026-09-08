# MIPS Cache Controller & Memory Hierarchy

A VHDL implementation of a memory hierarchy and cache control unit for a MIPS processor. This project models a complete memory system including a Main Memory (MD), a Direct Access Scratch Memory, and a Cache (MC) acting as the intermediary, communicating via a semi-synchronous bus with arbitration[cite: 1]. 

## Architecture & Features

The cache controller is driven by an 8-state Mealy Finite State Machine (FSM) that resolves hits in a single cycle and manages complex bus transfers for misses, scratch accesses, and dirty block replacements[cite: 1]. A secondary 2-state FSM handles hardware-level memory errors[cite: 1].

* **Cache Specs:** 2-way set-associative, 4 sets, 4 words per block (32-bit words)[cite: 1].
* **Replacement Policy:** FIFO[cite: 1].
* **Write Policies:** Write-back (copyback) for dirty blocks; Write-around for write misses (direct to Main Memory without loading the block to cache)[cite: 1].
* **Bus Arbitration:** Manages access requests dynamically between the Cache Controller and an `IO_Master` peripheral[cite: 1].
* **Error Handling:** Detects unmapped address accesses and read-only register writes, immediately asserting a `Mem_ERROR` signal to trigger a `Data_abort` exception in the processor[cite: 1].

## Advanced Optimizations

To maximize processor performance and minimize wait states, the baseline FSM was extended with two advanced hardware optimizations:

* **Critical Word Forwarding:** When fetching a block from Main Memory, the controller identifies the specific word requested by the processor and forwards it immediately upon arrival on the bus, allowing the MIPS pipeline to resume execution while the remainder of the cache block is loaded in the background[cite: 1].
* **Basic Lockup-Free Cache:** Write misses are executed in the background[cite: 1]. The cache buffers the target address and data, allowing the processor to continue executing non-memory instructions (or cache hits) concurrently with the main memory write-around transfer[cite: 1].

## Vulnerability Analysis 

The project includes an *Ethical Hacking* evaluation demonstrating a "Dirty Block Flooding Attack"[cite: 1]. By forcing a continuous loop of write-hits (marking blocks dirty) and immediate misses within the same cache set, the exploit forces continuous write-backs[cite: 1]. This successfully saturates the bus, degrading the `IO_Master` peripheral's access rate by roughly 3x[cite: 1].

## Acknowledgments & Credits
* **VHDL Implementation & Design:** Developed by Óscar Grimal Torres and Hugo García Sánchez[cite: 1].
* **Base Skeleton:** Provided by the Department of Computer Engineering (Universidad de Zaragoza) for academic purposes[cite: 1].
