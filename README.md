# FireSim

FireSim is an [open-source](https://github.com/firesim/firesim) FPGA-accelerated full-system hardware simulation platform that makes it easy to validate, profile, and debug RTL hardware implementations at 10s to 100s of MHz. FireSim simplifies co-simulating ASIC RTL with cycle-accurate hardware and software models for other system components (e.g. I/Os). FireSim can productively scale from individual SoC simulations hosted on on-prem FPGAs (e.g., a single Xilinx Alveo board attached to a desktop) to massive datacenter-scale simulations harnessing hundreds of cloud FPGAs (e.g., on Amazon EC2 F1).


## Quick Start

We provide here a quick guide to installing Firesim's dependency, building Firesim hardware and software.

### Dependency
##### Chipyard
Run these steps to install Chipyard (make sure to checkout the correct Chipyard commit as shown below):
```
git clone https://github.com/ucb-bar/chipyard.git
cd chipyard
git checkout 1.11.0
```
##### Repalce Gemmini Design

```
cd chipyard/generators/gemmini
git clone https://github.com/buddy-compiler/gemmini.git .
```

##### Initial Firesim Setup/Installation
Run these steps to initial Firesim's setup and installation [Firesim Document](https://docs.fires.im/en/1.18.0/Getting-Started-Guides/On-Premises-FPGA-Getting-Started/Initial-Setup/Xilinx-VCU118.html)



### Setup Firesim

FireSim is a submodule of Chipyard, used to accelerate the simulation of RTL designs. To utilise FireSim for testing the Buddy Compiler, we provide the following setup process for FireSim (based on VCU118).

```shell
cd chipyard/sims/firesim
git clone https://github.com/buddy-compiler/firesim.git .

cd chipyard
./build-setup.sh

cd chipyard/sims/firesim
source sourceme-manager.sh --skip-ssh-setup

cd chipyard/sims/firesim/sw/firesim-software
./init-submodules.sh
./marshal -v build br-base.json
```



#### Memory Model

Due to the hardware constraints of the simulation being performed in VCU118, we recommend to replaced the original memory model.

Original Configuration in `chipyard/generators/firechip/src/main/scala/TargetConfigs.scala`:

```scala
class FireSimGemminiRocketConfig extends Config(
  new WithDefaultFireSimBridges ++
  new WithDefaultMemModel ++
  new WithFireSimConfigTweaks ++
  new chipyard.GemminiRocketConfig)
```

Replaced Configuration:

```scala
class FireSimGemminiRocketConfig extends Config(
  new WithDefaultFireSimBridges ++
  new freechips.rocketchip.subsystem.WithExtMemSize((1 << 30) * 4L) ++
  new WithFireSimConfigTweaks ++
  new chipyard.GemminiRocketConfig)
```



Below we briefly describe the process of using firesim, we recommend reading the [official documents](https://docs.fires.im/en/1.18.0/Getting-Started-Guides/On-Premises-FPGA-Getting-Started/Repo-Setup/Xilinx-VCU118.html) for more details.

#### Simulation with Pre-generated Gemmini Bitstream Files

We have generated the Gemmini Bitstream Files under the above memory model configuration, with all other settings consistent with Gemmini's default configuration. These files are stored in the `chipyard/sims/firesim/deploy/results-build/pre_generated` directory. Below, we will demonstrate how to simulate using the pre-generated Gemmini bitstream files.

1. In the `chipyard/sims/firesim/deploy/` path, there are four files that configure key information for FireSim's build workload, bitstream, runtime, etc. To simulate with pre-generated Gemmini bitstream files, you just need to change two configuration to your path: `default_build_dir` in `config_build.yaml` and `default_simulation_dir` in `config_runtime.yaml`

2. Build and deploy simulation infrastructure to the Run Farm Machines. 

```
firesim infrasetup
```

3. Start simulation on Run Farm Machines. After executing the command below, the terminal will display a background monitor of the simulation running.

```
firesim runworkload
```

4. SSH connect to `BUILD_FARM_IP`, open a new terminal connection to the screen created by Run Farm Machines (please refer to the FireSim documentation to confirm you can correctly connect to Run Farm Machines).

```
ssh BUILD_FARM_IP
screen -r fsim0
```

5. Now, you can login to the system! The username is root and there is no password.



If you want to use your own hardware design bitstream files for simulation you can refer to this [document](https://docs.fires.im/en/1.18.0/Getting-Started-Guides/On-Premises-FPGA-Getting-Started/Building-a-FireSim-Bitstream/Xilinx-VCU118.html)
