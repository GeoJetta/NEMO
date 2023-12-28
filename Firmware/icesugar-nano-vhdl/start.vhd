library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ls021b7dd02_sync is
  port
  (
    clk_i, reset_i, enable_i                          : in std_logic;
    intb_o, gsp_o, bsp_o, gen_o, gck_o, bck_o, vcom_o : out std_logic;
    px_x_o, px_y_o                                    : out std_logic);
end entity ls021b7dd02_sync;

architecture arch of ls021b7dd02_sync is
  constant width         : integer := 240;
  constant height        : integer := 320;
  constant gsp_cyc_1     : integer := 65; -- bck event cycle numbers
  constant gck_cyc_1     : integer := 195;
  constant gck_cyc_2     : integer := gck_cyc_1 + 248;
  constant bsp_cyc_1     : integer := gck_cyc_2 + 1;
  constant bck_cyc_1     : integer := bsp_cyc_1 + 1;
  constant data_cyc_1    : integer := bck_cyc_1 + 1;
  constant bck_cyc_1d    : integer := bck_cyc_1 + 2;
  constant bsp_low       : integer := data_cyc_1 + 2;
  constant gen_cyc_h     : integer := gck_cyc_1 + 51;
  constant gsp_cyc_l     : integer := 323; -- on second cycle!
  constant data_cyc_last : integer := data_cyc_1 + width;
  constant gck_cyc_last  : integer := gck_cyc_2 + 248;
  constant gen_cyc_l     : integer := gck_cyc_last - 51;

  signal mod128_r, mod128_next   : std_logic;
  signal v_count_r, v_count_next : unsigned (9 downto 0);
  signal h_count_r, h_count_next : unsigned (9 downto 0);

  signal h_end, v_end, px_tick : std_logic;
begin
  process (clk_i)
  begin
    if (rising_edge(clk_i)) then
      if (reset_i = '1') then
        v_count_r <= (others => '0');
        h_count_r <= (others => '0');
      else
        v_count_r <= v_count_next;
        h_count_r <= h_count_next;
      end if;
    end if;
  end process;

  h_end <= '1' when h_count_r = gck_cyc_last else
    '0';
  h_count_next <= h_count_r + 1 when h_end = '0' else
    (others => '0');

  bck_o <= '0';
  gck_o <= '0';
  bck_o <= '0';
  bsp_o <= '0';

end arch;