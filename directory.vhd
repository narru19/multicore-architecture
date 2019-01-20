LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;
USE ieee.std_logic_arith.all;
USE work.utils.ALL;

ENTITY directory IS
	PORT(
		clk            : IN    STD_LOGIC;
		reset          : IN    STD_LOGIC;
		-- Directory -> L1_1
		addr_one       : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		we_one         : IN    STD_LOGIC;
		re_one         : IN    STD_LOGIC;
		evict_one      : IN    STD_LOGIC;
		evict_addr_one : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		ack_one        : OUT   STD_LOGIC;
		inv_one        : OUT   STD_LOGIC;
		inv_llc_one    : OUT   STD_LOGIC;
		inv_addr_one   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		inv_ack_one    : IN    STD_LOGIC;
		c2c_one        : OUT   STD_LOGIC;
		c2c_addr_one   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		-- Directory -> L1_2
		addr_two       : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		we_two         : IN    STD_LOGIC;
		re_two         : IN    STD_LOGIC;
		evict_two      : IN    STD_LOGIC;
		evict_addr_two : IN	   STD_LOGIC_VECTOR(31 DOWNTO 0);
		ack_two        : OUT   STD_LOGIC;
		inv_two        : OUT   STD_LOGIC;
        inv_llc_two    : OUT   STD_LOGIC;
		inv_addr_two   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		inv_ack_two    : IN    STD_LOGIC;
		c2c_two        : OUT   STD_LOGIC;
        c2c_addr_two   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		-- Directory -> LLC
		inv_llc        : OUT   STD_LOGIC;
		inv_addr_llc   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		inv_ack_llc    : IN    STD_LOGIC;
		evict_llc      : IN    STD_LOGIC;
		addr_llc       : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		c2c_llc        : OUT    STD_LOGIC;
		ack_llc        : OUT   STD_LOGIC;
		-- Directory -> Bus
		bus_c2c       : INOUT STD_LOGIC
	);
END directory;


