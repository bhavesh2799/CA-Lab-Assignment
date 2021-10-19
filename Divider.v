// Floating Point Divider
module fpdiv(AbyB, DONE, EXCEPTION, InputA, InputB, CLOCK, RESET);
	input CLOCK, RESET; // Active High
	input [31:0] InputA, InputB;
	output [31:0] AbyB;
	output DONE;
	output [1:0] EXCEPTION;
	
	wire [31:0] O;
	assign AbyB = O;
	
	wire [7:0] a_exponent;
	wire [23:0] a_mantissa;
	wire [7:0] b_exponent;
	wire [23:0] b_mantissa;
	
	reg o_sign;
	reg [7:0] o_exponent;
	reg [24:0] o_mantissa;
	
	reg [31:0] divider_a_in;
	reg [31:0] divider_b_in;
	wire[31:0] divider_out;
	
	reg [1:0] exception
	assign EXCEPTION = exception;
	
	wire [1:0] overflow_undeflow; // 00 normal operation, 01 underflow, 10 overflow 
	
	assign a_sign = InputA[31];
	assign a_exponent[7:0] = InputA[30:23];
	assign a_mantissa[23:0] = {1'b1, InputA[22:0]};
	
	assign b_sign = InputB[31];
	assign b_exponent[7:0] = InputB[30:23];
	assign b_mantissa[7:0] = {1'b1, InputB[22:0]};
	
	assign O[31] = o_sign;
	assign O[30:23] = o_exponent;
	assign O[22:0] = o_mantissa[22:0];
	
	divider D1
	(
		.a(divider_a_in),
		.b(divider_b_in),
		.out(divider_out),
		.of_uf(overflow_undeflow)
	);
	
	always @(posedge clk or posedge RESET) begin
		if(RESET) begin
			done = 0;
			divider_out = 32'b0;
			
		end else begin
			if(done == 0)  begin
				if((b_exponent == 0) && (b_mantissa == 0)) begin
					exception = 2'b00; // Divide by zero
				end else if ((a_exponent == 255 && a_mantissa != 0) || (b_exponent == 255 && b_mantissa != 0)) begin
					exception = 2'b11; // A or B are NaN
				end else if ((a_exponent == 255 ) || (b_exponent == 255)) begin
					exception = 2'b11; // Operands are infinity
				end else if ((overflow_undeflow != 2'b00)) begin
					exception = overflow_undeflow;
				end else begin
					divider_a_in = InputA;
					divider_b_in = InputB;
					o_sign = divider_out[31];
					o_exponent = divider_out[30:23];
					o_mantissa = divider_out[22:0];
				end
				done = 1;
			end
		end
	end

endmodule

module divider(a, b, out, of_uf);
	input [31:0] a;
	input [31:0] b;
	output [31:0] out;
	output [1:0] of_uf;
	
	wire [31:0] b_reciprocal;
	wire [1:0] reciprocal_of_uf;
	wire [1:0] mult_of_uf;
	reg [1:0] of_uf;
	
	reciprocal recip
	(
		.in(b),
		.out(b_reciprocal),
		.of_uf(reciprocal_of_uf)
	);
	
	multiplier mult
	(
		.a(a),
		.b(b_reciprocal),
		.out(out),
		.of_uf(mult_of_uf)
	);
	
	always @(*) begin
		if(reciprocal_of_uf != 2'b00) begin
			of_uf = reciprocal_of_uf;
		end else if(mult_of_uf != 2'b00) begin
			of_uf = mult_of_uf;
		end else begin
			of_uf = 2'b00;
		end
	end
endmodule

module reciprocal(in, out, of_uf);
	// implementing Newton-Raphson as learnt from Wikipedia
	input [31:0] in;
	output [31:0] out;
	output [1:0] of_uf;
	
	reg [1:0] of_uf;
	
	wire [31:0] D;
	assign D = {1'b0, 8'h80, in[22:0]};
	
	wire [31:0] C1;
	assign C1 = 32'h4034B4B5; // gives 48/17
	wire [31:0] C2; 
	assign C2 = 32'h3FF0F0F1; // gives 32/17
	wire [31:0] C3;
	assign C3 = 32'h40000000; // gives 2.0
	
	wire [31:0] N0;
	wire [31:0] N1;
	wire [31:0] N2;
	
	assign out[31] = in[31];
	assign out[22:0] = N2[22:0];
	assign out[30:23] = (D==9'b100000000) ? 9'h102 - in[30:23] : 9'h101 - in[30:23];
	
	// now we have temporaray wires
	wire [31:0] S0_2D_out;
	wire [31:0] S1_DN0_out;
	wire [31:0] S1_2min_DN0_out;
	wire [31:0] S2_DN1_out;
	wire [31:0] S2_2minDN1_out;
	
	wire [31:0] S0_N0_in;
	
	wire [1:0] mult_S0_of_uf;
	wire [1:0] add_S0_of_uf;
	wire [1:0] mult1_S1_of_uf;
	wire [1:0] mult2_S1_of_uf;
	wire [1:0] add_S1_of_uf;
	wire [1:0] mult1_S2_of_uf;
	wire [1:0] mult2_S2_of_uf;
	wire [1:0] add_S2_of_uf;
	
	
	assign S0_N0_in = {~S0_2D_out[31]. S0_2D_out[30:0]};
	
	//S0 
	multiplier S0_2D 
	(
		.a(C2),
		.b(D),
		.out(S0_2D_out),
		.of_uf(mult_S0_of_uf)
	);
	
	adder S0_N0 
	(
		.a(C1),
		.b(S0_N0_in),
		.out(N0),
		.of_uf(add_S0_of_uf)
	);
	
	//S1
	multiplier S1_DN0 
	(
		.a(D),
		.b(N0),
		.out(S1_DN0_out),
		.of_uf(mult1_S1_of_uf)
	);
	adder S1_2minDN0
	(
		.a(C3),
		.b({~S1_DN0_out[31], S1_DN0_out[30:0]}),
		.out(S1_2min_DN0_out),
		.of_uf(add_S1_of_uf)
	);
	multiplier S1_N1
	(
		.a(N0),
		.b(S1_2min_DN0_out),
		.out(N1),
		.of_uf(mult2_S1_of_uf)
	);
	
	//S2 
	multiplier S2_DN1 
	(
		.a(D),
		.b(N1),
		.out(S2_DN1_out),
		.of_uf(mult1_S2_of_uf)
	);
	adder S2_2minDN1 
	(
		.a(C3),
		.b({~S2_DN1_out[31], S2_DN1_out[30:0]}),
		.out(S2_2minDN1_out),
		.of_uf(add_S2_of_uf)
	);
	multiplier S2_N2
	(
		.a(N1),
		.b(S2_2minDN1_out),
		.out(N2),
		.of_uf(mult2_S2_of_uf)
	);
	always @(*) begin
		if(mult_S0_of_uf != 2'b00) begin
			of_uf = mult_S0_of_uf;
		end else if(add_S0_of_uf != 2'b00) begin
			of_uf = add_S0_of_uf;
		end else if(mult1_S1_of_uf != 2'b00) begin
			of_uf = mult1_S1_of_uf;
		end else if(add_S1_of_uf != 2'b00) begin
			of_uf = add_S1_of_uf;
		end else if(mult2_S1_of_uf != 2'b00) begin
			of_uf = mult2_S1_of_uf;
		end else if(mult1_S2_of_uf != 2'b00) begin
			of_uf = mult1_S2_of_uf;
		end else if(add_S2_of_uf != 2'b00) begin
			of_uf = add_S2_of_uf;
		end else if(mult2_S2_of_uf != 2'b00) begin
			of_uf = mult2_S2_of_uf;
		end else begin
			of_uf = 2'b00;
		end
	end
endmodule

module multiplier(a, b, out, of_uf);
	input [31:0] a,b;
	output [31:0] out;
	output [1:0] of_uf;
	
	reg [1:0] of_uf;
	
	reg a_sign;
	reg [7:0] a_exponent;
	reg [23:0] a_mantissa;
	reg b_sign;
	reg [7:0] b_exponent;
	reg [23:0] b_mantissa;
	
	wire[31:0] out;
	reg o_sign;
	reg [7:0] o_exponent;
	reg [24:0] o_mantissa;
	
	reg [47:0] product; // m bits x nb = (m+n) bits
	
	assign out[31] = o_sign;
	assign out[30:23] = o_exponent;
	assign out[22:0] = o_mantissa[22:0];
	
	reg [7:0] i_e;
	reg [24:0] i_m; // similarly
	reg [7:0] o_e;
	reg [24:0] o_m;
	
	multiplication_normalizer norm1
	(
		.in_e(i_e),
		.in_m(i_m),
		.out_e(o_e),
		.out_m(o_m)
	);
	
	always @(*) begin
		a_sign = a[31];
		if(a[30:23] == 0) begin
			a_exponent = 8'b00000001;
			a_mantissa = {1'b0, a[22:0]};
		end else begin
			a_exponent = a[30:23];
			a_mantissa = {1'b1, a[22:0]);
		end
		
		b_sign = b[31];
		if(b[30:23] == 0) begin
			b_exponent = 8'b00000001;
			b_mantissa = {1'b0, b[22:0]};
		end else begin
			b_exponent = b[30:23];
			b_mantissa = {1'b1, b[22:0]);
		end
		o_sign = a_sign ^ b_sign; // XOR
		o_exponent = a_exponent + b_exponent - 127;
		if(o_exponent > 255) begin
			of_uf = 2'b10;
		end else if(o_exponent < 0) begin
			of_uf = 2'b01;
		end else begin
			of_uf =2'b00;
			product = a_mantissa*b_mantissa;
		
			if(product[47] == 1) begin
				o_exponent = o_exponent + 1;
				product = product >> 1;
			end else if ((product[46]!=1) && (o_exponent != 0)) begin
				i_e = o_exponent;
				i_m = product;
				o_exponent = o_e;
				o_mantissa = o_m;
			end

			o_mantissa = product[46:23];
		end
		
	end
endmodule


module multiplication_normalizer(in_e, in_m, out_e, out_m);
	input [7:0] in_e;
	input [47:0] in_m;
	output [7:0] out_e;
	output [47:0] out_m;
	
	wire [7:0] in_e;
	wire [47:0] in_m;
	reg [7:0] out_e;
	reg [47:0] out_m;
	
	always @(*) begin
		if(in_m[46:41] == 6'b000001) begin
			out_e = in_e - 5;
			out_m = in_m << 5;
		end else if (in_m[46:42] == 5'b00001) begin
			out_e = in_e - 4;
			out_m = in_m << 4;
		end else if(in_m[46:43] == 4'b0001) begin
			out_e = in_e - 3;
			out_m = in_m << 3;
		end else if(in_m[46:44] == 3'b001) begin
			out_e = in_e - 2;
			out_m = in_m << 2;
		end else if(in_m[46:45] == 2'b01) begin
			out_e = in_e - 1;
			out_m = in_m << 1;
		end
	end
endmodule

module adder(a, b, out, of_uf);
	input [31:0] a, b;
	output [31:0] out;
	output [1:0] of_uf;
	
	reg [1:0] of_uf;
	
	reg a_sign;
	reg [7:0] a_exponent;
	reg [23:0] a_mantissa;
	reg b_sign;
	reg [7:0] b_exponent;
	reg [23:0] b_mantissa;
	
	wire [31:0] out;
	reg o_sign;
	reg [7:0] o_exponent;
	reg [24:0] o_mantissa; // notce length 25 - for 1.
	
	reg [7:0] diff;
	reg [23:0] tmp_mantissa;
	reg [7:0] tmp_exponent;
	
	reg [7:0] i_e;
	reg [24:0] i_m; // similarly
	reg [7:0] o_e;
	reg [24:0] o_m; // similarly
	
	addition_normalizer norm1
	(
		.in_e(i_e),
		.in_m(i_m),
		.out_e(o_e),
		.out_m(o_m)
	);
	
	assign out[31] = o_sign;
	assign out[30:23] = o_exponent;
	assign out[22:0] = o_mantissa[22:0];
	
	always @(*) begin
	
		a_sign = a[31];
		if(a[30:23] == 0) begin
			a_exponent = 8'b00000001;
			a_mantissa = {1'b0, a[22:0]}; // Subnormal number
		end else begin
			a_exponent = a[30:23];
			a_mantissa = {1'b1, a[22:0]};
		end
		b_sign = b[31];
		if(b[30:23] == 0) begin
			b_exponent = 8'b00000001;
			b_mantissa = {1'b0, b[22:0]};
		end else begin
			b_exponent = b[30:23];
			b_mantissa = {1'b1, b[22:0]};
		end
		
		if( a_exponent == b_exponent) begin
			o_exponent = a_exponent;
			if(a_sign == b_sign) begin
				o_mantissa = a_mantissa + b_mantissa;
				o_mantissa[24] = 1;
				o_sign = a_sign;
			end else begin // subtraction
				if(a_mantissa > b_mantissa) begin
					o_mantissa = a_mantissa - b_mantissa;
					o_sign = a_sign;
				end else begin
					o_mantissa = b_mantissa - a_mantissa;
					o_sign = b_sign;
				end
			end
		end else begin // Unequal exp
			if (a_exponent > b_exponent) begin
				o_exponent = a_exponent;
				o_sign = a_sign;
				diff = a_exponent - b_exponent;
				tmp_mantissa = b_mantissa >> diff;
				if (a_sign == b_sign)
					o_mantissa = a_mantissa + tmp_mantissa;
				else
					o_mantissa = a_mantissa - tmp_mantissa;
			end else if (a_exponent < b_exponent) begin
				o_exponent = b_exponent;
				o_sign = b_sign;
				diff = b_exponent - a_exponent;
				tmp_mantissa = a_mantissa >> diff; 
				if (a_sign == b_sign) 
					o_mantissa = b_mantissa +tmp_mantissa;
				else 
					o_mantissa = b_mantissa - tmp_mantissa;
			end
		end
		if(o_mantissa[24] == 1) begin
			o_exponent = o_exponent +1;
			o_mantissa = o_mantissa >> 1;
		end else if((o_mantissa[23] != 1) && (o_exponent != 0)) begin
			i_e = o_exponent;
			i_m = o_mantissa;
			o_exponent = o_e;
			o_mantissa = o_m;
		end
		
		if(o_exponent > 255) begin
			of_uf = 2'b10;
		end else if(o_exponent < 0) begin
			of_uf = 2'b01;
		end else begin
			of_uf =2'b00;
		end
	end
endmodule

module addition_normalizer(in_e, in_m, out_e, out_m);
	input [7:0] in_e;
	input [24:0] in_m;
	output [7:0] out_e;
	output [24:0] out_m;

	wire [7:0] in_e;
	wire [24:0] in_m;
	reg [7:0] out_e;
	reg [24:0] out_m;
	
	always @ ( * ) begin
		if (in_m[23:3] == 21'b000000000000000000001) begin
			out_e = in_e - 20;
			out_m = in_m << 20;
		end else if (in_m[23:4] == 20'b00000000000000000001) begin
			out_e = in_e - 19;
			out_m = in_m << 19;
		end else if (in_m[23:5] == 19'b0000000000000000001) begin
			out_e = in_e - 18;
			out_m = in_m << 18;
		end else if (in_m[23:6] == 18'b000000000000000001) begin
			out_e = in_e - 17;
			out_m = in_m << 17;
		end else if (in_m[23:7] == 17'b00000000000000001) begin
			out_e = in_e - 16;
			out_m = in_m << 16;
		end else if (in_m[23:8] == 16'b0000000000000001) begin
			out_e = in_e - 15;
			out_m = in_m << 15;
		end else if (in_m[23:9] == 15'b000000000000001) begin
			out_e = in_e - 14;
			out_m = in_m << 14;
		end else if (in_m[23:10] == 14'b00000000000001) begin
			out_e = in_e - 13;
			out_m = in_m << 13;
		end else if (in_m[23:11] == 13'b0000000000001) begin
			out_e = in_e - 12;
			out_m = in_m << 12;
		end else if (in_m[23:12] == 12'b000000000001) begin
			out_e = in_e - 11;
			out_m = in_m << 11;
		end else if (in_m[23:13] == 11'b00000000001) begin
			out_e = in_e - 10;
			out_m = in_m << 10;
		end else if (in_m[23:14] == 10'b0000000001) begin
			out_e = in_e - 9;
			out_m = in_m << 9;
		end else if (in_m[23:15] == 9'b000000001) begin
			out_e = in_e - 8;
			out_m = in_m << 8;
		end else if (in_m[23:16] == 8'b00000001) begin
			out_e = in_e - 7;
			out_m = in_m << 7;
		end else if (in_m[23:17] == 7'b0000001) begin
			out_e = in_e - 6;
			out_m = in_m << 6;
		end else if (in_m[23:18] == 6'b000001) begin
			out_e = in_e - 5;
			out_m = in_m << 5;
		end else if (in_m[23:19] == 5'b00001) begin
			out_e = in_e - 4;
			out_m = in_m << 4;
		end else if (in_m[23:20] == 4'b0001) begin
			out_e = in_e - 3;
			out_m = in_m << 3;
		end else if (in_m[23:21] == 3'b001) begin
			out_e = in_e - 2;
			out_m = in_m << 2;
		end else if (in_m[23:22] == 2'b01) begin
			out_e = in_e - 1;
			out_m = in_m << 1;
		end
	end
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
