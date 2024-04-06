`timescale 1ns/1fs

`include "Channel.sv"

// xuOperation
// op 0: adder sub
// op 1: adder slt
// op 2: adder sum
// op 3: branch EQ
// op 4: branch NE
// op 5: branch LT
// op 6: branch GE
// op 7: branch JL
// op 8: bypassB
// op 9: logic xor
// op 10: logic or
// op 11: logic and
// op 12: shifter Ll
// op 13: shifter Rl
// op 14: shifter Ra
// op 15: memory LB
// op 16: memory LH
// op 17: memory LW
// op 18: memory SB
// op 19: memory SH
// op 20: memory SW

// XuSelector
// xuBypassSel: 0
// xuAdderSel: 1
// xuLogicSel: 2
// xuShiftSel: 3
// xuMemorySel: 4
// xuBranchSel: 5

// Constructs a two stages adder execution unit.
// This unit is used by ADD(I), SUB(I), SLT(I), SLT(I)U instructions.
//
// In the real implementation adder logic may be distributed across the two stages,
// in this model the second stage is a just a dummy delay stage.
module Adder(interface inputA,
             interface inputB,
             interface inputOp,
             interface result);
  Channel buffer();
  AdderStage1 stage1(buffer, result);
  AdderStage2 stage2(inputA, inputB, inputOp, buffer);
endmodule

module AdderStage1(interface buffer,
                   interface result);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] data;
  always begin 
    buffer.Receive(data);
    result.Send(data);
  end
endmodule

module AdderStage2(interface inputA,
                   interface inputB,
                   interface inputOp,
                   interface buffer);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic [WIDTH-1:0] op;
  always begin
    inputA.Receive(a);
    inputB.Receive(b);
    inputOp.Receive(op);
    if (op == 0) begin
      buffer.Send(a - b);
    end else if (op == 1) begin
      if (a < b) begin
        buffer.Send(1);
      end else begin 
        buffer.Send(0);
      end
    end else if (op == 2) begin
      buffer.Send(a + b);
    end
  end
endmodule

// This function constructs the branch unit two logical stages.
//
// In the real implementation adder logic may be distributed across the two stages,
// in this model the second stage is a just a dummy delay stage.
module Branch(interface inputA,
              interface inputB,
              interface inputC,
              interface inputPC,
              interface inputOp,
              interface outputLink,
              interface outputTaken,
              interface outputLinkAddr,
              interface outputTarget);
  Channel bufferLink();
  Channel bufferTaken();
  Channel bufferLinkAddr();
  Channel bufferTarget();
  BranchStage1 stage1(
    bufferLink, 
    bufferTaken, 
    bufferLinkAddr, 
    bufferTarget, 
    outputLink, 
    outputTaken, 
    outputLinkAddr, 
    outputTarget);
  BranchStage2 stage2(
    inputA, 
    inputB, 
    inputC, 
    inputPC, 
    inputOp, 
    bufferLink, 
    bufferTaken, 
    bufferLinkAddr, 
    bufferTarget);
endmodule

module BranchStage1(interface bufferLink,
                    interface bufferTaken,
                    interface bufferLinkAddr,
                    interface bufferTarget,
                    interface outputLink,
                    interface outputTaken,
                    interface outputLinkAddr,
                    interface outputTarget);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] link;
  logic [WIDTH-1:0] taken;
  logic [WIDTH-1:0] linkAddr;
  logic [WIDTH-1:0] target;
  always begin 
    bufferLink.Receive(link);
    bufferTaken.Receive(taken);
    bufferLinkAddr.Receive(linkAddr);
    bufferTarget.Receive(target);
    outputLink.Send(link);
    outputTaken.Send(taken);
    outputLinkAddr.Send(linkAddr);
    outputTarget.Send(target);
  end
endmodule

module BranchStage2(interface inputA,
                    interface inputB,
                    interface inputC,
                    interface inputPC,
                    interface inputOp,
                    interface bufferLink,
                    interface bufferTaken,
                    interface bufferLinkAddr,
                    interface bufferTarget);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic [WIDTH-1:0] c;
  logic [WIDTH-1:0] pc;
  logic [WIDTH-1:0] op;
  always begin 
    inputA.Receive(a);
    inputB.Receive(b);
    inputC.Receive(c);
    inputPC.Receive(pc);
    inputOp.Receive(op);
    if (op == 7) begin 
      bufferLink.Send(1);
      bufferTaken.Send(1);
      bufferLinkAddr.Send(pc + 4);
      bufferTarget.Send(a + b);
    end else begin 
      bufferLink.Send(0);
      if (op == 3) begin
        if (a == b) begin 
          bufferTaken.Send(1);
        end else begin 
          bufferTaken.Send(0);
        end
      end else if (op == 4) begin
        if (a != b) begin 
          bufferTaken.Send(1);
        end else begin 
          bufferTaken.Send(0);
        end
      end else if (op == 5) begin
        if (a < b) begin 
          bufferTaken.Send(1);
        end else begin 
          bufferTaken.Send(0);
        end
      end else begin
        if (a >= b) begin 
          bufferTaken.Send(1);
        end else begin 
          bufferTaken.Send(0);
        end
      end
      bufferLinkAddr.Send(pc + 4);
      bufferTarget.Send(pc + c);
    end
  end
endmodule

// Constructs a dummy bypass element used by bubbles, LUI and NOP instructions.
// Initiated to zeros as the execution loop started filled.
module BypassEl(interface inputC,
                interface outputC);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] data;
  // initial begin 
  //   outputC.Send(0);
  // end
  always begin 
    inputC.Receive(data);
    outputC.Send(data);
  end