ARCHITECTURE directory_behaviour OF directory IS
	
	TYPE L1_status_fields_t  IS ARRAY(32 DOWNTO 0) OF STD_LOGIC_VECTOR(1 DOWNTO 0); -- Whether a block has valid data
	TYPE LLC_status_fields_t IS ARRAY(32 DOWNTO 0) OF STD_LOGIC;                    -- Whether a block has valid data

	TYPE tag_fields_t	IS ARRAY(32 DOWNTO 0) OF STD_LOGIC_VECTOR(27 DOWNTO 0);
	
	SIGNAL L1_1_status_fields : L1_status_fields_t;
	SIGNAL L1_2_status_fields : L1_status_fields_t;
	SIGNAL LLC_status_fields  : L1_status_fields_t;
	SIGNAL tag_fields         : tag_fields_t;

	SIGNAL first_invalid_line : INTEGER RANGE 0 TO 32 := 0;
	SIGNAL hit_line_num_one_i : INTEGER RANGE 0 TO 32 := 0;
	SIGNAL hit_line_num_two_i : INTEGER RANGE 0 TO 32 := 0;
	SIGNAL hit_line_num_llc_i : INTEGER RANGE 0 TO 32 := 0;
	
	-- The next state of the directory
	SIGNAL state_i    : directory_state_t;
	SIGNAL state_nx_i : directory_state_t;

	SIGNAL req_1 : STD_LOGIC;
	SIGNAL req_2 : STD_LOGIC;

	SIGNAL done_one_sig : STD_LOGIC;
	SIGNAL done_two_sig : STD_LOGIC;

	-- For each cache, we need to check if the block it is requesting is in SHARED 
	--   or MODIFIED state. Since both caches can be asking at once, results may
	--   differ, so we need separate signals that will be given values independently
	SIGNAL valid_state_S_one : STD_LOGIC;
	SIGNAL valid_state_M_one : STD_LOGIC;
	SIGNAL valid_state_S_two : STD_LOGIC;
	SIGNAL valid_state_M_two : STD_LOGIC;

	-- For each cache, check if the line is owned in SHARED or MODIFIED state
	SIGNAL owned_state_S_one : STD_LOGIC;
	SIGNAL owned_state_M_one : STD_LOGIC;
	SIGNAL owned_state_S_two : STD_LOGIC;
	SIGNAL owned_state_M_two : STD_LOGIC;
	SIGNAL owned_state_S_LLC : STD_LOGIC;

	-- Check if the address indicated by the LLC is in cache
	SIGNAL present_state_S_one : STD_LOGIC;
	SIGNAL present_state_M_one : STD_LOGIC;
	SIGNAL present_state_S_two : STD_LOGIC;
	SIGNAL present_state_M_two : STD_LOGIC;
	SIGNAL present_state_S_LLC : STD_LOGIC;
	SIGNAL present_in_cache    : STD_LOGIC;

	-- Check which line to evict
	SIGNAL evict_line_num_one_i : INTEGER RANGE 0 TO 32 := 0;
	SIGNAL evict_line_num_two_i : INTEGER RANGE 0 TO 32 := 0;

	-- The current CPU being served
	-- CPU_ONE  -> 1
	-- CPU_TWO  -> 2
	-- CPU_NONE -> 0
	SIGNAL current_cpu_i : STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL current_cpu_nx_i : STD_LOGIC_VECTOR(1 DOWNTO 0);

	-- Determine if the line is present in S state in other caches
	FUNCTION has_line_in_S (
		addr              : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields        : tag_fields_t;
		status_fields_L1  : L1_status_fields_t;
		status_fields_LLC : L1_status_fields_t
	) 
	RETURN STD_LOGIC IS
		VARIABLE tmp_return : STD_LOGIC := '0';
		BEGIN
			FOR i IN 0 TO 32 LOOP
				tmp_return := tmp_return OR (to_std_logic(status_fields_L1(i) = STATE_SHARED AND tag_fields(i) = addr(31 DOWNTO 4)))  OR (to_std_logic(status_fields_LLC(i) = "01" AND tag_fields(i) = addr(31 DOWNTO 4)));
			END LOOP;
		RETURN tmp_return;
	END has_line_in_S;

	-- Determine which line has hit
	FUNCTION line_hit (
		addr               : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields         : tag_fields_t;
		status_fields_L1_1 : L1_status_fields_t;
		status_fields_L1_2 : L1_status_fields_t;
		status_fields_LLC  : L1_status_fields_t
	) 
	RETURN INTEGER IS
		VARIABLE tmp_return : INTEGER := 0;
		BEGIN
			FOR i IN 0 TO 32 LOOP
				IF (tag_fields(i) = addr(31 DOWNTO 4)) AND ((status_fields_L1_1(i) = STATE_SHARED OR status_fields_L1_1(i) = STATE_MODIFIED) 
				    OR (status_fields_L1_2(i) = STATE_SHARED OR status_fields_L1_2(i) = STATE_MODIFIED) 
				    OR (status_fields_LLC(i) = STATE_SHARED)) THEN
					tmp_return := i;
				END IF;
			END LOOP;
		RETURN tmp_return;
	END line_hit;

	-- Determine which line to evict
	FUNCTION line_evict (
		addr             : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields       : tag_fields_t;
		status_fields_L1 : L1_status_fields_t
	) 
	RETURN INTEGER IS
		VARIABLE tmp_return : INTEGER := 0;
		BEGIN
			FOR i IN 0 TO 32 LOOP
				IF ((tag_fields(i) = addr(31 DOWNTO 4)) AND ((status_fields_L1(i) = STATE_SHARED) OR (status_fields_L1(i) = STATE_MODIFIED))) THEN
					tmp_return := i;
				END IF;
			END LOOP;
		RETURN tmp_return;
	END line_evict;

	-- Determine if the line is present in M state in other caches
	FUNCTION has_line_in_M (
		addr              : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields        : tag_fields_t;
		status_fields_L1  : L1_status_fields_t;
		status_fields_LLC : L1_status_fields_t
	) 
	RETURN STD_LOGIC IS
		VARIABLE tmp_return : STD_LOGIC := '0';
		BEGIN
			FOR i IN 0 TO 32 LOOP
				tmp_return := tmp_return OR (to_std_logic(status_fields_L1(i) = STATE_MODIFIED AND tag_fields(i) = addr(31 DOWNTO 4)));
			END LOOP;
		RETURN tmp_return;
	END has_line_in_M;

	-- Determine if the line is present in S state in an L1 cache
	FUNCTION owns_line_in_S (
		addr             : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields       : tag_fields_t;
		status_fields_L1 : L1_status_fields_t
	) 
	RETURN STD_LOGIC IS
		VARIABLE tmp_return : STD_LOGIC := '0';
		BEGIN
			FOR i IN 0 TO 32 LOOP
				tmp_return := tmp_return OR (to_std_logic(status_fields_L1(i) = STATE_SHARED AND tag_fields(i) = addr(31 DOWNTO 4)));
			END LOOP;
		RETURN tmp_return;
	END owns_line_in_S;

	-- Determine if the line is present in M state in an L1 cache
	FUNCTION owns_line_in_M (
		addr             : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields       : tag_fields_t;
		status_fields_L1 : L1_status_fields_t
	) 
	RETURN STD_LOGIC IS
		VARIABLE tmp_return : STD_LOGIC := '0';
		BEGIN
			FOR i IN 0 TO 32 LOOP
				tmp_return := tmp_return OR (to_std_logic(status_fields_L1(i) = STATE_MODIFIED AND tag_fields(i) = addr(31 DOWNTO 4)));
			END LOOP;
		RETURN tmp_return;
	END owns_line_in_M;

	-- Determine the least recently used line
	FUNCTION get_empty_line (
		status_fields_L1_1 : L1_status_fields_t;
		status_fields_L1_2 : L1_status_fields_t;
		status_fields_LLC  : L1_status_fields_t
	) RETURN INTEGER IS
		VARIABLE tmp_return : INTEGER := 0;
		BEGIN
			FOR i IN 0 to 32 LOOP
				IF status_fields_L1_1(i) = STATE_INVALID AND status_fields_L1_2(i) = STATE_INVALID AND status_fields_LLC(i) = STATE_INVALID THEN
					tmp_return := i;
				END IF;
			END LOOP;
		RETURN tmp_return;
	END get_empty_line;

	-- Procedure to reset and initialize the cache
	PROCEDURE reset_directory(
			SIGNAL L1_1_status_fields : OUT L1_status_fields_t;
			SIGNAL LLC_status_fields  : OUT L1_status_fields_t;
			SIGNAL L1_2_status_fields : OUT L1_status_fields_t;
			SIGNAL inv_one            : OUT STD_LOGIC;
			SIGNAL inv_two            : OUT STD_LOGIC;
			SIGNAL inv_llc            : OUT STD_LOGIC;
			SIGNAL ack_one            : OUT STD_LOGIC;
			SIGNAL ack_two            : OUT STD_LOGIC;
			SIGNAL ack_llc            : OUT STD_LOGIC;
			SIGNAL c2c_one            : OUT STD_LOGIC;
			SIGNAL c2c_two            : OUT STD_LOGIC;
			SIGNAL c2c_llc            : OUT STD_LOGIC;
			SIGNAL inv_llc_one        : OUT STD_LOGIC;
			SIGNAL inv_llc_two        : OUT STD_LOGIC
		) IS
	BEGIN
		-- Initialize valid fields
		FOR i IN 0 TO 32 LOOP
			L1_1_status_fields(i) <= STATE_INVALID;
			LLC_status_fields(i)  <= STATE_INVALID;
			L1_2_status_fields(i) <= STATE_INVALID;
		END LOOP;
	
		inv_one <= '0';
		inv_two <= '0';
		inv_llc <= '0';
		ack_one <= '0';
		ack_two <= '0';
		ack_llc <= '0';
		c2c_one <= '0';
		c2c_two <= '0';
		c2c_llc <= '0';
		inv_llc_one <= '0';
		inv_llc_two <= '0';
	END PROCEDURE;

	PROCEDURE clear_bus(
		SIGNAL mem_c2c : INOUT STD_LOGIC
	) IS
	BEGIN
		mem_c2c      <= 'Z';
	END PROCEDURE;

