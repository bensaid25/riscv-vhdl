library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity immgen is
  port (
    instr : in  std_logic_vector(31 downto 0);
    imm   : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of immgen is
begin
  process(all)
    variable i_imm : std_logic_vector(11 downto 0);
    variable s_imm : std_logic_vector(11 downto 0);
    variable b_imm : std_logic_vector(12 downto 0);
    variable j_imm : std_logic_vector(20 downto 0);
  begin
    i_imm := instr(31 downto 20);
    s_imm := instr(31 downto 25) & instr(11 downto 7);
    b_imm := instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';
    j_imm := instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0';

    case instr(6 downto 0) is
      when "0010011" | "0000011" | "1100111" =>   -- OP-IMM, LOAD, JALR (I)
        imm <= std_logic_vector(resize(signed(i_imm), 32));
      when "0100011" =>                            -- STORE (S)
        imm <= std_logic_vector(resize(signed(s_imm), 32));
      when "1100011" =>                            -- BRANCH (B)
        imm <= std_logic_vector(resize(signed(b_imm), 32));
      when "0110111" | "0010111" =>                -- LUI, AUIPC (U)
        imm <= instr(31 downto 12) & x"000";
      when "1101111" =>                            -- JAL (J)
        imm <= std_logic_vector(resize(signed(j_imm), 32));
      when others =>
        imm <= (others => '0');
    end case;
  end process;
end architecture;