endmodule

// // Constructs a parameterisabled depth bypass execution unit.
module Bypass2(interface bypassIn,
               interface bypassOut);
  Channel internal();
  BypassEl be1(bypassIn, internal);
  BypassEl be2(internal, bypassOut);
endmodule

// This struct concatenates all signals sent from the decoder to the operandFetchUnit,
// so they can be send using a single channel under a single handshake,
// simulating the behavior found in hardware.
//
// ins is the raw instruction opcode
// op is used by the dispatcher to select the correct execution unit and by the unit to select the operation
// fmt is used by operandFetchUnit to retrieve the correct instruction operand sources
// regA, rebB and regD are onehot representations of the register addresses used by the operandFetchunit

// The decoder unit decodes the instruction opcode fetched from memory into control signals used by later stages.
//
// The pc and valid (streamtag) from the fetch unit are further delayed one handshake cycle and synchronized with
// the control signals.
module Decoder(interface fetchValid,
               interface fetchPcAddr,
               interface instruction,
               interface decoderPc,
               interface decoderValid,
               interface decoderInstruction,
               interface decoderRegA,
               interface decoderRegB,
               interface decoderRegD,
               interface decoderXuOp,
               interface outOpFormat);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] inst;
  logic [WIDTH-1:0] pc;
  logic [WIDTH-1:0] pe;
  logic [WIDTH-1:0] valid;
  logic [WIDTH-1:0] validE;
  logic [WIDTH-1:0] ra;
  logic [WIDTH-1:0] rb;
  logic [WIDTH-1:0] rd;
  
  always begin 
    instruction.Receive(inst);
    fetchPcAddr.Receive(pc);
    // fetchPcAddr.Receive(pe);
    fetchValid.Receive(valid);
    // fetchValid.Receive(validE);
    decoderPc.Send(pc);
    decoderValid.Send(valid);
    decoderInstruction.Send(inst);
    ra = (inst >> 15) & 2'h1F;
    rb = (inst >> 20) & 2'h1F;
    rd = (inst >> 07) & 2'h1F;
    decoderRegA.Send(ra);
    decoderRegB.Send(rb);
    decoderRegD.Send(rd);
    if (inst == 19 || inst == 103 || inst == 3) begin 
      outOpFormat.Send(1);
    end else if (inst == 111) begin 
      outOpFormat.Send(5);
    end else if (inst == 51) begin 
      outOpFormat.Send(0);
    end else if (inst == 99) begin 
      outOpFormat.Send(3);
    end else if (inst == 55 || inst == 23) begin 
      outOpFormat.Send(4);
    end else if (inst == 35) begin 
      outOpFormat.Send(2);
    end else begin 
      outOpFormat.Send(6);
    end
    if (inst == 15 || inst == 55) begin 
      decoderXuOp.Send(8); // bypassB
    end else if (inst == 23) begin 
      decoderXuOp.Send(2); // adder sum
    end else if (inst == 111) begin 
      decoderXuOp.Send(7); // branch JL
    end else begin 
      if (inst == 103) begin 
        decoderXuOp.Send(7); // branch JL
      end else if (inst == 99) begin 
        decoderXuOp.Send(3); // branch EQ
      end else if (inst == 4195) begin 
        decoderXuOp.Send(4); // branch NE
      end else if (inst == 16483) begin 
        decoderXuOp.Send(5); // branch LT
      end else if (inst == 20579) begin 
        decoderXuOp.Send(6); // branch GE
      end else if (inst == 3) begin 
        decoderXuOp.Send(15); // memory LB
      end else if (inst == 4099) begin 
        decoderXuOp.Send(16); // memory LH
      end else if (inst == 8195) begin 
        decoderXuOp.Send(17); // memory LW
      end else if (inst == 35) begin
        decoderXuOp.Send(18); // memory SB
      end else if (inst == 4131) begin 
        decoderXuOp.Send(19); // memory SH
      end else if (inst == 8227) begin 
        decoderXuOp.Send(20); // memory SW
      end else if (inst == 19) begin 
        decoderXuOp.Send(2); // adder sum
      end else if (inst == 8211) begin 
        decoderXuOp.Send(1); // adder slt
      end else if (inst == 16403) begin 
        decoderXuOp.Send(9); // xor
      end else if (inst == 24595) begin 
        decoderXuOp.Send(10); // or
      end else if (inst == 28691) begin 
        decoderXuOp.Send(11); // and
      end else begin 
        if (inst == 4147 || inst == 4115) begin 
          decoderXuOp.Send(12); // shifter Ll
        end else if (inst == 20531 || inst == 20499) begin 
          decoderXuOp.Send(13); // shifter Rl
        end else if (inst == 1073 || inst == 1073762323) begin 
          decoderXuOp.Send(14); // shifter Ra
        end else if (inst == 51) begin 
          decoderXuOp.Send(2); // adder sum
        end else if (inst == 1073741875) begin 
          decoderXuOp.Send(0); // adder sub
        end else if (inst == 8243) begin 
          decoderXuOp.Send(1); // adder slt
        end else if (inst == 16435) begin 
          decoderXuOp.Send(9); // xor
        end else if (inst == 24627) begin 
          decoderXuOp.Send(10); // or
        end else if (inst == 28723) begin 
          decoderXuOp.Send(11); // and
        end else begin 
          decoderXuOp.Send(8); // bypassB
        end
      end
    end
    
  end