BEGIN

-- Process that represents the internal register
internal_register : PROCESS(clk, reset)
BEGIN
	IF rising_edge(clk) THEN
		IF reset = '1' THEN
			state_i <= READY;
			current_cpu_i <= CPU_NONE;
		ELSE
			state_i <= state_nx_i;
			current_cpu_i <= current_cpu_nx_i;
		END IF;
	END IF;
END PROCESS internal_register;

next_state_process : PROCESS(clk, reset, state_i, current_cpu_i, req_1, req_2, re_one, re_two, we_one, we_two, evict_one, evict_two, evict_llc, inv_ack_one, inv_ack_two, inv_ack_llc, valid_state_S_one, valid_state_M_one, valid_state_S_two, valid_state_M_two, bus_c2c, owned_state_S_one, owned_state_M_one, owned_state_S_two, owned_state_M_two, owned_state_S_LLC, present_state_S_one, present_state_M_one, present_state_S_two, present_state_M_two, present_state_S_LLC, present_in_cache)

BEGIN
	IF reset = '1' THEN
		state_nx_i <= READY;
		current_cpu_nx_i <= CPU_NONE;
	
	ELSIF clk = '1' THEN
		-- Processor Next State
		state_nx_i <= state_i;
		current_cpu_nx_i <= current_cpu_i;
		
		IF state_i = READY THEN
			-- LLC evictions should be top priority to be able to load new blocks
			IF evict_llc = '1' AND present_in_cache = '1' THEN
				state_nx_i <= LLC_INV;
			ELSIF current_cpu_i = CPU_NONE OR current_cpu_i = CPU_TWO THEN
				IF req_1 = '1' AND evict_one /= '1' THEN
					current_cpu_nx_i <= CPU_ONE;
					IF re_one = '1' AND valid_state_S_one = '0' AND valid_state_M_one = '0' THEN 
						-- re && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF re_one = '1' AND valid_state_S_one = '1' AND valid_state_M_one = '0' THEN
						-- re && somebody has S -> GET from LLC
						state_nx_i <= READY;
					ELSIF re_one = '1' AND valid_state_M_one = '1' THEN
						-- re && somebody has M -> bus_C2C 
						state_nx_i <= WAIT_C2C;
					ELSIF we_one = '1' AND valid_state_S_one = '0' AND valid_state_M_one = '0' THEN
						-- we && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF we_one = '1' AND valid_state_S_one = '1' AND valid_state_M_one = '0' THEN
						-- we && somebody has S -> GET from LLC + bus_INV
						state_nx_i <= WAIT_INV;
					ELSIF we_one = '1' AND valid_state_M_one = '1' THEN
						-- we && somebody has M -> bus_C2C + bus_INV
						state_nx_i <= WAIT_C2C;
					END IF;
					-- re && owned S -> no transaction will be done
					-- re && owned M -> no transaction will be done
					-- we && owned S -> no transaction will be done (this case is not even possible)
					-- we && owned M -> no transaction will be done
				ELSIF req_2 = '1' AND evict_two /= '1' THEN
					current_cpu_nx_i <= CPU_TWO;
					IF re_two = '1' AND valid_state_S_two = '0' AND valid_state_M_two = '0' THEN 
						-- re && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF re_two = '1' AND valid_state_S_two = '1' AND valid_state_M_two = '0' THEN					
						-- re && somebody has S -> GET from LLC
						state_nx_i <= READY;
					ELSIF re_two = '1' AND valid_state_M_two = '1' THEN
						-- re && somebody has M -> bus_C2C 
						state_nx_i <= WAIT_C2C;
					ELSIF we_two = '1' AND valid_state_S_two = '0' AND valid_state_M_two = '0' THEN
						-- we && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF we_two = '1' AND valid_state_S_two = '1' AND valid_state_M_two = '0' THEN
						-- we && somebody has S -> GET from LLC + bus_INV
						state_nx_i <= WAIT_INV;
					ELSIF we_two = '1' AND valid_state_M_two = '1' THEN
						-- we && somebody has M -> bus_C2C + bus_INV
						state_nx_i <= WAIT_C2C;
					END IF;
					-- re && owned S -> no transaction will be done
					-- re && owned M -> no transaction will be done
					-- we && owned S -> no transaction will be done (this case is not even possible)
					-- we && owned M -> no transaction will be done
				END IF;
			ELSIF current_cpu_i = CPU_ONE THEN
				IF req_2 = '1' AND evict_two /= '1' THEN
					current_cpu_nx_i <= CPU_TWO;
					IF re_two = '1' AND valid_state_S_two = '0' AND valid_state_M_two = '0' THEN 
						-- re && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF re_two = '1' AND valid_state_S_two = '1' AND valid_state_M_two = '0' THEN					
						-- re && somebody has S -> GET from LLC
						state_nx_i <= READY;
					ELSIF re_two = '1' AND valid_state_M_two = '1' THEN
						-- re && somebody has M -> bus_C2C  
						state_nx_i <= WAIT_C2C;
					ELSIF we_two = '1' AND valid_state_S_two = '0' AND valid_state_M_two = '0' THEN
						-- we && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF we_two = '1' AND valid_state_S_two = '1' AND valid_state_M_two = '0' THEN
						-- we && somebody has S -> GET from LLC + bus_INV
						state_nx_i <= WAIT_INV;
					ELSIF we_two = '1' AND valid_state_M_two = '1' THEN
						-- we && somebody has M -> bus_C2C + bus_INV
						state_nx_i <= WAIT_C2C;
					END IF;
					-- re && owned S -> no transaction will be done
					-- re && owned M -> no transaction will be done
					-- we && owned S -> no transaction will be done (this case is not even possible)
					-- we && owned M -> no transaction will be done
				ELSIF req_1 = '1' AND evict_one /= '1' THEN
					current_cpu_nx_i <= CPU_ONE;
					IF re_one = '1' AND valid_state_S_one = '0' AND valid_state_M_one = '0' THEN 
						-- re && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF re_one = '1' AND valid_state_S_one = '1' AND valid_state_M_one = '0' THEN
						-- re && somebody has S -> GET from LLC
						state_nx_i <= READY;
					ELSIF re_one = '1' AND valid_state_M_one = '1' THEN
						-- re && somebody has M -> bus_C2C 
						state_nx_i <= WAIT_C2C;
					ELSIF we_one = '1' AND valid_state_S_one = '0' AND valid_state_M_one = '0' THEN
						-- we && nobody has -> bus_GET
						state_nx_i <= READY;
					ELSIF we_one = '1' AND valid_state_S_one = '1' AND valid_state_M_one = '0' THEN
						-- we && somebody has S -> GET from LLC + bus_INV
						state_nx_i <= WAIT_INV;
					ELSIF we_one = '1' AND valid_state_M_one = '1' THEN
						-- we && somebody has M -> bus_C2C + bus_INV
						state_nx_i <= WAIT_C2C;
					END IF;
					-- re && owned S -> no transaction will be done
					-- re && owned M -> no transaction will be done
					-- we && owned S -> no transaction will be done (this case is not even possible)
					-- we && owned M -> no transaction will be done
				END IF;
			END IF;
		
		ELSIF state_i = WAIT_C2C THEN
			IF bus_c2c = '1' THEN
				state_nx_i <= READY;
			END IF;
		
		ELSIF state_i = WAIT_INV THEN
			IF current_cpu_i = CPU_ONE THEN
				IF valid_state_S_one = '0' THEN
					state_nx_i <= READY;
				END IF;
			ELSIF current_cpu_i = CPU_TWO THEN
				IF valid_state_S_two = '0' THEN
					state_nx_i <= READY;
				END IF;
			END IF;
		
		ELSIF state_i = LLC_INV THEN
			IF present_in_cache = '0' THEN
				state_nx_i <= READY;
			END IF;
		END IF;
	END IF;
