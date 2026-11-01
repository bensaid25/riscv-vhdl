library ieee;
use ieee.std_logic_1164.all;
use work.alu_pkg.all;

entity alu_wrap is
  port (
    a, b   : in  std_logic_vector(31 downto 0);
    op     : in  std_logic_vector(3 downto 0);
    result : out std_logic_vector(31 downto 0);
    zero   : out std_logic
  );
end entity;

architecture rtl of alu_wrap is
  signal op_e : alu_op_t;
begin
  with op select op_e <=
    ALU_ADD   when "0000",
    ALU_SUB   when "0001",
    ALU_AND   when "0010",
    ALU_OR    when "0011",
    ALU_XOR   when "0100",
    ALU_SLL   when "0101",
    ALU_SRL   when "0110",
    ALU_SRA   when "0111",
    ALU_SLT   when "1000",
    ALU_SLTU  when "1001",
    ALU_COPYB when "1010",
    ALU_ADD   when others;

  u_alu: entity work.alu
    port map (a => a, b => b, op => op_e, result => result, zero => zero);
end architecture;