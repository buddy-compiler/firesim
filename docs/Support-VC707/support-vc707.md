# Adding support for VC707

First, you need to create a new folder under `~/firesim/platforms/` to store VC707 related design files and scripts.

When creating new folders and files, rename `xilinx_alveo_u250` to your specific FPGA name (`xilinx_vc707`).

```bash
cd ~/firesim/
git checkout 12e2e0a (release 1.20.1)
git checkout -b vc707
cd ~/firesim/platforms/
mkdir xilinx_vc707
```

>FPGAs in FireSim, when first developed, start with implementing/testing the AXI4-Lite interface before moving to add the DMA interface and DRAM. We highly recommend you to follow the same flow when adding an FPGA.

## Adding a new FireSim `platform`

In order to make firesim support VC707, we need to get the bitstream that can be programmed into the VC707 board, so we need to first understand how the `firesim buildbitstream` command generates the bitstream for the u250 board.

Through `which firesim`, we can know that the firesim command actually runs the python program `~/firesim/deploy/firesim`. The specific tasks are defined in the python program. For example, the corresponding code of `firesim buildbitstream` is as follows:

```python
@register_task
def buildbitstream(build_config_file: BuildConfigFile) -> None:
    """ Starting from local Chisel, build a bitstream for all of the specified
    hardware configs. """

    # forced to build locally
    for build_config in build_config_file.builds_list:
        execute(build_config.bitbuilder.replace_rtl, hosts=['localhost'])
        execute(build_config.bitbuilder.build_driver, hosts=['localhost'])
    ...
```

Before running the `firesim buildbitstream` command, be sure to make some modifications to `./firesim/deploy/config_build.yaml`: modify `default_build_dir` to specify the directory to build in; modify `builds_ro_run` to determine the build object, for example, for u250, build `alveo_u250_firesim_rocket_singlecore_no_nic`.

In the `buildbitstream` function, `build_config.bitbuilder.replace_rtl` actually executes the following command:

```bash
cd ~/firesim/sim/
make PLATFORM=xilinx_alveo_u250 TARGET_PROJECT=firesim DESIGN=FireSim TARGET_CONFIG=FireSimRocketConfig PLATFORM_CONFIG=BaseXilinxAlveoU250Config replace-rtl
```

This command actually executes the following content in `~/firesim/sim/make/fpga.mk`:

```makefile
replace-rtl: $(fpga_delivery_files) $(fpga_sim_delivery_files)

fpga_delivery_files = $(addprefix $(fpga_delivery_dir)/$(BASE_FILE_NAME), \
	.sv .defines.vh \
	.synthesis.xdc .implementation.xdc)

fpga_sim_delivery_files = $(fpga_driver_dir)/$(DESIGN)-$(PLATFORM)
```

For the u250 board, the above `fpga_delivery_files` corresponds to

```
~/firesim/platforms/xilinx_alveo_u250/cl_xilinx_alveo_u250-firesim-FireSim-FireSimRocketConfig-BaseXilinxAlveoU250Config/design
|-- FireSim-generated.sv
|-- FireSim-generated.defines.vh
|-- FireSim-generated.synthesis.xdc
|-- FireSim-generated.implementation.xdc
```

The above `fpga_sim_delivery_file` corresponds to `~/firesim/platforms/xilinx_alveo_u250/cl_xilinx_alveo_u250-firesim-FireSim-FireSimRocketConfig-BaseXilinxAlveoU250Config/driver/FireSim-xilinx_alveo_u250`



Before calling vivado to generate bitstream, you first need to automatically generate RTL through firesim, so you need to make some modifications to the files under `platforms/xilinx_alveo_u250/cl_firesim`.

`platforms/xilinx_alveo_u250/cl_firesim` holds all RTL, TCL, and more needed to build a bitstream for a specific FPGA.

First, you’ll need to add new Scala configurations to tell Golden Gate there is a new FPGA.

```scala
class XilinxAlveoU250Config
    extends Config(new Config((_, _, _) => {
      case F1ShimHasQSFPPorts  => true
      case HostMemNumChannels  => 1
      case PreLinkCircuitPath  => Some("firesim_top")
      case PostLinkCircuitPath => Some("firesim_top")
    }) ++ new F1Config ++ new SimConfig)
```

Next, you’ll need to provide a C++ interface that allows FireSim to read/write to the FPGA’s MMIO (AXI4-Lite) and DMA (AXI4) port through XDMA. 

```c
uint32_t simif_xilinx_alveo_u250_t::read(size_t addr) {
  uint32_t value;
  int rc = fpga_pci_peek(addr, &value);
  return value & 0xFFFFFFFF;
}
```

Next, you’ll need to add a hook to FireSim’s make system to build the FPGA RTL and also build the C++ driver with the given `simif_*` file. 

At this point you should be able to build the RTL using something like `make -C sim PLATFORM=xilinx_alveo_u250 xilinx_alveo_u250` where you can replace `xilinx_alveo_u250` with your FPGA platform name. This should build both the C++ driver and the RTL associated with it that is copied for synthesis.



## Manager build modifications

Next, you’ll need to tell the FireSim manager a new platform exists to use it in `firesim buildbitstream`.

First, we need to add a “bit builder” class that gives the Python code necessary to build and synthesize the RTL on a build farm instance/machine and copy the results back into a FireSim HWDB entry.

In the Xilinx Alveo U250 case, the `build_bitstream` function builds a bitstream by doing the following in Python:

1. Creates a copy of the `platform` area previously described on the build farm machine/instance
2. Adds the RTL built with the `make` command from the prior section to that copied area (i.e. `CL_DIR`)
3. Runs the [platforms/xilinx_alveo_u250/build-bitstream.sh](https://www.github.com/firesim/firesim/blob/HEAD/platforms/xilinx_alveo_u250/build-bitstream.sh) script with the copied area.
4. Retrieves the bitstream built and compiles a `*.tar.gz` file with it. Uses that file in a HWDB entry.

Next, since this class can take arguments from FireSim’s YAML, you’ll need to add a YAML file for a new FPGA in [deploy/bit-builder-recipes](https://www.github.com/firesim/firesim/blob/HEAD/deploy/bit-builder-recipes) (even if it has no args).

Reference：https://docs.fires.im/en/latest/Advanced-Usage/Adding-FPGAs.html