END PROCESS next_state_process;

execution_process : PROCESS(clk)
BEGIN
	IF rising_edge(clk) AND reset = '1' THEN
		reset_directory(L1_1_status_fields, L1_2_status_fields, LLC_status_fields, inv_one, inv_two, inv_llc, ack_one, ack_two, ack_llc, c2c_one, c2c_two, c2c_llc, inv_llc_one, inv_llc_two);	
		clear_bus(bus_c2c);
	
	ELSIF falling_edge(clk) AND reset = '0' THEN
		IF state_i = READY THEN
			IF state_nx_i = LLC_INV THEN
				LLC_status_fields(hit_line_num_llc_i) <= STATE_INVALID;
				inv_one      <= '1';
				inv_llc_one  <= '1';
				inv_addr_one <= addr_llc;
				inv_two      <= '1';
				inv_llc_two  <= '1';
				inv_addr_two <= addr_llc;
				IF present_state_M_one = '1' THEN
					c2c_one <= '1';
				ELSIF present_state_M_two = '1' THEN
					c2c_two <= '1';
				END IF;
			
			ELSIF (current_cpu_i = CPU_NONE OR current_cpu_i = CPU_TWO) AND evict_one /= '1' THEN
				IF req_1 = '1' THEN
					IF state_nx_i = READY THEN
						ack_one <= '1';
						-- Block already exists SHARED in other caches
						IF valid_state_S_one = '1' THEN 
							-- Loaded line is SHARED, update LLC as well
							L1_1_status_fields(hit_line_num_one_i) <= STATE_SHARED;
						ELSE
							IF re_one = '1' THEN
								-- Loaded line is SHARED, update LLC as well
								L1_1_status_fields(first_invalid_line) <= STATE_SHARED;
								LLC_status_fields(first_invalid_line)  <= STATE_SHARED;
								tag_fields(first_invalid_line)         <= addr_one(31 DOWNTO 4);
							ELSIF we_one = '1' AND owned_state_M_one = '0' THEN
								-- Loaded line is SHARED, LLC does not get the line
								L1_1_status_fields(first_invalid_line) <= STATE_MODIFIED;
								tag_fields(first_invalid_line)         <= addr_one(31 DOWNTO 4);
							END IF;
						END IF;
					
					ELSIF state_nx_i = WAIT_C2C THEN
						-- Tell Core 1's cache to put make a c2c transaction for the data
						ack_one      <= '1';
						c2c_two      <= '1';
						c2c_llc      <= '1';
						c2c_addr_two <= addr_one;
						IF we_one = '1' THEN
							-- Also invalidate if the address will be written
							inv_two <= '1';
						END IF;
						
						IF re_one = '1' THEN
							L1_1_status_fields(hit_line_num_one_i) <= STATE_SHARED;
							-- The original cache keeps the line in SHARED as well
							L1_2_status_fields(hit_line_num_one_i) <= STATE_SHARED;
							-- The LLC also gets the line in SHARED
							LLC_status_fields(hit_line_num_one_i)  <= STATE_SHARED;
						ELSIF we_one = '1' THEN
							L1_1_status_fields(hit_line_num_one_i) <= STATE_MODIFIED;
							-- The original cache invalidates the line
							L1_2_status_fields(hit_line_num_one_i) <= STATE_INVALID;
						END IF;
					
					ELSIF state_nx_i = WAIT_INV THEN
						-- If a cache does not have the data in SHARED, an ack will be sent right away with no further action
						inv_two      <= '1'; 
						inv_addr_two <= addr_one;
						inv_llc      <= '1';
						inv_addr_llc <= addr_one;
					END IF;
				
				ELSIF req_2 = '1' THEN
					IF state_nx_i = READY THEN
						ack_two <= '1';
						-- Block already exists SHARED in other caches
						IF valid_state_S_two = '1' THEN
							-- Loaded line is SHARED, update LLC as well
							L1_2_status_fields(hit_line_num_two_i) <= STATE_SHARED;
						ELSE
							IF re_two = '1' THEN
								-- Loaded line is SHARED, update LLC as well
								L1_2_status_fields(first_invalid_line) <= STATE_SHARED;
								LLC_status_fields(first_invalid_line)  <= STATE_SHARED;
								tag_fields(first_invalid_line)         <= addr_two(31 DOWNTO 4);
							ELSIF we_two = '1' AND owned_state_M_two = '0' THEN
								-- Loaded line is SHARED, LLC does not get the line
								L1_2_status_fields(first_invalid_line) <= STATE_MODIFIED;
								tag_fields(first_invalid_line)         <= addr_two(31 DOWNTO 4);
							END IF;
						END IF;
					
					ELSIF state_nx_i = WAIT_C2C THEN
						ack_two      <= '1';
						c2c_one      <= '1'; 
						c2c_llc      <= '1';
						c2c_addr_one <= addr_two;
						IF we_two = '1' THEN
							inv_one <= '1'; 
						END IF;
						
						IF re_two = '1' THEN
							L1_1_status_fields(hit_line_num_two_i) <= STATE_SHARED;
							-- The original cache keeps the line in SHARED as well
							L1_2_status_fields(hit_line_num_two_i) <= STATE_SHARED;
							-- The LLC also gets the line in SHARED
							LLC_status_fields(hit_line_num_two_i)  <= STATE_SHARED;
						ELSIF we_two = '1' THEN
							L1_2_status_fields(hit_line_num_two_i) <= STATE_MODIFIED;
							-- The original cache invalidates the line
							L1_1_status_fields(hit_line_num_two_i) <= STATE_INVALID;
						END IF;
					
					ELSIF state_nx_i = WAIT_INV THEN
						-- If a cache does not have the data in SHARED, an ack will be sent right away with no further action
						inv_one      <= '1'; 
						inv_addr_one <= addr_two;
						inv_llc      <= '1';
						inv_addr_llc <= addr_two;
					END IF;
				END IF;
			
			ELSIF current_cpu_i = CPU_ONE AND evict_two /= '1' THEN
				IF req_2 = '1' THEN
					IF state_nx_i = READY THEN
						ack_two <= '1';
						-- Block already exists SHARED in other caches
						IF valid_state_S_two = '1' THEN
							-- Loaded line is SHARED, update LLC as well
							L1_2_status_fields(hit_line_num_two_i) <= STATE_SHARED;
						ELSE
							IF re_two = '1' THEN
								-- Loaded line is SHARED, update LLC as well
								L1_2_status_fields(first_invalid_line) <= STATE_SHARED;
								LLC_status_fields(first_invalid_line)  <= STATE_SHARED;
								tag_fields(first_invalid_line)         <= addr_two(31 DOWNTO 4);
							ELSIF we_two = '1' AND owned_state_M_two = '0' THEN
								-- Loaded line is SHARED, LLC does not get the line
								L1_2_status_fields(first_invalid_line) <= STATE_MODIFIED;
								tag_fields(first_invalid_line)         <= addr_two(31 DOWNTO 4);
							END IF;
						END IF;
					
					ELSIF state_nx_i = WAIT_C2C THEN
						ack_two      <= '1';
						c2c_one      <= '1'; 
						c2c_llc      <= '1';
						c2c_addr_one <= addr_two;
						IF we_two = '1' THEN
							inv_one <= '1'; 
						END IF;
						
						IF re_two = '1' THEN
							L1_1_status_fields(hit_line_num_two_i) <= STATE_SHARED;
							-- The original cache keeps the line in SHARED as well
							L1_2_status_fields(hit_line_num_two_i) <= STATE_SHARED;
							-- The LLC also gets the line in SHARED
							LLC_status_fields(hit_line_num_two_i)  <= STATE_SHARED;
						ELSIF we_two = '1' THEN
							L1_2_status_fields(hit_line_num_two_i) <= STATE_MODIFIED;
							-- The original cache invalidates the line
							L1_1_status_fields(hit_line_num_two_i) <= STATE_INVALID;
						END IF;
					
					ELSIF state_nx_i = WAIT_INV THEN
						inv_one <= '1'; -- If a cache does not have the data in SHARED, an ack will be sent right away with no further action
						inv_addr_one <= addr_two;
						inv_llc <= '1';
						inv_addr_llc <= addr_two;
					END IF;
				ELSIF req_1 = '1' THEN
					IF state_nx_i = READY THEN
						ack_one <= '1';
						-- Block already exists SHARED in other caches
						IF valid_state_S_one = '1' THEN
							-- Loaded line is SHARED, update LLC as well
							L1_1_status_fields(hit_line_num_one_i) <= STATE_SHARED;
						ELSE
							IF re_one = '1' THEN
								-- Loaded line is SHARED, update LLC as well
								L1_1_status_fields(first_invalid_line) <= STATE_SHARED;
								LLC_status_fields(first_invalid_line)  <= STATE_SHARED;
								tag_fields(first_invalid_line)         <= addr_one(31 DOWNTO 4);
							ELSIF we_one = '1' AND owned_state_M_one = '0' THEN
								-- Loaded line is SHARED, LLC does not get the line
								L1_1_status_fields(first_invalid_line) <= STATE_MODIFIED;
								tag_fields(first_invalid_line) <= addr_one(31 DOWNTO 4);
							END IF;
						END IF;
					
					ELSIF state_nx_i = WAIT_C2C THEN
						ack_one <= '1';
						c2c_two <= '1'; -- Tell Core 1's cache to put make a c2c transaction for the data
						c2c_llc <= '1';
						c2c_addr_two <= addr_one;
						IF we_one = '1' THEN
							-- Also invalidate if the address will be written
							inv_two <= '1';
						END IF;
						
						IF re_one = '1' THEN
							L1_1_status_fields(hit_line_num_one_i) <= STATE_SHARED;
							-- The original cache keeps the line in SHARED as well
							L1_2_status_fields(hit_line_num_one_i) <= STATE_SHARED;
							-- The LLC also gets the line in SHARED
							LLC_status_fields(hit_line_num_one_i)  <= STATE_SHARED;
						ELSIF we_one = '1' THEN
							L1_1_status_fields(hit_line_num_one_i) <= STATE_MODIFIED;
							-- The original cache invalidates the line
							L1_2_status_fields(hit_line_num_one_i) <= STATE_INVALID;
						END IF;

					ELSIF state_nx_i = WAIT_INV THEN
						inv_two <= '1'; -- If a cache does not have the data in SHARED, an ack will be sent right away with no further action
						inv_addr_two <= addr_two;
						inv_llc <= '1';
						inv_addr_llc <= addr_llc;
					END IF;
				END IF;
			END IF;
			
			-- Lower ack signal for requests that have no transition
			IF req_1 = '0' THEN
				ack_one <= '0';
			END IF;
			IF req_2 = '0' THEN
				ack_two <= '0';
			END IF;
			IF evict_llc = '0' THEN
				ack_llc <= '0';
			END IF;
			
			-- Evictions have priority over other changes, L1 evictions are silent to other L1s
			IF current_cpu_i = CPU_ONE THEN
				IF evict_one = '1' THEN
					L1_1_status_fields(evict_line_num_one_i) <= STATE_INVALID;
					IF L1_1_status_fields(evict_line_num_one_i) = STATE_MODIFIED THEN
						LLC_status_fields(evict_line_num_one_i) <= STATE_SHARED;
					END IF;
				ELSIF evict_two = '1' THEN
					L1_2_status_fields(evict_line_num_two_i) <= STATE_INVALID;
					IF L1_2_status_fields(evict_line_num_two_i) = STATE_MODIFIED THEN
						LLC_status_fields(evict_line_num_two_i) <= STATE_SHARED;
					END IF;
				END IF;
			ELSIF current_cpu_i = CPU_TWO THEN
				IF evict_two = '1' THEN
					L1_2_status_fields(evict_line_num_two_i) <= STATE_INVALID;
					IF L1_2_status_fields(evict_line_num_two_i) = STATE_MODIFIED THEN
						LLC_status_fields(evict_line_num_two_i) <= STATE_SHARED;
					END IF;
				ELSIF evict_one = '1' THEN
					L1_1_status_fields(evict_line_num_one_i) <= STATE_INVALID;
					IF L1_1_status_fields(evict_line_num_one_i) = STATE_MODIFIED THEN
						LLC_status_fields(evict_line_num_one_i) <= STATE_SHARED;
					END IF;
				END IF;
			END IF;
		
		ELSIF state_i = WAIT_C2C THEN
			IF state_nx_i <= READY THEN
				ack_one <= '0';
				ack_two <= '0';
				c2c_one <= '0';
				c2c_two <= '0';
				c2c_llc <= '0';
				inv_one <= '0';
				inv_two <= '0';
			END IF;

		ELSIF state_i = WAIT_INV THEN
			IF current_cpu_i = CPU_ONE THEN 
				IF inv_ack_two = '1' THEN
					-- As caches respond to invalidations, mark the data as invalidated in the directory
					L1_2_status_fields(hit_line_num_one_i) <= STATE_INVALID;
					inv_two <= '0';
				ELSE
					inv_two <= '1';
					inv_addr_two <= addr_one;
				END IF;
				IF inv_ack_llc = '1' THEN
					LLC_status_fields(hit_line_num_one_i) <= STATE_INVALID;
					inv_llc <= '0';
				ELSE
					inv_llc <= '1';
					inv_addr_llc <= addr_one;
				END IF;
				
				IF state_nx_i <= READY THEN
					ack_one <= '1';
					inv_two <= '0';
					inv_llc <= '0';
					IF owned_state_S_one = '1' THEN
						-- Loaded line is SHARED, LLC does not get the line
						L1_1_status_fields(hit_line_num_one_i) <= STATE_MODIFIED;
					ELSE
						-- Loaded line is SHARED, LLC does not get the line
						L1_1_status_fields(first_invalid_line) <= STATE_MODIFIED;
					END IF;
				END IF;
			
			ELSIF current_cpu_i = CPU_TWO THEN
				IF inv_ack_one = '1' THEN
					-- As caches respond to invalidations, mark the data as invalidated in the directory
					L1_1_status_fields(hit_line_num_two_i) <= STATE_INVALID;
					inv_one <= '0';
				ELSE
					inv_one <= '1';
					inv_addr_one <= addr_two;
				END IF;
				IF inv_ack_llc = '1' THEN
					LLC_status_fields(hit_line_num_two_i) <= STATE_INVALID;
					inv_llc <= '0';
				ELSE
					inv_llc <= '1';
					inv_addr_llc <= addr_two;
				END IF;
				IF state_nx_i <= READY THEN
					ack_two <= '1';
					inv_one <= '0';
					inv_llc <= '0';
					IF owned_state_S_two = '1' THEN
						-- Loaded line is SHARED, LLC does not get the line
						L1_2_status_fields(hit_line_num_two_i) <= STATE_MODIFIED;
					ELSE 
						-- Loaded line is SHARED, LLC does not get the line
						L1_2_status_fields(first_invalid_line) <= STATE_MODIFIED;
					END IF;
				END IF;
			END IF;
		
		ELSIF state_i = LLC_INV THEN
			IF inv_ack_one = '1' THEN
				-- As caches respond to invalidations, mark the data as invalidated in the directory
				L1_1_status_fields(hit_line_num_llc_i) <= STATE_INVALID;
				inv_one <= '0';
				inv_llc_one <= '0';
			ELSE
				inv_one <= '1';
				inv_llc_one <= '1';
				inv_addr_one <= addr_llc;
			END IF;
			IF inv_ack_two = '1' THEN
				-- As caches respond to invalidations, mark the data as invalidated in the directory
				L1_2_status_fields(hit_line_num_llc_i) <= STATE_INVALID;
				inv_two <= '0';
				inv_llc_two <= '0';
			ELSE
				inv_one <= '1';
				inv_llc_two <= '1';
				inv_addr_two <= addr_llc;
			END IF;
			
			IF present_in_cache = '0' THEN
				inv_one <= '0';
				inv_two <= '0';
				inv_llc_one <= '0';
				inv_llc_two <= '0';
				c2c_one <= '0';
				c2c_two <= '0';
				ack_llc <= '1';
			END IF;
		END IF;
		
		clear_bus(bus_c2c);
	END IF;
