// See LICENSE for license details.

package firesim.lib.testutils

import chisel3._

import firesim.lib.bridges._

// A simple MIDAS harness that generates a legacy
// module DUT (it has a single io: Data member) and connects all of
// its IO to a PeekPokeBridge
class PeekPokeHarness(dutGen: () => Module) extends RawModule {
  val clock = RationalClockBridge().io.clocks.head
  val reset = WireInit(false.B)

  withClockAndReset(clock, reset) {
    val dut = Module(dutGen())
    PeekPokeBridge(
      clock,
      reset,
      chisel3.experimental.DataMirror.modulePorts(dut).filterNot { case (name, _) =>
        name == "clock" | name == "reset"
      }: _*
    )
  }
}