endmodule

// This function constructs the dispatcher logic stage
//
// The instruction control signals is received through the the dispatcherIn,
// the dispatcher then selects the correct execution unit using the upper bits of the xuOper,
// sending the instruction to the correct execution unit.
//
// The selected execution unit is sent to the program ordering queue along with the stream tag.
//
// The stage is initiated to a bubble
module Dispatcher(interface dispatcherValid,
                  interface dispatcherPcAddr,
                  interface decoderXuOp,
                  interface dispatcherA,
                  interface dispatcherB,
                  interface dispatcherC,
                  interface outProgramValid,
                  interface outProgramXuSelector,
                  interface bypassIn,
                  interface outAdderA,
                  interface outAdderB,
                  interface outAdderXuOp,
                  interface outLogicA,
                  interface outLogicB,
                  interface outLogicXuOp,
                  interface outShifterA,
                  interface outShifterB,
                  interface outShifterXuOp,
                  interface outMemoryA,
                  interface outMemoryB,
                  interface outMemoryC,
                  interface outMemoryXuOp,
                  interface outBranchA,
                  interface outBranchB,
                  interface outBranchC,
                  interface outBranchPC,
                  interface outBranchXuOp);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] valid;
  logic [WIDTH-1:0] pcAddr;
  logic [WIDTH-1:0] xuOp;
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic [WIDTH-1:0] c;
  logic [WIDTH-1:0] xuSel;
  always begin 
    outProgramValid.Send(255);
    outProgramXuSelector.Send(0); // xuBypassSel
    bypassIn.Send(0);
    dispatcherValid.Receive(valid);
    dispatcherPcAddr.Receive(pcAddr);
    decoderXuOp.Receive(xuOp);
    dispatcherA.Receive(a);
    dispatcherB.Receive(b);
    dispatcherC.Receive(c);
    xuSel = xuOp >> 4;
    if (xuSel == 0) begin 
      outBypass.Send(b);
    end else if (xuSel == 1) begin 
      outAdderA.Send(a);
      outAdderB.Send(b);
      outAdderXuOp.Send(xuOp);
    end else if (xuSel == 2) begin 
      outLogicA.Send(a);
      outLogicB.Send(b);
      outLogicXuOp.Send(xuOp);
    end else if (xuSel == 3) begin 
      outShifterA.Send(a);
      outShifterB.Send(b);
      outShifterXuOp.Send(xuOp);
    end else if (xuSel == 4) begin 
      outMemoryA.Send(a);
      outMemoryB.Send(b);
      outMemoryC.Send(c);
      outMemoryXuOp.Send(xuOp);
    end else begin 
      outBranchA.Send(a);
      outBranchB.Send(b);
      outBranchC.Send(c);
      outBranchPC.Send(pcAddr);
      outBranchXuOp.Send(xuOp);
    end
    outProgramValid.Send(valid);
    outProgramXuSelector.Send(xuSel);
  end
endmodule

// Constructs a read-only memory port logic stage as described in the Memory interface.
//
// Memory locations corresponding to the valid range in the file are read normally,
// non mapped memory and special memory regions returns all zero data.
module MemoryRead(interface fetchAddr,
                  interface len,
                  interface instruction);
  parameter WIDTH = 32;
  
  logic [WIDTH-1:0] addr;
  logic [WIDTH-1:0] length;
  logic [WIDTH-1:0] memory [0:255];

  always begin 
    fetchAddr.Receive(addr);
    len.Receive(length);
    if (addr + length < 256) begin 
      instruction.Send(memory[addr:addr+length]);
    end else begin 
      instruction.Send(0);
    end
  end
endmodule

// Constructs a read-then-write memory port logic stage as described in the Memory interface.
//
// Memory locations backed by file are read normally,
// non mapped memory and special memory regions returns all zero data.
//
// Memory regions backed by the file are written normally,
// writes to special memory regions trigger actions as documented in memoryArray struct,
// writes to memory locations bellow 0x80000000 not backed by file are discarded.
module MemoryWrite(interface inAddr,
                   interface inLength,
                   interface inDataIn,
                   interface inWe,
                   interface outData);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] addr;
  logic [WIDTH-1:0] length;
  logic [WIDTH-1:0] memory [0:255];
  logic [WIDTH-1:0] index = 0;
  logic [WIDTH-1:0] data;
  logic [WIDTH-1:0] we;
  always begin 
    inAddr.Receive(addr);
    inDataIn.Receive(data);
    inLength.Receive(length);
    if ((addr >= 2147508224) && (addr < 2147508232)) begin 
      outData.Send(1);
    end else if ((addr < 2147508224) && (addr + length < 256)) begin 
      outData.Send(memory[addr + index]);
    end else begin 
      outData.Send(0);
    end
    inWe.Receive(we);
    if (we == 1) begin 
      memory[addr] = data;
    end
  end
endmodule

// nextPc and streamTag logic unit constructor
//
// receives the currPC and currValid values from the delay logic stage in the fetchUnit
// and computes the nextPc, fetchaddr and nextValid (streamtag) values based on the presence of a branch address
module NextPc(interface currPc,
              interface currValid,
              interface inBranch,
              interface fetchAddr,
              interface nextPc,
              interface nextValid);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] pc;
  logic [WIDTH-1:0] valid;
  logic [WIDTH-1:0] branch;

  initial begin
    nextPc.Send(0);
    fetchAddr.Send(0);
    nextValid.Send(0);
  end

  always begin 
    currPc.Receive(pc);
    currValid.Receive(valid);
    inBranch.Receive(branch);
    nextValid.Send(valid + 1);
    if (branch == 0) begin 
      fetchAddr.Send(pc + 4);
      nextPc.Send(pc + 4);
    end else begin 
      fetchAddr.Send(branch);
      nextPc.Send(branch);
    end
  end