END PROCESS execution_process;

req_1 <= we_one OR re_one;
req_2 <= we_two OR re_two;

-- Core 0 will check for a block in SHARED or MODIFIED state in Core 1's cache and LLC, while Core 1 checks Core 0 and the LLC
valid_state_S_one <= has_line_in_S(addr_one, tag_fields, L1_2_status_fields, LLC_status_fields);
valid_state_M_one <= has_line_in_M(addr_one, tag_fields, L1_2_status_fields, LLC_status_fields);
valid_state_S_two <= has_line_in_S(addr_two, tag_fields, L1_1_status_fields, LLC_status_fields);
valid_state_M_two <= has_line_in_M(addr_two, tag_fields, L1_1_status_fields, LLC_status_fields);

-- Each cache checks if it owns a block in SHARED or MODIFIED states
owned_state_S_one <= owns_line_in_S(addr_one, tag_fields, L1_1_status_fields);
owned_state_M_one <= owns_line_in_M(addr_one, tag_fields, L1_1_status_fields);
owned_state_S_two <= owns_line_in_S(addr_two, tag_fields, L1_2_status_fields);
owned_state_M_two <= owns_line_in_M(addr_two, tag_fields, L1_2_status_fields);
owned_state_S_LLC <= owns_line_in_S(addr_llc, tag_fields, LLC_status_fields);

