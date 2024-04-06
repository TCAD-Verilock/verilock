<h1 align="center">
  verilock
</h1>
<p align="center">
  <img src="./img/verilock logo.jpg" width="160" />
</p>
`verilock` is a verification tool that can detect deadlocks in asynchronous circuits specified in SystemVerilog.
This repository includes the artifacts for the OOPSLA 2024 submission #292.

- `resource/cases` folder includes the cases collected from literatures.
- `resource/gen` folder includes the circuits synthesized randomly by [xin](https://github.com/OOPSLA24-Verilock/xin), where `Gen1` ~ `Gen5` are the cases without deadlocks, and `Gen6` ~ `Gen10` are the ones with deadlocks.

### Installation

1. Install Rust tool chain.
```shell
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
2. Clone this repository.

3. Navigate to the project directory.
```shell
cd verilock
```
4. Build the project.
```shell
cargo build
```

### Reproducing Experimental Results
To replicate the experimental result from OOPSLA24 submission #292, please adhere to these instructions.
#### Observing Verification Results
1. To observe the results that `verilock` verifies the cases from the literatures, run the command: 
```shell
cargo run -- RQ1
```

2. To observe the results that `verilock` verifies the cases randomly synthesized, run the command:
```shell
cargo run -- RQ2
```

3. To observe the results that `verilock-flatten` verifies the cases from the literatures, run the command:
```shell
cargo run -- -f RQ1
```

4. To observe the results that `verilock-flatten` verifies the cases randomly synthesized, run the command:
```shell
cargo run -- -f RQ2
```