endmodule

// the fetchUnit constructor instantiates the nextPcUnit,
// a delay logic element and a memory port.
//
// The delay logic element delays in one handshake cycle the value of nextPc and nextValid
// sending them back to the nextPcUnit to form the pc/streamtag loop
// and forwarding them to the decoder unit.
//
// In parallel with the delay element, the memory port fetches the instruction from the fetchAddr
// outputting the fetched instruction directly to the decoderUnit.
module Fetch(interface inBranch,
             interface fetchPcAddr,
             interface instruction,
             interface fetchValid);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] pc;
  logic [WIDTH-1:0] valid;
  Channel nextPc();
  Channel currPc();
  Channel fetchAddr();
  Channel nextValid();
  Channel currValid();
  Channel len();

  NextPc nextPcUnit(currPc, currValid, inBranch, fetchAddr, nextPc, nextValid);

  MemoryRead memoryRead(fetchAddr, len, instruction);

  FetchStage1 fetchStage1(currPc, nextPc, fetchPcAddr);
  FetchStage2 fetchStage2(currValid, nextValid, fetchValid);
  FetchStage3 fetchStage3(len);
endmodule

module FetchStage1(interface currPc,
                   interface nextPc,
                   interface fetchPcAddr);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] pc;
  always begin 
    nextPc.Receive(pc);
    fetchPcAddr.Send(pc);
    currPc.Send(pc);
  end
endmodule

module FetchStage2(interface currValid,
                   interface nextValid,
                   interface fetchValid);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] valid;
  always begin 
    // nextValid.Receive(valid);
    // outValid.Send(valid);
    // currValid.Send(valid);
    nextValid.Receive(valid);
    currValid.Send(valid);
    fetchValid.Send(valid);
  end
endmodule

module FetchStage3(interface len);
  always begin 
    len.Send(4);
  end
endmodule

// Constructs the logic execution unit logic stages
// This unit is used by XOR(I), OR(I), AND(I) instructions.
//
// The unit is two-stage long to match the the expected depth of execution units.
// Due to the simple logic, use of buffer may be carried to the silicon design.
module Logic(interface inA,
             interface inB,
             interface inXuOp,
             interface outResult);
  Channel buffer();
  LogicStage1 stage1(buffer, outResult);
  LogicStage2 stage2(inA, inB, inXuOp, buffer);
endmodule

module LogicStage1(interface buffer,
                   interface outResult);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] data = 0;
  always begin 
    buffer.Receive(data);
    outResult.Send(data);
  end
endmodule

module LogicStage2(interface inA,
                   interface inB,
                   interface inXuOp,
                   interface outResult);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic [WIDTH-1:0] xuOp;
  always begin 
    inA.Receive(a);
    inB.Receive(b);
    inXuOp.Receive(xuOp);
    if (xuOp == 9) begin 
      outResult.Send(a ^ b);
    end else if (xuOp == 10) begin 
      outResult.Send(a | b);
    end else begin 
      outResult.Send(a & b);
    end
  end
endmodule

// Constructs the memory access controller as a execution unit stage.
// It instantiate the first stage, a memory read-then-write port and the second stage.
//
// This unit is used for LW, LH(U), LB(U), SW, SH, SB.
//
// Data in memory is encoded as little-endian.
// The first stage computes the base address, encodes the data to be written
// and generate control signals to access the memory;
// the memory port then retrieves the data, if a write is issued it waits on the we channel
// for confirmation from the retire unit;
// the second stage decodes and sign extends the data read and sends to the retire unit,
// if the operation is a write the second stage signals the retire unit to control the we channel.
//
// The we channel is only used if a write is issued to the memory port,
// otherwise it is left idle and is ignored by the memory port.
module Memory(interface inA,
              interface inB,
              interface inC,
              interface inXuOp,
              interface inWe,
              interface outWriteRequest,
              interface outMemoryRead,
              interface outValue);
  Channel addr();
  Channel rdata();
  Channel wdata();
  Channel rlen();
  Channel operation();
  MemoryWrite memoryWrite(addr, rlen, wdata, inWe, rdata);
  MemoryStage1 memoryStage1(
    operation, 
    inA, 
    inB, 
    inC, 
    inXuOp, 
    addr,
    wdata, 
    rlen);
  MemoryStage2 memoryStage2(
    operation, 
    rdata, 
    outWriteRequest, 
    outMemoryRead, 
    outValue);
endmodule

