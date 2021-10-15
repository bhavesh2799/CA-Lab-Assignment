// Floating Point Divider
module fpdiv(AbyB, DONE, EXCEPTION, InputA, InputB, CLOCK, RESET);
	input CLOCK, RESET; // Active High
	input [31:0] InputA, InputB;
	output [31:0] AbyB;
	output DONE;
	output [1:0] EXCEPTION;
	
	

endmodule

// Testbench
module tb_Divider;
	reg clk, reset;
	reg [31:0] a, b;
	wire [31:0] quotient;
	wire done;
	wire [1:0] exception;
	
	initial
		begin
		end
endmodule