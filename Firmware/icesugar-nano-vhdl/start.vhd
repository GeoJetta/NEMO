library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity counter is
    generic(MAX_VALUE : positive := 15);
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- For this entity, the output is not a fixed number of bits. 
        -- The output has MAX_VALUE+1 possible values, so we need to do some
        -- math to calculate the number of bits. If MAX_VALUE+1 was a power
        -- of 2, we could just do log2(MAX_VALUE+1).
        -- 
        -- However, MAX_VALUE is a generic and can be any possible value.
        -- We therefore want to take the ceiling of the log2 to ensure we
        -- have enough bits.
        --
        -- e.g., if the maximum value is 10, the output can have 11 possible
        -- values. log2(11) = 3.4, which will round down to 3 when used as an
        -- integer. However, we know we need 4 bits since 3 bits only supports
        -- 8 values, with a maximum value of 7. By taking the ceiling,
        -- ceil(3.4) = 4, we get the correct number of bits.
        --
        -- To do this calculation in VHDL, we can use the log2 and ceil function
        -- from the math_real package. However, log2 and ceil only support the
        -- real type, so we have to cast the input to real. Similarly, we need
        -- to cast the ceil result back to an integer. The complete, horribly
        -- ugly computation is: integer(ceil(log2(real(MAX_VALUE+1)))). I will
        -- show a more readable way of doing this in the next entity.
        --
        -- Be aware that calculating the appropriate number of bits is a
        -- common place for errors. You should test this for a large number
        -- of generics to be confident that it is correct. A very common
        -- mistake is forgetting the +1. Remember that log2 of a number doesn't
        -- tell you the number of bits needed to represent that number, unless
        -- it is a power of 2. Log2(n) specifies how many bits are required to
        -- represent n different values. Since we also have to support 0, there
        -- are n+1 total values.
        count : out std_logic_vector(integer(ceil(log2(real(MAX_VALUE+1))))-1 downto 0);
		 ovf : out std_logic);
end counter;

-- This architecture modifies the unsigned implementation of counter4bit to
-- support a generic MAX_VALUE. Note that the previous advantages of unsigned
-- do not apply here because MAX_VALUE does not have to be a power of 2 - 1.
-- In fact, in this case the integer and unsigned implementations are very
-- similar.

architecture BHV_UNSIGNED of counter is

    -- We have to recalculate the bits here again. It would definitely be
    -- best to use a function in a package. See the next entity.
    constant NUM_BITS : positive := integer(ceil(log2(real(MAX_VALUE+1))));

    -- when using the generic MAX_VALUE, count requires NUM_BITS bits.
    signal count_r : unsigned(NUM_BITS-1 downto 0);
    
begin
    process(clk, rst)
    begin
        if (rst = '1') then
            -- We can't use a hardcoded literal anymore because the width can
            -- change with MAX_VALUE. We also can't assign an integer to
            -- a vector (without using conversion functions).
            count_r <= (others => '0');
            
        elsif (rising_edge(clk)) then

            -- We can no longer simply add/subtract 1 because MAX_VALUE may not
            -- be a power of 2 - 1 (e.g., 3,7,15,etc.). Instead, we have to use
            -- a similar strategy as the integer implementation.

                if (count_r = MAX_VALUE) then
                    count_r <= to_unsigned(0, NUM_BITS);
					  ovf <= '1';
                else
                    count_r <= count_r + 1;
					  ovf <= '0';
				  end if;
        end if;
    end process;

    count <= std_logic_vector(count_r);
    
end BHV_UNSIGNED;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity ls021b7dd02_sync is
  port
  (
    clk, rst, en_i                          : in std_logic;
    intb_o, gsp_o, bsp_o, gen_o, gck_o, bck_o, vcom_o : out std_logic;
    px_x_o, px_y_o                                    : out std_logic);
end entity ls021b7dd02_sync;

architecture arch of ls021b7dd02_sync is
  constant width   	: integer := 240;
  constant height 	: integer := 320;
  constant gsp_h     	: integer := 65; -- bck event cycle numbers
  constant gck_h  	: integer := 195;
  constant bsp_h 		: integer := 1; -- gck cycle 2
  constant bck_1h    	: integer := bsp_h + 1;
  constant data_1h   	: integer := bck_1h + 1;
  constant bck_1l    	: integer := bck_1h + 2;
  constant bsp_l     	: integer := data_1h + 2;
  constant gen_h     	: integer := gck_h + 51;
  constant gsp_l     	: integer := 323; -- on second cycle!
  constant data_last 	: integer := data_1h + width;
  constant gen_l     	: integer := data_last - 51;
  constant MAX_VALUE 	: integer := 248;
  constant VMAX 		: integer := 648;
  
  signal count2 	: std_logic_vector(integer(ceil(log2(real(MAX_VALUE+1))))-1 downto 0);
  signal gcount2 	: std_logic_vector(integer(ceil(log2(real(VMAX+1))))-1 downto 0);
  signal gclk 		: std_logic;
  signal fclk 		: std_logic;
  
 	
begin
	B_COUNT : entity work.counter(BHV_UNSIGNED)
        generic map (MAX_VALUE => MAX_VALUE)
        port map (
          	clk    => clk,
         	rst    => rst,
			ovf => gclk,
         	count => count2);

	G_COUNT : entity work.counter(BHV_UNSIGNED)
        generic map (MAX_VALUE => VMAX)
        port map (
         	clk    => gclk,
        	rst    => rst,
			ovf => fclk,
          	count => gcount2);
				
	process(gcount2, count2)
		variable gcount : integer := 0;
		variable count : integer := 0;
	begin
		gcount := to_integer(unsigned(gcount2));
		count := to_integer(unsigned(count2));
		
		if (gcount = 0) then
			if (count = gck_h) then
				gck_o <= '1';
			end if;
			if (count = gsp_h) then
				gsp_o <= '1';
			elsif (count = gsp_l) then
				gsp_o <= '0';
			end if;
		elsif (gcount = 1) then
			gck_o <= '0';
			if (count = bsp_h) then
				bsp_o <= '1';
			elsif (count = bsp_l) then
				bsp_o <= '0';
			end if;
			if (count = gen_h) then
				gen_o <= '1';
			elsif (count = gen_l) then
				gen_o <= '0';
			end if;
		else
			
		end if;
		if (count mod 2 = 0) then
			bck_o <= '0';
		else
			bck_o <= '1';
		end if;
	end process;
end arch;