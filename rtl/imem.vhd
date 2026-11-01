library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity imem is
  generic (
    INIT_FILE : string   := "";     -- hex file, one 32-bit word per line
    DEPTH     : positive := 1024    -- number of words
  );
  port (
    addr  : in  std_logic_vector(31 downto 0);   -- byte address (the PC)
    instr : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of imem is
  type mem_t is array (0 to DEPTH-1) of std_logic_vector(31 downto 0);

  impure function load(file_name : string) return mem_t is
    file f : text;
    variable status : file_open_status;
    variable l : line;
    variable w : std_logic_vector(31 downto 0);
    variable m : mem_t := (others => x"00000013");   -- NOP
    variable i : natural := 0;
  begin
    if file_name'length = 0 then
      return m;
    end if;
    file_open(status, f, file_name, read_mode);
    assert status = open_ok
      report "imem: cannot open " & file_name severity failure;
    while not endfile(f) and i < DEPTH loop
      readline(f, l);
      if l'length > 0 then
        hread(l, w);
        m(i) := w;
        i := i + 1;
      end if;
    end loop;
    file_close(f);
    return m;
  end function;

  constant mem : mem_t := load(INIT_FILE);
begin
  instr <= mem(to_integer(unsigned(addr(30 downto 2))) mod DEPTH);
end architecture;