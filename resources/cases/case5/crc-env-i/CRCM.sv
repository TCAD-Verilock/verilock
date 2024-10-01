module CRCM(interface data,
            interface count,
            interface result);
  Channel side(); 
  Monitor monitor(side); 
  // bug line, channels count and side are flipped
  CRC crc(data, side, count, result); 
endmodule

module CRC(interface data,
           interface count,
           interface side,
           interface result);       
  Channel command();
  FSM fsm(command, count);
  Compute c(command, data, result, side);
endmodule

module FSM(interface co,
           interface ct);
  always begin
    logic [7:0] len;
    co.Send(1);
    ct.Receive(len);
    while (len != 0) begin
      co.Send(2);
      len = len - 1;
    end
    co.Send(3);
  end
endmodule

module Monitor(interface side);
  logic complete;
  always begin
    side.Receive(complete);
    // omitted handler logic
  end
endmodule

module Compute(interface co,
               interface d,
               interface r,
               interface s);
  always begin
    logic [7:0] state, bits, origin, calc;
    co.Receive(state);
    if (state == 1) begin 
      calc = 0; 
    end else if (state == 2) begin
      d.Receive(bits);
      // omitted CRC computation logic
    end else begin
      d.Receive(origin);
      if (origin == calc) begin 
        fork
            r.Send(1); s.Send(1); 
        join
      end else begin
        fork
            r.Send(0); s.Send(0); 
        join
      end
    end
  end
endmodule