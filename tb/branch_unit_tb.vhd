library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_unit_tb is end entity;

architecture sim of branch_unit_tb is
  signal branch      : std_logic := '0';
  signal funct3      : std_logic_vector(2 downto 0) := "000";
  signal zero, lt    : std_logic := '0';
  signal take_branch : std_logic;

  type word_array is array (natural range <>) of std_logic_vector(31 downto 0);
  constant CORNERS : word_array :=
    (x"00000000", x"00000001", x"7FFFFFFF", x"80000000", x"80000001", x"FFFFFFFF");

  -- index k: 0=BEQ 1=BNE 2=BLT 3=BGE 4=BLTU 5=BGEU
  type f3_array is array (0 to 5) of std_logic_vector(2 downto 0);
  constant KINDS : f3_array := ("000", "001", "100", "101", "110", "111");

  function to_sl(v : boolean) return std_logic is
  begin
    if v then return '1'; else return '0'; end if;
  end function;
begin
  dut: entity work.branch_unit
    port map (branch => branch, funct3 => funct3, zero => zero,
              lt => lt, take_branch => take_branch);

  stim: process
    variable a, b     : std_logic_vector(31 downto 0);
    variable diff     : unsigned(31 downto 0);
    variable lt_s     : boolean;
    variable lt_u     : boolean;
    variable expected : std_logic;
    variable n        : natural := 0;
  begin
    -- 1. The six valid branch kinds over every pair of corner operands
    for ia in CORNERS'range loop
      for ib in CORNERS'range loop
        a := CORNERS(ia);
        b := CORNERS(ib);
        diff := unsigned(a) - unsigned(b);
        lt_s := signed(a) < signed(b);
        lt_u := unsigned(a) < unsigned(b);

        for k in KINDS'range loop
          -- flags as the ALU would present them
          case k is
            when 0 | 1 =>                       -- BEQ, BNE: ALU did SUB
              zero <= to_sl(diff = 0);
              lt   <= diff(0);                  -- junk the unit must ignore
            when 2 | 3 =>                       -- BLT, BGE: ALU did SLT
              lt   <= to_sl(lt_s);
              zero <= to_sl(not lt_s);          -- junk the unit must ignore
            when others =>                      -- BLTU, BGEU: ALU did SLTU
              lt   <= to_sl(lt_u);
              zero <= to_sl(not lt_u);
          end case;

          -- oracle: direct comparison of the operands
          case k is
            when 0      => expected := to_sl(a = b);
            when 1      => expected := to_sl(a /= b);
            when 2      => expected := to_sl(signed(a) < signed(b));
            when 3      => expected := to_sl(signed(a) >= signed(b));
            when 4      => expected := to_sl(unsigned(a) < unsigned(b));
            when others => expected := to_sl(unsigned(a) >= unsigned(b));
          end case;

          funct3 <= KINDS(k);
          branch <= '1';
          wait for 1 ns;
          assert take_branch = expected
            report "kind " & integer'image(k) & " a=" & to_hstring(a)
                   & " b=" & to_hstring(b) & ": expected "
                   & std_logic'image(expected) & " got " & std_logic'image(take_branch)
            severity error;
          n := n + 1;

          -- same flags with branch = '0': never taken
          branch <= '0';
          wait for 1 ns;
          assert take_branch = '0'
            report "kind " & integer'image(k) & ": taken although branch = 0"
            severity error;
        end loop;
      end loop;
    end loop;

    -- 2. Invalid funct3 (010, 011) with branch = '1': never taken, whatever the flags
    branch <= '1';
    for f in 2 to 3 loop
      funct3 <= std_logic_vector(to_unsigned(f, 3));
      for z in 0 to 1 loop
        for l in 0 to 1 loop
          zero <= to_sl(z = 1);
          lt   <= to_sl(l = 1);
          wait for 1 ns;
          assert take_branch = '0'
            report "invalid funct3 " & integer'image(f) & " took a branch"
            severity error;
        end loop;
      end loop;
    end loop;

    -- 3. branch = '0' with every funct3 and flag combination: never taken
    branch <= '0';
    for f in 0 to 7 loop
      funct3 <= std_logic_vector(to_unsigned(f, 3));
      for z in 0 to 1 loop
        for l in 0 to 1 loop
          zero <= to_sl(z = 1);
          lt   <= to_sl(l = 1);
          wait for 1 ns;
          assert take_branch = '0'
            report "funct3 " & integer'image(f) & " took a branch with branch = 0"
            severity error;
        end loop;
      end loop;
    end loop;

    report "branch_unit_tb finished: " & integer'image(n) & " operand checks";
    wait;
  end process;
end architecture;