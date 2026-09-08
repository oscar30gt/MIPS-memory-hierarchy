----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    12:10:07 04/01/2026 
-- Design Name: 
-- Module Name:    ALU - Behavioral with support for vectorial MAC with internal accumulation
-- Additional Comments: by AOC2 Team Unizar 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;



entity ALU_Vector_MAC is
    Port ( DA : in  STD_LOGIC_VECTOR (31 downto 0); --input 1
           DB : in  STD_LOGIC_VECTOR (31 downto 0); --input 2
           valid_I_EX : in  STD_LOGIC;
           clk : in  STD_LOGIC;
		   reset : in  STD_LOGIC;
		   cancel_mac : in  STD_LOGIC; --abort current multicycle MAC without clearing ACC
		   ready : out STD_LOGIC; --initially is always '1', but if ALU supports multicycle ops, it will be cero when the output is not ready
           ALUctrl : in  STD_LOGIC_VECTOR (2 downto 0); -- Ops: "000" add, "001" sub, "010" AND, "011" OR, "100" MAC with internal acc, "101" MAC without previous acc.
           Dout : out  STD_LOGIC_VECTOR (31 downto 0)); -- Output
end ALU_Vector_MAC;

architecture Behavioral of ALU_Vector_MAC is

component reg is
    generic (size: natural := 32);  -- por defecto son de 32 bits, pero se puede usar cualquier tama�o
	Port ( Din : in  STD_LOGIC_VECTOR (size -1 downto 0);
           clk : in  STD_LOGIC;
		   reset : in  STD_LOGIC;
           load : in  STD_LOGIC;
           Dout : out  STD_LOGIC_VECTOR (size -1 downto 0));
end component;

signal Dout_internal: STD_LOGIC_VECTOR (31 downto 0);
signal ACC_out : STD_LOGIC_VECTOR (31 downto 0) := X"00000000";
signal ACC_input: Signed (31 downto 0) := (others => '0');
signal load_acc, Acc_op, MAC_start, mac_start_req : STD_LOGIC;
signal sum_total_ext: Signed (31 downto 0);
signal prod0_reg, prod1_reg, prod2_reg, prod3_reg : Signed(15 downto 0) := (others => '0');
signal partial_sum_reg : Signed(17 downto 0) := (others => '0');
signal mac_done : STD_LOGIC := '0';

type mac_state_t is (MAC_MUL, MAC_SUM, MAC_ACC);
signal mac_state : mac_state_t := MAC_MUL;
begin
	sum_total_ext <= resize(partial_sum_reg, 32);
	
	Acc_op <= '1' when (ALUctrl(2 downto 1) = "10") else '0'; --Acc operations: "100" and "101" 
	mac_start_req <= '1' when (Acc_op = '1') and (valid_I_EX = '1') and (mac_state = MAC_MUL) and (mac_done = '0') else '0';
	
	load_acc <= '1' when (mac_state = MAC_ACC) else '0';
	MAC_start <=   '1' when (ALUctrl(0) = '1') else '0'; -- If ALUCtrl = "101" the accumulation register is restarted
	ACC_input <= sum_total_ext when (MAC_start = '1') else (sum_total_ext + signed(ACC_out));

	process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				mac_state <= MAC_MUL;
				mac_done <= '0';
				prod0_reg <= (others => '0');
				prod1_reg <= (others => '0');
				prod2_reg <= (others => '0');
				prod3_reg <= (others => '0');
				partial_sum_reg <= (others => '0');
			elsif cancel_mac = '1' then
				mac_state <= MAC_MUL;
				mac_done <= '0';
			else
				if mac_done = '1' then
					mac_done <= '0';
				end if;

				case mac_state is
					when MAC_MUL =>
						if mac_start_req = '1' then
							prod0_reg <= signed(DA(7 downto 0))   * signed(DB(7 downto 0));
							prod1_reg <= signed(DA(15 downto 8))  * signed(DB(15 downto 8));
							prod2_reg <= signed(DA(23 downto 16)) * signed(DB(23 downto 16));
							prod3_reg <= signed(DA(31 downto 24)) * signed(DB(31 downto 24));
							mac_state <= MAC_SUM;
						end if;

					when MAC_SUM =>
						partial_sum_reg <= resize(prod0_reg, 18) + resize(prod1_reg, 18) + resize(prod2_reg, 18) + resize(prod3_reg, 18);
						mac_state <= MAC_ACC;

					when MAC_ACC =>
						mac_state <= MAC_MUL;
						mac_done <= '1';
				end case;
			end if;
		end if;
	end process;

	ACC_register: reg 	generic map (size => 32)
						port map (	Din => std_logic_vector(ACC_input), clk => clk, reset => reset, load => load_acc, Dout => ACC_out);

	Dout_internal <= 	DA + DB when (ALUctrl="000") 
				else DA - DB when (ALUctrl="001") 
				else DA AND DB when (ALUctrl="010")
				else DA OR DB when (ALUctrl="011")
				else ACC_out when (ALUctrl(2 downto 1) = "10")
				else "00000000000000000000000000000000";
	Dout <= Dout_internal;
	ready <= '0' when (mac_start_req = '1') or (mac_state /= MAC_MUL) else '1';
end Behavioral;