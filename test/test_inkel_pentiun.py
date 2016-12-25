import processor_model
import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.result import TestFailure

@cocotb.coroutine
def clock_gen(signal):
    while True:
        signal <= 0
        yield Timer(1)
        signal <= 1
        yield Timer(1)

@cocotb.test()
def init_test(dut):
    cocotb.fork(clock_gen(dut.clk))
    clk_rising = RisingEdge(dut.clk)
    model = processor_model.InkelPentiun("memory_boot")

    # Init test
    dut.reset <= 1
    yield clk_rising
    yield clk_rising
    dut.reset <= 0
    yield clk_rising

    first = True
    do_dump = False
    while True:
        mod_pc = model.step()
        if mod_pc == 0:
            break

        if do_dump:
            dut.debug_dump_F <= 1

        # Move simulation forward
        yield clk_rising

        # Signals in stage F are not propagated in case of stalling
        if dut.debug_dump_D == 1:
            do_dump = False
            dut.debug_dump_F <= 0

        # One instruction may take many cycles
        count = 1
        while count < 20 and dut.pc_out == 0:
            yield clk_rising

            # Signals in stage F are not propagated in case of stalling
            if dut.debug_dump_D == 1:
                do_dump = False
                dut.debug_dump_F <= 0

            count = count + 1

        if count == 20:
            raise TestFailure("Processor is in an infinite loop at PC 0x%08x" % mod_pc)

        if first:
            first = False
            do_dump = True

        # Check if dump has propagated
        if dut.debug_dump_WB == 1:
            if dut.debug_dump_F == 0 and dut.debug_dump_D == 0 and dut.debug_dump_A == 0 and dut.debug_dump_C == 0:
                # There is a bug: sometimes two debug signals are injected. I don't know why :(
                do_dump = True
                if model.check_dump("dump"):
                    raise TestFailure("Memories don't have the expected values")
                else:
                    dut._log.info("PC 0x%08x (memory) ok", old_proc_pc)

        # Check PC's
        proc_pc = dut.pc_out
        if mod_pc != proc_pc:
            raise TestFailure("Processor is at PC 0x%08x, whereas model is at PC 0x%08x" % (proc_pc, mod_pc))


        old_proc_pc = int(proc_pc)
        dut._log.info("PC 0x%08x ok", proc_pc)

    dut._log.info("Test run successfully!")