-- Determine if line addr_llc is present in cache
present_state_S_one <= owns_line_in_S(addr_llc, tag_fields, L1_1_status_fields);
present_state_M_one <= owns_line_in_M(addr_llc, tag_fields, L1_1_status_fields);
present_state_S_two <= owns_line_in_S(addr_llc, tag_fields, L1_2_status_fields);
present_state_M_two <= owns_line_in_M(addr_llc, tag_fields, L1_2_status_fields);
present_state_S_LLC <= owns_line_in_S(addr_llc, tag_fields, LLC_status_fields);
present_in_cache    <= present_state_S_one OR present_state_M_one OR present_state_S_two OR present_state_M_two OR present_state_S_LLC;

-- Determine an empty line where new data can be placed
first_invalid_line <= get_empty_line(L1_1_status_fields, L1_2_status_fields, LLC_status_fields);

-- Determine which line has hit
hit_line_num_one_i <= line_hit(addr_one, tag_fields, L1_1_status_fields, L1_2_status_fields, LLC_status_fields);
hit_line_num_two_i <= line_hit(addr_two, tag_fields, L1_1_status_fields, L1_2_status_fields, LLC_status_fields);
hit_line_num_llc_i <= line_hit(addr_llc, tag_fields, L1_1_status_fields, L1_2_status_fields, LLC_status_fields);

-- Determine which line to evict
evict_line_num_one_i <= line_evict(evict_addr_one, tag_fields, L1_1_status_fields);
evict_line_num_two_i <= line_evict(evict_addr_two, tag_fields, L1_2_status_fields);

END directory_behaviour;