module MemoryStage1(interface operation,
                    interface inA,
                    interface inB,
                    interface inC,
                    interface inXuOp,
                    interface addr,
                    interface wdata,
                    interface rlen);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic [WIDTH-1:0] c;
  logic [WIDTH-1:0] xuOp;
  always begin 
    inA.Receive(a);
    inB.Receive(b);
    inC.Receive(c);
    inXuOp.Receive(xuOp);
    operation.Send(xuOp);
    addr.Send(a + b);
    if (xuOp == 15) begin // memory LB
      wdata.Send(0);
      rlen.Send(1);
    end else if (xuOp == 16) begin // memory LH
      wdata.Send(0);
      rlen.Send(2);
    end else if (xuOp == 17) begin // memory LW
      wdata.Send(0);
      rlen.Send(4);
    end else if (xuOp == 18) begin // memory SB
      wdata.Send(c & 2'hFF);
      rlen.Send(1);
    end else if (xuOp == 19) begin  // memory SH
      wdata.Send(c & 2'hFFFF);
      rlen.Send(2);
    end else begin // memory SW
      wdata.Send(c);
      rlen.Send(4);
    end
  end
endmodule

module MemoryStage2(interface operation,
                    interface rdata,
                    interface outWriteRequest,
                    interface outMemoryRead,
                    interface outValue);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] xuOp;
  logic [WIDTH-1:0] val;
  logic [WIDTH-1:0] writeRequest;
  logic [WIDTH-1:0] memoryRead;
  logic [WIDTH-1:0] outData;
  always begin 
    operation.Receive(xuOp);
    rdata.Receive(val);
    writeRequest = 0;
    memoryRead = 1;
    outData = 0;
    if (xuOp == 18) begin // memory SB
      writeRequest = 1;
      memoryRead = 0;
    end else if (xuOp == 19) begin // memory SH
      writeRequest = 1;
      memoryRead = 0;
    end else if (xuOp == 20) begin // memory SW
      writeRequest = 1;
      memoryRead = 0;
    end else if (xuOp == 15) begin // memory SB
      outData = val;
    end else if (xuOp == 16) begin // memory LH
      outData = val;
    end else if (xuOp == 17) begin // memory LW
      outData = val;
    end else begin 
      outData = 0;
    end
    outWriteRequest.Send(writeRequest);
    outMemoryRead.Send(memoryRead);
    outValue.Send(outData);
  end
endmodule

// Constructs the operandFetchUnit logic stage
//
// The control signals are received from the decoder unit,
// the instruction format is used to determinate the required operands,
// the regLock channel is read and if the instruction format requires register operands,
// the register address is compared with the registerLock mask and bubbles are issue untill the register is unlocked,
// after every required register are unlocked, the immediate values are sign extended
// and the instruction is issued.
//
// Instructions and bubbles are issued by writing to the dispatcherOut, regRcmdOut and regDaddrOut channels.
// The dispatcherOut channel sends the operation control signal, the operands and the stream tag to the dispatcher.
// regRcmdOut is used by the registerBypassUnit to compare the simultaneous register reads and writes and retrieve register values.
// regDaddrOut is the destination register feed into the register lock queue and later used to write back results.
module OperandFetch(interface decoderPc,
                    interface decoderValid,
                    interface decoderInstruction,
                    interface decoderRegA,
                    interface decoderRegB,
                    interface decoderRegD,
                    interface decoderOp,
                    interface decoderOpFormat,
                    interface regLock,
                    interface dispatcherValid,
                    interface outPcAddr,
                    interface outXuOp,
                    interface outA,
                    interface outB,
                    interface outC,
                    interface outRegDaddr);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] pc;
  logic [WIDTH-1:0] valid;
  logic [WIDTH-1:0] instruction;
  logic [WIDTH-1:0] regA;
  logic [WIDTH-1:0] regB;
  logic [WIDTH-1:0] regD;
  logic [WIDTH-1:0] op;
  logic [WIDTH-1:0] opFormat;
  logic [WIDTH-1:0] regLock;
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic [WIDTH-1:0] c;
  Channel chAaddr();
  Channel chAdata();
  Channel chBaddr();
  Channel chBdata();
  RegBankRead regReadA(chAaddr, chAdata);
  RegBankRead regReadB(chBaddr, chBdata);
  always begin 
    decoderPc.Receive(pc);
    decoderValid.Receive(valid);
    decoderInstruction.Receive(instruction);
    decoderRegA.Receive(regA);
    decoderRegB.Receive(regB);
    decoderRegD.Receive(regD);
    decoderOp.Receive(op);
    decoderOpFormat.Receive(opFormat);
    a = 0;
    b = 0;
    c = 0;

     if (opFormat == 1) begin // format I
       inRegLock.Receive(regLock);
       dispatcherValid.Send(valid);
       outPcAddr.Send(pc);
       outXuOp.Send(8); // bypass B
       outA.Send(0);
       outB.Send(0);
       outC.Send(0);
       outRegDaddr.Send(1);
       inRegLock.Receive(regLock);
       chAaddr.Send(regA);
       chAdata.Receive(a);
       b = instruction >> 20;
     end else if (opFormat == 4) begin // format U
       inRegLock.Receive(regLock);
       a = pc;
       b = instruction & 8'hFFFFF000;
     end else if (opFormat == 5) begin // format J
       a = pc;
       b = ((instruction >> 12) & 8'hFFF00000) |
           (instruction & 8'h000FF000) |
           ((instruction >> 9) & 3'h800) |
           ((instruction >> 20) & 3'h7FE);
     end else if (opFormat == 2) begin // format S
       inRegLock.Receive(regLock);
       dispatcherValid.Send(valid);
       outPcAddr.Send(pc);
       outXuOp.Send(8); // bypass B
       outA.Send(0);
       outB.Send(0);
       outC.Send(0);
       outRegDaddr.Send(1);
       inRegLock.Receive(regLock);
       chAaddr.Send(regA);
       chBaddr.Send(regB);
       chAdata.Receive(a);
       b = ((instruction >> 20) & 8'hFFFFFFE0) | ((instruction >> 7) & 2'h1F);
       chBdata.Receive(c);
     end else if (opFormat == 0 || opFormat == 3) begin // format R or B
       inRegLock.Receive(regLock);
       dispatcherValid.Send(valid);
       outPcAddr.Send(pc);
       outXuOp.Send(8); // bypass B
       outA.Send(0);
       outB.Send(0);
       outC.Send(0);
       outRegDaddr.Send(1);
       chAaddr.Send(regA);
       chBaddr.Send(regB);
       chAdata.Receive(a);
       chBdata.Receive(b);
       c = ((instruction >> 20) & 8'hFFFFF000) |
           ((instruction << 4) & 3'h800) |
           ((instruction >> 20) & 3'h7E0) |
           ((instruction >> 7) & 2'h1E);
     end else begin // format NOP
       inRegLock.Receive(regLock);
     end
    if (opFormat == 3 || opFormat == 2 || opFormat == 6) begin 
      outRegDaddr.Send(1);
    end else begin 
      outRegDaddr.Send(regD);
    end
  end
endmodule

// construct a program queue stage
//
// the stage is initiated to a bubble
module PrgQElement(interface inValid,
                   interface inXuSelector,
                   interface outValid,
                   interface outXuSelector);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] valid;
  logic [WIDTH-1:0] xuSelector;
  // initial begin 
  //   outValid.Send(255);
  //   outXuSelector.Send(0);
  // end
  always begin 
    inValid.Receive(valid);
    inXuSelector.Receive(xuSelector);
    outValid.Send(valid);
    outXuSelector.Send(xuSelector);

  end
endmodule

// Construct parameterisabled length program queue.
module ProgramQueue2(interface inValid,
                     interface inXuSelector,
                     interface outValid,
                     interface outXuSelector);
  Channel internalValid();
  Channel internalXuSelector();
  PrgQElement prgQElement1(inValid, inXuSelector, internalValid, internalXuSelector);
  PrgQElement prgQElement2(internalValid, internalXuSelector, outValid, outXuSelector);
endmodule

// This function constructs a register read port logical stage associated to a register file model.
//
// The constructed logic stage reads the address channel;
// if the address points register zero, the port writes the value zero on the data channel;
// otherwise it reads the content of register pointed by address and write to the data channel.
module RegBankRead(interface inRegAddr,
                   interface outData);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] addr;
  logic [WIDTH-1:0] registers [0:31];
  always begin 
    inRegAddr.Receive(addr);
    if (addr == 0) begin 
      outData.Send(0);
    end else begin 
      outData.Send(register[addr]);
    end
  end
endmodule

// This function constructs a register write port logical stage associated to a register file model.
//
// The Constructed logic stage first reads the data channel, then the address channel;
// if the address points to register zero, the data is discarded;
// otherwise it is written to the register pointed by address before reading the next data-address pair.
//
// It is important to notice that the if the data and address channels are written by the same logic stage
// they must be written in the order they are read, i.e. data first, address last, otherwise a deadlock occurs.
// This limitation is due to the way go operates on channels, real hardware or a more precise model would read both channels in parallel.
module RegBankWrite(interface inRegAddr,
                    interface inWe,
                    interface inData);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] registers [0:31];
  logic [WIDTH-1:0] regAddr;
  logic [WIDTH-1:0] we;
  logic [WIDTH-1:0] data;
  always begin 
    inWe.Receive(we);
    inData.Receive(data);
    inRegAddr.Receive(regAddr);
    if (addr > 31) begin 
      addr = 31;
    end
    if (we == 1 && addr != 0) begin 
      registers[addr] = data;
    end
  end
endmodule

// This function constructs a register lock queue logical stage element.
//
// The logical stage constructed reads a one-hot encoded register address,
// holds and outputs it to the two output channels.
//
// The first output channel is chained to the next stage or connected to the register write address output.
// The second output connects to a stage responsible for ORing the address and producing the lock mask.
module RegLockEl(interface inRegAddr,
                 interface outRegAddr,
                 interface outLock);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] regAddr;

  // initial begin 
  //   outRegAddr.Send(0);
  //   outLock.Send(0);
  // end

  always begin 
    inRegAddr.Receive(regAddr);
    outRegAddr.Send(regAddr);
    outLock.Send(regAddr);
  end
endmodule

// Constructs a variable length register lock queue and the mask generator logic element.
//
// The one-hot encoded destination register address is feed in the queue when the instruction is dispatched,
// the queue is the same depth as the instruction execution path.
// The register file write port or controller synchronises the destination address with the data.
// This imply that the register lock queue holds the destination register of all instructions dispatched
// that have not committed results to the register file.
//
// Each element of the queue have two output channels, one is chained to the next stage up to the output,
// the other channel is connected to the masking logic stage.
// The one-hot encoded address sent by each stage secondary channel are ORed by the masking logic stage,
// the output is the lockedRegs bitmask used by the operandFetch unit to identify locked register.
//
// It is important to notice that the lockedRegs channel must be read prior to any writes to the fifoIn channel.
// Otherwise a deadlock would occur as the queue has no bubbles to accommodate new tokens.
module RegisterLock4(interface inRegAddr,
                     interface outRegAddr,
                     interface outLockedRegs);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] in = 0;
  logic [WIDTH-1:0] out = 0;
  Channel internalRegAddr1();
  Channel internalRegAddr2();
  Channel internalRegAddr3();
  Channel internalLockedRegs1();
  Channel internalLockedRegs2();
  Channel internalLockedRegs3();
  Channel internalLockedRegs4();
  RegLockEl regLockEl1(inRegAddr, internalRegAddr1, internalLockedRegs1);
  RegLockEl regLockEl2(internalRegAddr1, internalRegAddr2, internalLockedRegs2);
  RegLockEl regLockEl3(internalRegAddr2, internalRegAddr3, internalLockedRegs3);
  RegLockEl regLockEl4(internalRegAddr3, outRegAddr, internalLockedRegs4);
  always begin 
    internalLockedRegs4.Receive(in);
    out = out | (in & 8'hFFFFFFFE);
    internalLockedRegs3.Receive(in);
    out = out | (in & 8'hFFFFFFFE);
    internalLockedRegs2.Receive(in);
    out = out | (in & 8'hFFFFFFFE);
    internalLockedRegs1.Receive(in);
    out = out | (in & 8'hFFFFFFFE);
    outLockedRegs.Send(out);
  end
endmodule

module Retire(interface inValid,
              interface inXuSelector,
              interface bypassOut,
              interface inAdder,
              interface inLogic,
              interface inShifter,
              interface inMemoryWriteRequest,
              interface inMemoryRead,
              interface inMemoryValue,
              interface inBranchLink,
              interface inBranchTaken,
              interface inBranchLinkAddr,
              interface inBranchTarget,
              interface outRegWe,
              interface outRegData,
              interface outMemoryWe,
              interface outBranch);
  Channel currValid();
  Channel nextValid();
  Channel nextBr();
  RetireStage1 retireStage1(outBranch, nextBr);
  RetireStage2 retireStage2(currValid, nextValid);
  RetireStage3 retireStage3(
    currValid,
    nextValid,
    nextBr,
    inValid,
    inXuSelector,
    bypassOut,
    inAdder,
    inLogic,
    inShifter,
    inMemoryWriteRequest,
    inMemoryRead,
    inMemoryValue,
    inBranchLink,
    inBranchTaken,
    inBranchLinkAddr,
    inBranchTarget,
    outRegWe,
    outRegData,
    outMemoryWe,
    outBranch);
endmodule

module RetireStage1(interface branchOut,
                    interface nextBr);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] data;
  always begin 
    nextBr.Receive(data);
    branchOut.Send(data);
  end
endmodule

module RetireStage2(interface currValid,
                    interface nextValid);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] valid;
  always begin 
    currValid.Send(valid);
    nextValid.Receive(valid);
  end
endmodule

module RetireStage3(interface currValid,
                    interface nextValid,
                    interface nextBr,
                    interface inValid,
                    interface inXuSelector,
                    interface bypassOut,
                    interface inAdder,
                    interface inLogic,
                    interface inShifter,
                    interface inMemoryWriteRequest,
                    interface inMemoryRead,
                    interface inMemoryValue,
                    interface inBranchLink,
                    interface inBranchTaken,
                    interface inBranchLinkAddr,
                    interface inBranchTarget,
                    interface outRegWe,
                    interface outRegData,
                    interface outMemoryWe,
                    interface outBranch);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] valid;
  logic [WIDTH-1:0] programValid;
  logic [WIDTH-1:0] programXuSelector;
  logic [WIDTH-1:0] data;
  logic [WIDTH-1:0] memoryRead;
  logic [WIDTH-1:0] rWe;
  logic [WIDTH-1:0] memWe;
  logic [WIDTH-1:0] brTaken;
  logic [WIDTH-1:0] brTarget;

  initial begin 
    nextValid.Send(0);
    outRegWe.Send(0);
    outRegData.Send(0);
  end

  always begin 
    inValid.Receive(programValid);
    inXuSelector.Receive(programXuSelector);
    currValid.Receive(valid);
    rWe = 1;
    memWe = 0;
    brTaken = 0;
    if (programXuSelector == 0) begin  // bypass sel
      bypassOut.Receive(data);
      inAdder.Receive(0);
      inLogic.Receive(0);
      inShifter.Receive(0);
      inMemoryWriteRequest.Receive(0);
      inMemoryRead.Receive(0);
      inMemoryValue.Receive(0);
      inBranchLink.Receive(0);
      inBranchTaken.Receive(0);
      inBranchLinkAddr.Receive(0);
      inBranchTarget.Receive(0);
    end else if (programXuSelector == 1) begin // adder sel 
      bypassOut.Receive(0);
      inAdder.Receive(data);
      inLogic.Receive(0);
      inShifter.Receive(0);
      inMemoryWriteRequest.Receive(0);
      inMemoryRead.Receive(0);
      inMemoryValue.Receive(0);
      inBranchLink.Receive(0);
      inBranchTaken.Receive(0);
      inBranchLinkAddr.Receive(0);
      inBranchTarget.Receive(0);
    end else if (programXuSelector == 2) begin // logic sel
      bypassOut.Receive(0);
      inAdder.Receive(0);
      inLogic.Receive(data);
      inShifter.Receive(0);
      inMemoryWriteRequest.Receive(0);
      inMemoryRead.Receive(0);
      inMemoryValue.Receive(0);
      inBranchLink.Receive(0);
      inBranchTaken.Receive(0);
      inBranchLinkAddr.Receive(0);
      inBranchTarget.Receive(0);
    end else if (programXuSelector == 3) begin // shifter sel
      bypassOut.Receive(0);
      inAdder.Receive(0);
      inLogic.Receive(0);
      inShifter.Receive(data);
      inMemoryWriteRequest.Receive(0);
      inMemoryRead.Receive(0);
      inMemoryValue.Receive(0);
      inBranchLink.Receive(0);
      inBranchTaken.Receive(0);
      inBranchLinkAddr.Receive(0);
      inBranchTarget.Receive(0);
    end else if (programXuSelector == 4) begin // memory sel
      bypassOut.Receive(0);
      inAdder.Receive(0);
      inLogic.Receive(0);
      inShifter.Receive(0);
      inMemoryWriteRequest.Receive(memWe);
      inMemoryRead.Receive(memoryRead);
      inMemoryValue.Receive(data);
      inBranchLink.Receive(0);
      inBranchTaken.Receive(0);
      inBranchLinkAddr.Receive(0);
      inBranchTarget.Receive(0);
    end else begin // branch sel
      bypassOut.Receive(0);
      inAdder.Receive(0);
      inLogic.Receive(0);
      inShifter.Receive(0);
      inMemoryWriteRequest.Receive(0);
      inMemoryRead.Receive(0);
      inMemoryValue.Receive(0);
      inBranchLink.Receive(rWe);
      inBranchTaken.Receive(brTaken);
      inBranchLinkAddr.Receive(data);
      inBranchTarget.Receive(brTarget);
    end
    if (valid != programValid) begin 
      brTaken = 0;
      rWe = 0;
      if (memWe == 1) begin 
        outMemoryWe.Send(0);
      end
    end else begin 
      if (memWe == 1) begin 
        outMemoryWe.Send(1);
      end
    end
    if (brTaken == 1) begin 
      nextValid.Send(valid + 1);
    end else begin 
      nextValid.Send(valid);
    end
    outRegWe.Send(rWe);
    outRegData.Send(data);
    if (brTaken == 1) begin 
      nextBr.Send(brTarget);
    end
  end
endmodule

// Constructs the shift execution unit logic stages
// This unit is used by SLL(I), SRL(I), SRA(I) instructions.
//
// The unit is two-stage long to match the the expected depth of execution units.
// Due to the simple logic, use of buffer may be carried to the silicon design.
module Shifter(interface inXuOp,
               interface inA,
               interface inB,
               interface outResult);
  Channel buffer();
  ShifterStage1 stage1(buffer, outResult);
  ShifterStage2 stage2(buffer, inXuOp, inA, inB);
endmodule

module ShifterStage1(interface buffer,
                     interface outResult);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] data = 0;
  always begin 
    buffer.Receive(data);
    outResult.Send(data);
  end
endmodule

module ShifterStage2(interface buffer,
                     interface inXuOp,
                     interface inA,
                     interface inB);
  parameter WIDTH = 32;
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic [WIDTH-1:0] xuOp;
  always begin 
    inA.Receive(a);
    inB.Receive(b);
    inXuOp.Receive(xuOp);
    if (xuOp == 12) begin // shifter Ll
      buffer.Send(a << (b & 2'h1F));
    end else if (xuOp == 13) begin  // shifter Rl
      buffer.Send(a >> (b & 2'h1F));
    end else begin // shifter Ra
      buffer.Send(a >> (b & 2'h1F));
    end
  end
endmodule

module FetchDecoder(interface brCmd,
  interface decoderPc,
  interface decoderValid,
  interface decoderInstruction,
  interface decoderRegA,
  interface decoderRegB,
  interface decoderRegD,
  interface decoderXuOp,
  interface outOpFormat);
  Channel instruction();
  Channel fetchValid();
  Channel fetchPcAddr();
  Fetch fetchUnit(
    brCmd,
    fetchPcAddr,
    instruction,
    fetchValid);
  Decoder decoderUnit(
    fetchValid,
    fetchPcAddr,
    instruction,
    decoderPc,
    decoderValid,
    decoderInstruction,
    decoderRegA,
    decoderRegB,
    decoderRegD,
    decoderXuOp,
    outOpFormat);
endmodule

module DispatcherBranch(
  interface dispatcherValid,
  interface dispatcherPcAddr,
  interface dispatcherXuOp,
  interface dispatcherA,
  interface dispatcherB,
  interface dispatcherC,
  interface ctrlQInValid,
  interface ctrlQInXuSelector,
  interface bypassIn,
  interface adderInA,
  interface adderInB,
  interface adderInXuOp,
  interface logicInA,
  interface logicInB,
  interface logicInXuOp,
  interface shifterInA,
  interface shifterInB,
  interface shifterInXuOp,
  interface memoryInA,
  interface memoryInB,
  interface memoryInC,
  interface memoryInXuOp,
  interface branchOutLink,
  interface branchOutTaken,
  interface branchOutLinkAddr,
  interface branchOutTarget
);
  Channel branchInA();
  Channel branchInB();
  Channel branchInC();
  Channel branchInPC();
  Channel branchInXuOp();
  Dispatcher dispatcher(
    dispatcherValid,
    dispatcherPcAddr,
    dispatcherXuOp,
    dispatcherA,
    dispatcherB,
    dispatcherC,
    ctrlQInValid,
    ctrlQInXuSelector,
    bypassIn,
    adderInA,
    adderInB,
    adderInXuOp,
    logicInA,
    logicInB,
    logicInXuOp,
    shifterInA,
    shifterInB,
    shifterInXuOp,
    memoryInA,
    memoryInB,
    memoryInC,
    memoryInXuOp,
    branchInA,
    branchInB,
    branchInC,
    branchInPC,
    branchInXuOp
  );
  Branch branchUnit(
    branchInA,
    branchInB,
    branchInC,
    branchInPC,
    branchInXuOp,
    branchOutLink,
    branchOutTaken,
    branchOutLinkAddr,
    branchOutTarget
  );
endmodule