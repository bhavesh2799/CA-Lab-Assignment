module fpdiv(AbyB, DONE, EXCEPTION, InputA, InputB, CLOCK, RESET);

	input CLOCK, RESET; // Active High
	input [31:0] InputA, InputB;
	output [31:0] AbyB;
	output DONE;
	output reg [1:0] EXCEPTION;
	
	reg [31:0] ExSol;
	wire sign;
	wire [7:0] shift;
	wire [7:0] exponent_a;
	wire [31:0] divisor;
	wire [31:0] operand_a;
	wire [31:0] Intermediate_X0;
	wire [31:0] Iteration_X0;
	wire [31:0] Iteration_X1;
	wire [31:0] Iteration_X2;
	wire [31:0] Iteration_X3;
	wire [31:0] solution;

	wire [31:0] denominator;
	wire [31:0] operand_a_change;
	
	wire [9:0] sol_exponent;
	
	assign sign = InputA[31] ^ InputB[31];
	assign shift = 8'd126 - InputB[30:23];
	assign divisor = {1'b0,8'd126,InputB[22:0]};
	assign denominator = divisor;
	assign exponent_a = InputA[30:23] + shift;
	assign operand_a = {InputA[31],exponent_a,InputA[22:0]};
	assign operand_a_change = operand_a;
	assign sol_exponent = InputA[30:23] - InputB[30:23] + 8'd127;
	
	// Reciprocal Block: Newton-Raphson  Algorithm
	//32'hC00B_4B4B = (-37)/17
	Multiplication x0(32'hC00B_4B4B,divisor,,,,Intermediate_X0);

	//32'h4034_B4B5 = 48/17
	Addition_Subtraction X0(Intermediate_X0,32'h4034_B4B5,1'b0,,Iteration_X0);
	
	// The above part is to choose a better X(0), for which we need to minimize the absolute error in approximation
	// of 1/D, we do X(0) = 48/17 - (32/17)*D'. Where D' is the number scaled to between 0.5 and 1.

	Iteration X1(Iteration_X0,divisor,Iteration_X1);
	Iteration X2(Iteration_X1,divisor,Iteration_X2);
	Iteration X3(Iteration_X2,divisor,Iteration_X3);
	
	// Multiplication block with reciprocal

	Multiplication END(Iteration_X3,operand_a,,,,solution);

	assign AbyB = {sign,solution[30:0]};
	
	always @* 
	begin
		EXCEPTION = 2'bxx;
		// GIVE RESULTS FOR ALL!!!
		
		// 00: Divide Normal by Zero
		if ((0 < InputA[30:23] && 255 > InputA[30:23]) && InputB[31:0] == 32'h00000000) 
		begin
			EXCEPTION = 2'b00;
			ExSol = 32'h7f800000;
			// AbyB = ExSol;
		end
		// 11: Invalid Operands
		else if (((InputA[30:23] == 255) && (InputA[22:0] != 23'b0)) || ((InputB[30:23] == 255) && (InputB[22:0] != 23'b0))) // A NaN or B NaN (r= NaN)
			EXCEPTION = 2'b11;
		else if (((InputA[30:23] == 255) && (InputA[22:0] == 23'b0)) && ((InputB[30:23] == 255) && (InputB[22:0] == 23'b0))) // A Inf and B Inf (r= NaN)
			EXCEPTION = 2'b11;
		else if (((InputA[30:23] == 255) && (InputA[22:0] == 23'b0))) // A Inf and B normal
			begin
			if (InputB[31:0] == 32'h00000000) // B Zero (r= NaN)
				EXCEPTION = 2'b11;
			else // B normal (r= inf)
				EXCEPTION = 2'b11;
			end 
		else if (((InputB[30:23] == 255) && (InputB[22:0] == 23'b0))) // B Inf (r= Zero)
				EXCEPTION = 2'b11;
		else if ((InputA[31:0] == 32'h00000000) && (InputB[31:0] == 32'h00000000)) // A Zero and B Zero (r= NaN)
				EXCEPTION = 2'b11;
		// 10: Overflow		
		else if (sol_exponent > 9'd255) // Overflow
				EXCEPTION = 2'b10;
		// 01: Underflow
		else if (sol_exponent < 9'd0) // Subnormal Numbers
				EXCEPTION = 2'b01;
	end
	
	
	
endmodule


module Iteration(operand_1,operand_2,solution);

	input [31:0] operand_1;
	input [31:0] operand_2;
	output [31:0] solution;
	
	/// THIS Module is to implement the newton-raphson iteration: X(i+1) = X(i)*(2-DX(i))

	wire [31:0] Intermediate_Value1,Intermediate_Value2;
	Multiplication M1(operand_1,operand_2,,,,Intermediate_Value1);

	//32'h4000_0000 -> 2.
	Addition_Subtraction A1(32'h4000_0000,{1'b1,Intermediate_Value1[30:0]},1'b0,,Intermediate_Value2);
	Multiplication M2(operand_1,Intermediate_Value2,,,,solution);

endmodule

module Addition_Subtraction(a_operand,b_operand,AddBar_Sub,Exception,result);

	// ADD:0, SUB: 1
	input [31:0] a_operand,b_operand;
	input AddBar_Sub;			  
	output Exception;
	output [31:0] result; 
	
	wire operation_sub_addBar;
	wire Comp_enable;
	wire output_sign;

	wire [31:0] operand_a,operand_b;
	wire [23:0] significand_a,significand_b;
	wire [7:0] exponent_diff;


	wire [23:0] significand_b_add_sub;
	wire [7:0] exponent_b_add_sub;

	wire [24:0] significand_add;
	wire [30:0] add_sum;

	wire [23:0] significand_sub_complement;
	wire [24:0] significand_sub;
	wire [30:0] sub_diff;
	wire [24:0] subtraction_diff; 
	wire [7:0] exponent_sub;

	//for operations always operand_a must not be less than operand_b.
	assign {Comp_enable,operand_a,operand_b} = (a_operand[30:0] < b_operand[30:0]) ? {1'b1,b_operand,a_operand} : {1'b0,a_operand,b_operand};

	assign exp_a = operand_a[30:23];
	assign exp_b = operand_b[30:23];

	// [CHECK!!]: Refactoring Exception flag sets 1 if either one of the exponent is 255.
	assign Exception = (&operand_a[30:23]) | (&operand_b[30:23]);
	assign output_sign = AddBar_Sub ? Comp_enable ? !operand_a[31] : operand_a[31] : operand_a[31] ;
	assign operation_sub_addBar = AddBar_Sub ? operand_a[31] ^ operand_b[31] : ~(operand_a[31] ^ operand_b[31]);

	//Assigining significand values according to Hidden Bit == Significand Bit
	//If exponent is equal to zero then hidden bit will be 0 for that respective significand else it will be 1
	assign significand_a = (|operand_a[30:23]) ? {1'b1,operand_a[22:0]} : {1'b0,operand_a[22:0]};
	assign significand_b = (|operand_b[30:23]) ? {1'b1,operand_b[22:0]} : {1'b0,operand_b[22:0]};

	//Evaluating Exponent Difference
	assign exponent_diff = operand_a[30:23] - operand_b[30:23];

	//Shifting significand_b according to exponent_diff: pperand_b is smaller.
	assign significand_b_add_sub = significand_b >> exponent_diff;

	assign exponent_b_add_sub = operand_b[30:23] + exponent_diff; 

	//Checking exponents are same or not
	assign perform = (operand_a[30:23] == exponent_b_add_sub);

	// ADD Operation
	assign significand_add = (perform & operation_sub_addBar) ? (significand_a + significand_b_add_sub) : 25'd0; 
	//Result will be equal to Most 23 bits if carry generates else it will be Least 22 bits.
	assign add_sum[22:0] = significand_add[24] ? significand_add[23:1] : significand_add[22:0];

	//If carry generates in sum value then exponent must be added with 1 else feed as it is.
	assign add_sum[30:23] = significand_add[24] ? (1'b1 + operand_a[30:23]) : operand_a[30:23];

	// Subtraction Block

	assign significand_sub_complement = (perform & !operation_sub_addBar) ? ~(significand_b_add_sub) + 24'd1 : 24'd0 ; 
	assign significand_sub = perform ? (significand_a + significand_sub_complement) : 25'd0;
	priority_encoder pe(significand_sub,operand_a[30:23],subtraction_diff,exponent_sub);
	assign sub_diff[30:23] = exponent_sub;
	assign sub_diff[22:0] = subtraction_diff[22:0];

	// [CHECK FOR Exception]Final output, evaluate under noexception
	
	assign result = Exception ? 32'b0 : ((!operation_sub_addBar) ? {output_sign,sub_diff} : {output_sign,add_sum});

endmodule

module Multiplication(a_operand, b_operand, Exception, Overflow, Underflow, result);

	input [31:0] a_operand;
	input [31:0] b_operand;
	output Exception,Overflow,Underflow;
	output [31:0] result;
	
	wire sign,product_round,normalised,zero;
	wire [8:0] exponent,sum_exponent;
	wire [22:0] product_mantissa;
	wire [23:0] operand_a,operand_b;
	//48 Bits = 24 bits + 24 bits
	// As it's 1.Mantissa
	wire [47:0] product,product_normalised; 


	assign sign = a_operand[31] ^ b_operand[31];

	//Exception flag sets 1 if either one of the exponent is 255.
	assign Exception = (&a_operand[30:23]) | (&b_operand[30:23]);

	//Assigining significand values according to Hidden Bit.
	//If exponent is equal to zero then hidden bit will be 0 for that respective significand else it will be 1

	assign operand_a = (|a_operand[30:23]) ? {1'b1,a_operand[22:0]} : {1'b0,a_operand[22:0]};
	assign operand_b = (|b_operand[30:23]) ? {1'b1,b_operand[22:0]} : {1'b0,b_operand[22:0]};
	assign product = operand_a * operand_b;			//Calculating Product
	assign product_round = |product_normalised[22:0];  //Ending 22 bits are OR'ed for rounding operation.
	assign normalised = product[47] ? 1'b1 : 1'b0;	
	assign product_normalised = normalised ? product : product << 1;	//Assigning Normalised value based on 48th bit

	//Final Manitssa.
	assign product_mantissa = product_normalised[46:24] + {21'b0,(product_normalised[23] & product_round)};
	assign zero = Exception ? 1'b0 : (product_mantissa == 23'd0) ? 1'b1 : 1'b0;
	assign sum_exponent = a_operand[30:23] + b_operand[30:23];
	assign exponent = sum_exponent - 8'd127 + normalised;

	assign Overflow = ((exponent[8] & !exponent[7]) & !zero) ; //If overall exponent is greater than 255 then Overflow condition.
	//Exception Case when exponent reaches its maximu value that is 384.

	//If sum of both exponents is less than 127 then Underflow condition.
	assign Underflow = ((exponent[8] & exponent[7]) & !zero) ? 1'b1 : 1'b0; 

	assign result = Exception ? 32'd0 : zero ? {sign,31'd0} : Overflow ? {sign,8'hFF,23'd0} : Underflow ? {sign,31'd0} : {sign,exponent[7:0],product_mantissa};


endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module priority_encoder(
			input [24:0] significand,
			input [7:0] Exponent_a,
			output reg [24:0] Significand,
			output [7:0] Exponent_sub
			);

reg [4:0] shift;

always @(significand)
begin
	casex (significand)
		25'b1_1xxx_xxxx_xxxx_xxxx_xxxx_xxxx :	begin
													Significand = significand;
									 				shift = 5'd0;
								 			  	end
		25'b1_01xx_xxxx_xxxx_xxxx_xxxx_xxxx : 	begin						
										 			Significand = significand << 1;
									 				shift = 5'd1;
								 			  	end

		25'b1_001x_xxxx_xxxx_xxxx_xxxx_xxxx : 	begin						
										 			Significand = significand << 2;
									 				shift = 5'd2;
								 				end

		25'b1_0001_xxxx_xxxx_xxxx_xxxx_xxxx : 	begin 							
													Significand = significand << 3;
								 	 				shift = 5'd3;
								 				end

		25'b1_0000_1xxx_xxxx_xxxx_xxxx_xxxx : 	begin						
									 				Significand = significand << 4;
								 	 				shift = 5'd4;
								 				end

		25'b1_0000_01xx_xxxx_xxxx_xxxx_xxxx : 	begin						
									 				Significand = significand << 5;
								 	 				shift = 5'd5;
								 				end

		25'b1_0000_001x_xxxx_xxxx_xxxx_xxxx : 	begin						// 24'h020000
									 				Significand = significand << 6;
								 	 				shift = 5'd6;
								 				end

		25'b1_0000_0001_xxxx_xxxx_xxxx_xxxx : 	begin						// 24'h010000
									 				Significand = significand << 7;
								 	 				shift = 5'd7;
								 				end

		25'b1_0000_0000_1xxx_xxxx_xxxx_xxxx : 	begin						// 24'h008000
									 				Significand = significand << 8;
								 	 				shift = 5'd8;
								 				end

		25'b1_0000_0000_01xx_xxxx_xxxx_xxxx : 	begin						// 24'h004000
									 				Significand = significand << 9;
								 	 				shift = 5'd9;
								 				end

		25'b1_0000_0000_001x_xxxx_xxxx_xxxx : 	begin						// 24'h002000
									 				Significand = significand << 10;
								 	 				shift = 5'd10;
								 				end

		25'b1_0000_0000_0001_xxxx_xxxx_xxxx : 	begin						// 24'h001000
									 				Significand = significand << 11;
								 	 				shift = 5'd11;
								 				end

		25'b1_0000_0000_0000_1xxx_xxxx_xxxx : 	begin						// 24'h000800
									 				Significand = significand << 12;
								 	 				shift = 5'd12;
								 				end

		25'b1_0000_0000_0000_01xx_xxxx_xxxx : 	begin						// 24'h000400
									 				Significand = significand << 13;
								 	 				shift = 5'd13;
								 				end

		25'b1_0000_0000_0000_001x_xxxx_xxxx : 	begin						// 24'h000200
									 				Significand = significand << 14;
								 	 				shift = 5'd14;
								 				end

		25'b1_0000_0000_0000_0001_xxxx_xxxx  : 	begin						// 24'h000100
									 				Significand = significand << 15;
								 	 				shift = 5'd15;
								 				end

		25'b1_0000_0000_0000_0000_1xxx_xxxx : 	begin						// 24'h000080
									 				Significand = significand << 16;
								 	 				shift = 5'd16;
								 				end

		25'b1_0000_0000_0000_0000_01xx_xxxx : 	begin						// 24'h000040
											 		Significand = significand << 17;
										 	 		shift = 5'd17;
												end

		25'b1_0000_0000_0000_0000_001x_xxxx : 	begin						// 24'h000020
									 				Significand = significand << 18;
								 	 				shift = 5'd18;
								 				end

		25'b1_0000_0000_0000_0000_0001_xxxx : 	begin						// 24'h000010
									 				Significand = significand << 19;
								 	 				shift = 5'd19;
												end

		25'b1_0000_0000_0000_0000_0000_1xxx :	begin						// 24'h000008
									 				Significand = significand << 20;
								 					shift = 5'd20;
								 				end

		25'b1_0000_0000_0000_0000_0000_01xx : 	begin						// 24'h000004
									 				Significand = significand << 21;
								 	 				shift = 5'd21;
								 				end

		25'b1_0000_0000_0000_0000_0000_001x : 	begin						// 24'h000002
									 				Significand = significand << 22;
								 	 				shift = 5'd22;
								 				end

		25'b1_0000_0000_0000_0000_0000_0001 : 	begin						// 24'h000001
									 				Significand = significand << 23;
								 	 				shift = 5'd23;
								 				end

		25'b1_0000_0000_0000_0000_0000_0000 : 	begin						// 24'h000000
								 					Significand = significand << 24;
							 	 					shift = 5'd24;
								 				end
		default : 	begin
						Significand = (~significand) + 1'b1;
						shift = 8'd0;
					end

	endcase
end
assign Exponent_sub = Exponent_a - shift;

endmodule


// TESTBENCH!!! 


module tb_fp_div();
	 initial begin
	 $display ("The Group Members are:");
	 $display ("********************************************");
	 $display ("2019A7PS0077P Aadit Deshpande");
	 $display ("2019A7PS0123P Lakshya");
	 $display ("2018B2A70699P Minu Rajeeve Payyapilly");
	 $display ("2018B1A70657P Niharika Gupta");
	 $display ("********************************************");
	 end

	 initial begin
	 $display ("A few thigs about our design:");
	 $display ("********************************************");
	 $display ("It works on the Positive edge of the CLOCK signal");
	 $display ("Will take 25 CLOCK cycles to complete the execution");
	 $display ("We haven't used the guard bits");
	 $display ("********************************************");
	 end
 	reg clk = 0;
	reg [31:0] a_operand;
	reg [31:0] b_operand;
	
	wire [31:0] result;
	wire [1:0] Exception;

	reg [31:0] Expected_result;
	// module fpdiv(AbyB, DONE, EXCEPTION, InputA, InputB, CLOCK, RESET);
	fpdiv my_div(result,,Exception,a_operand, b_operand, clk,);

	always #5 clk = ~clk;


	always@(*)
		$monitor($time,"A = %h, B = %h, A/b = %h, Exception = %b Expected Result = %h",a_operand, b_operand, result, Exception, Expected_result);
	always @(posedge clk) 
	begin
	
	// For Reference:
	// 00000000: 0
	// 7f800000: +Infinity
	// ff800000: -Infinity
	// 7fc00000: NaN
	
			#6 $display("Case 1: Normal");
			#6 a_operand = 32'h40a00000; b_operand = 32'h40000000; Expected_result = 32'h40200000;// 5 / 2 = 2.5
			
			#6 $display("Case 2: Divide by Zero");
			#6 a_operand = 32'h40000000; b_operand = 32'h00000000; Expected_result = 32'h7f800000;// 2 / Zero = Infinity
			
			#6 $display("Case 3: Invalid Operands");
			#6 a_operand = 32'h7fc00000; b_operand = 32'h7fc00000; Expected_result = 32'h7fc00000;// NaN / NaN = NaN
			#6 a_operand = 32'h7f800000; b_operand = 32'h7f800000; Expected_result = 32'h7fc00000;// Inf / Inf = NaN
			#6 a_operand = 32'h7f800000; b_operand = 32'h00000000; Expected_result = 32'h7fc00000;// Inf / Zero = NaN
			#6 a_operand = 32'h7f800000; b_operand = 32'h40000000; Expected_result = 32'h7fc00000;// Inf / 2 = Inf
			#6 a_operand = 32'h40000000; b_operand = 32'h7f800000; Expected_result = 32'h00000000;//  2 / Inf = Zero
			#6 a_operand = 32'h00000000; b_operand = 32'h00000000; Expected_result = 32'h7fc00000;// Zero / Zero = NaN
			
			
			#6 $display("Case 3: Overflow or Underflow");			
			#6 a_operand = 32'h00195400; b_operand = 32'h7f7fffff; Expected_result = 32'h7f800000;// Smallest Positive Subnormal / 2 ~ Zero [Underflow]
			#6 a_operand = 32'h7f7fffff; b_operand = 32'h00195400; Expected_result = 32'h7f800000;// Largest Positive Normal / Smallest Positive Normal ~ Inf [Overflow]
			
			
			
			# 60 $finish;

			
			
	end


endmodule
