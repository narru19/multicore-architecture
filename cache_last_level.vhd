LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_textio.ALL;
USE std.textio.ALL;
USE work.utils.ALL;

ENTITY cache_last_level IS
	PORT (
		clk             : IN    STD_LOGIC;
		reset           : IN    STD_LOGIC;
		-- LLC-L1 direct signals
		cache0_done_inv : IN    STD_LOGIC;
		cache1_done_inv : IN    STD_LOGIC;
		-- LLC-L1 bus signals
		bus_done        : INOUT STD_LOGIC;
		bus_force_inv   : INOUT STD_LOGIC;
		bus_c2c         : INOUT STD_LOGIC;
		bus_cmd         : INOUT STD_LOGIC_VECTOR(2 DOWNTO 0);
		bus_addr        : INOUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		bus_data        : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		-- LLC-Mem signals
		mem_done        : IN    STD_LOGIC;
		mem_cmd         : OUT   STD_LOGIC_VECTOR(2 DOWNTO 0);
		mem_addr        : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		mem_data        : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		arb_req         : OUT   STD_LOGIC;
		arb_ack         : IN    STD_LOGIC;
		-- LLC-Directory signals
		dir_inv         : IN    STD_LOGIC;                     -- Directory tells LLC it must invalidate an address
		dir_inv_addr    : IN    STD_LOGIC_VECTOR(31 DOWNTO 0); -- The address to invalidate
		dir_inv_ack     : OUT   STD_LOGIC;                     -- LLC tells directory that it has already invalidated
		dir_evict       : OUT   STD_LOGIC;                     -- LLC tells directory it wants to evict a line
		dir_addr        : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0); -- The line to evict
		dir_c2c         : IN    STD_LOGIC;                     -- Whether a C2C transfer is being made
		dir_ack         : IN    STD_LOGIC                      -- The directory tells the LLC it can proceed with the eviction
	);
END cache_last_level;

ARCHITECTURE cache_last_level_behavior OF cache_last_level IS

	TYPE data_fields_t  IS ARRAY(31 DOWNTO 0) OF STD_LOGIC_VECTOR(127 DOWNTO 0);
	TYPE valid_fields_t IS ARRAY(31 DOWNTO 0) OF STD_LOGIC;                      -- Whether a block has valid data
	TYPE tag_fields_t   IS ARRAY(31 DOWNTO 0) OF STD_LOGIC_VECTOR(27 DOWNTO 0);  -- Whether a block is present
	TYPE avail_fields_t IS ARRAY(31 DOWNTO 0) OF STD_LOGIC;                      -- Whether data in the block is available
	
	-- Each line maps to a value in range 0..31 for the LRU algorithm
	TYPE lru_fields_t   IS ARRAY(31 DOWNTO 0) OF INTEGER RANGE 0 TO 31;
	
	-- Fields of the LLC
	SIGNAL data_fields  : data_fields_t;
	SIGNAL valid_fields : valid_fields_t;
	SIGNAL tag_fields   : tag_fields_t;
	SIGNAL avail_fields : avail_fields_t;
	SIGNAL lru_fields   : lru_fields_t;

	-- The next state of the cache
	SIGNAL state_i    : cache_last_level_state_t;
	SIGNAL state_nx_i : cache_last_level_state_t;
	
	-- Determine:
	-- 1 - If there's a hit              -> (VALID == 1 && TAG == ADDR)
	-- 3 - Which line has hit            -> Number representing the hit line
	-- 2 - If the hit block is available -> (VALID == 1 && TAG == ADDR && AVAIL(hit_line_num_i) == 1)
	SIGNAL hit_i          : STD_LOGIC := '0';
	SIGNAL hit_line_num_i : INTEGER RANGE 0 TO 31 := 0;
	SIGNAL hit_avail_i    : STD_LOGIC := '0';

	-- Replacement signals
	SIGNAL repl_i         : STD_LOGIC := '0';
	SIGNAL repl_addr_i    : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL repl_avail_i   : STD_LOGIC := '0';
	SIGNAL lru_line_num_i : INTEGER RANGE 0 TO 31 := 0;

	-- Temporary signals to store a previous request
	-- Used when:
	--   Cache requests a block, LLC needs to replace an invalid block that
	--   maps to the same address, which means it is modified on the other cache. 
	--   Cache requests a block, LLC needs to replace a valid (shared) block
	--   that maps to the same address, which means it is shared on other L1s.
	-- Actions:
	--   Store address requested by cache while faking a request so the other
	--   cache evicts the block.
	SIGNAL tmp_address    : STD_LOGIC_VECTOR(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL priority_req_M : STD_LOGIC := '0';
	SIGNAL priority_req_S : STD_LOGIC := '0';
	
	SIGNAL dir_inv_line_num_i : INTEGER RANGE 0 TO 31 := 0;
	
	-- Determine if there's a hit
	FUNCTION has_access_hit (
		bus_addr     : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields   : tag_fields_t;
		valid_fields : valid_fields_t
	) 
	RETURN STD_LOGIC IS
		VARIABLE tmp_return : STD_LOGIC := '0';
		BEGIN
			FOR i IN 0 TO 31 LOOP
				tmp_return := tmp_return OR to_std_logic(valid_fields(i) = '1' AND tag_fields(i) = bus_addr(31 DOWNTO 4));
			END LOOP;
		RETURN tmp_return;
	END has_access_hit;
	
		-- Determine which line has hit
	FUNCTION line_hit (
		bus_addr     : STD_LOGIC_VECTOR(31 DOWNTO 0);
		tag_fields   : tag_fields_t;
		valid_fields : valid_fields_t
	) 
	RETURN INTEGER IS
		VARIABLE tmp_return : INTEGER := 0;
		BEGIN
			FOR i IN 0 TO 31 LOOP
				IF (tag_fields(i) = bus_addr(31 DOWNTO 4) AND valid_fields(i) = '1') THEN
					tmp_return := i;
				END IF;
			END LOOP;
		RETURN tmp_return;
	END line_hit;
	
	-- Determine the least recently used line
	FUNCTION get_lru_line (lru_fields : lru_fields_t) RETURN INTEGER IS
		VARIABLE tmp_return : INTEGER := 0;
		BEGIN
			FOR i IN 0 to 31 LOOP
				IF lru_fields(i) = 31 THEN
					tmp_return := i;
				END IF;
			END LOOP;
		RETURN tmp_return;
	END get_lru_line;
	
	-- Determine if a replacement is needed
	FUNCTION replace_needed (
		hit_i        : STD_LOGIC;
		valid_fields : valid_fields_t
	) 
	RETURN STD_LOGIC IS
		VARIABLE tmp_return : STD_LOGIC;
		BEGIN
			tmp_return := NOT hit_i;
			FOR i IN 0 TO 31 LOOP
				tmp_return := tmp_return AND valid_fields(i);
			END LOOP;
		RETURN tmp_return;
	END replace_needed;
	
	-- Procedure to reset and initialize the cache
	PROCEDURE reset_cache (
			SIGNAL lru_fields     : OUT lru_fields_t;
			SIGNAL valid_fields   : OUT valid_fields_t;
			SIGNAL avail_fields   : OUT avail_fields_t;
			SIGNAL tmp_address    : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			SIGNAL priority_req_M : OUT STD_LOGIC;
			SIGNAL priority_req_S : OUT STD_LOGIC;
			SIGNAL arb_req        : OUT STD_LOGIC
		) IS
		BEGIN
		-- Initialize LRU and valid fields
		FOR i IN 0 TO 31 LOOP
			lru_fields(i)   <= i;
			valid_fields(i) <= '0';
			avail_fields(i) <= '0';
		END LOOP;
		
		tmp_address    <= (OTHERS => '0');
		priority_req_M <= '0';
		priority_req_S <= '0';
		arb_req        <= '0';
	END PROCEDURE;

	PROCEDURE clear_bus (
			SIGNAL bus_cmd       : OUT STD_LOGIC_VECTOR(2   DOWNTO 0);
			SIGNAL bus_addr      : OUT STD_LOGIC_VECTOR(31  DOWNTO 0);
			SIGNAL bus_data      : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
			SIGNAL bus_done      : OUT STD_LOGIC;
			SIGNAL bus_force_inv : OUT STD_LOGIC;
			SIGNAL bus_c2c       : OUT STD_LOGIC
	) IS
		BEGIN
		bus_cmd       <= (OTHERS => 'Z');
		bus_addr      <= (OTHERS => 'Z');
		bus_data      <= (OTHERS => 'Z');
		bus_done      <= 'Z';
		bus_force_inv <= 'Z';
		bus_c2c       <= 'Z';
	END PROCEDURE;

	PROCEDURE clear_mem (
			SIGNAL mem_cmd  : OUT STD_LOGIC_VECTOR(2   DOWNTO 0);
			SIGNAL mem_addr : OUT STD_LOGIC_VECTOR(31  DOWNTO 0);
			SIGNAL mem_data : OUT STD_LOGIC_VECTOR(127 DOWNTO 0)
	) IS
		BEGIN
		mem_cmd  <= (OTHERS => 'Z');
		mem_addr <= (OTHERS => 'Z');
		mem_data <= (OTHERS => 'Z');
	END PROCEDURE;

	-- Procedure to execute the Least Recently Used algorithm
	PROCEDURE LRU_execute (
			SIGNAL lru_fields : INOUT lru_fields_t;
			SIGNAL line_id    : IN INTEGER RANGE 0 TO 31
	) IS
		BEGIN
		FOR i IN 0 TO 31 LOOP
			IF lru_fields(i) < lru_fields(line_id) THEN
				lru_fields(i) <= lru_fields(i) + 1;
			END IF;
		lru_fields(line_id) <= 0;
		END LOOP;
	END PROCEDURE;
	
	
	-- Check whether an address is in the code zone to avoid forcing invalidations
	FUNCTION is_not_instruction_line (
		addr : STD_LOGIC_VECTOR(31 DOWNTO 0))
		return STD_LOGIC is
	BEGIN
		IF addr < CODE_ZONE_LOWER_LIMIT OR addr > CODE_ZONE_UPPER_LIMIT THEN
			return('1');
		ELSE
			return('0');
		END IF;
	END FUNCTION is_not_instruction_line;
	
	
	BEGIN
	
	-- Process that represents the internal register
	internal_register : PROCESS(clk, reset)
	BEGIN
		IF rising_edge(clk) THEN
			IF reset = '1' THEN
				state_i <= READY;
			ELSE
				state_i <= state_nx_i;
			END IF;
		END IF;
	END PROCESS internal_register;
	
	-- Process that computes the next state of the cache
	next_state_process : PROCESS(clk, reset, state_i, mem_done, arb_ack, hit_i, hit_avail_i, repl_i, repl_avail_i, bus_cmd, bus_done, bus_force_inv, bus_c2c, priority_req_M, priority_req_S, dir_inv, dir_ack, dir_c2c)
	BEGIN
		IF reset = '1' THEN
			state_nx_i <= READY;
			
		ELSIF clk = '1' THEN
			state_nx_i <= state_i;
			
			IF state_i = READY THEN
				-- Special case, the directory tells the LLC to invalidate a line
				IF (dir_inv = '1') THEN
					state_nx_i <= INVALIDATE;
				
				-- Special case, must evict an available block
				ELSIF (priority_req_M = '1' OR priority_req_S = '1') THEN
					state_nx_i <= EVICT_DIR;
				
				ELSIF (bus_cmd = CMD_GET_RO OR bus_cmd = CMD_GETRD OR bus_cmd = CMD_GETWR) THEN
					IF hit_i = '1' THEN
						state_nx_i <= READY;
					ELSE
						IF repl_i = '1' THEN
							IF repl_avail_i = '1' THEN
								-- repl + repl_avail means LLC has the block as Shared and one or more L1s too
								-- Here we will save that we must do a priority request after serving the processor's request 
								-- so that the block replaced can be invalidated from all the L1s that have it
								state_nx_i <= MEM_REQ;  -- READY -> MEM-REQ + Flush Shared L1s
							ELSE
								-- repl + NOT repl_avail means LLC has the block (invalid) and one L1 has it as
								-- modified. Here we will save that we must do a priority request after serving the proc's request
								-- so that the block replaced can be invalidated + evicted + flushed to memory from the L1
								state_nx_i <= MEM_REQ;  -- READY -> MEM_REQ + Flush Modified L1
							END IF;
						ELSE
							state_nx_i <= MEM_REQ;      -- READY -> MEM_REQ
						END IF;
					END IF;
				
				-- If an L1 tries to store a value, we must have it for sure, so update LLC
				ELSIF (bus_cmd = CMD_PUT) THEN
					state_nx_i <= READY;
				END IF;
			
			ELSIF state_i = MEM_REQ THEN
				IF mem_done = '1' THEN
					state_nx_i <= READY;
				END IF;
			
			ELSIF state_i = EVICT_DIR THEN
				IF dir_ack = '1' THEN
					IF priority_req_M = '1' THEN
						state_nx_i <= MEM_PUT;
					ELSIF priority_req_S = '1' THEN
						state_nx_i <= READY;
					END IF;
				END IF;
				
			ELSIF state_i = MEM_PUT THEN
				IF mem_done = '1' THEN
					state_nx_i <= READY;
				END IF;
			
			ELSIF state_i = INVALIDATE THEN
				state_nx_i <= READY;
			END IF;
		END IF;
	END PROCESS next_state_process;

	-- Process that sets the output signals of the cache
	execution_process : PROCESS(clk)
		VARIABLE can_clear_mem : BOOLEAN;
		VARIABLE can_clear_bus : BOOLEAN;
	BEGIN
		can_clear_mem := TRUE;
		can_clear_bus := TRUE;
		
		IF rising_edge(clk) AND reset = '1' THEN
			reset_cache(lru_fields, valid_fields, avail_fields, tmp_address, priority_req_M, priority_req_S, arb_req);
			clear_bus(bus_cmd, bus_addr, bus_data, bus_done, bus_force_inv, bus_c2c);
			clear_mem(mem_cmd, mem_addr, mem_data);
		
		ELSIF falling_edge(clk) AND reset = '0' THEN
			IF state_i = READY THEN
				IF state_nx_i = READY THEN
					IF (bus_cmd = CMD_PUT) THEN
						avail_fields(hit_line_num_i) <= '1';
						data_fields(hit_line_num_i)  <= bus_data;
						bus_done                     <= '1';
						can_clear_bus                := FALSE;
						LRU_execute(lru_fields, hit_line_num_i);
					ELSIF (bus_cmd = CMD_GETRD) OR (bus_cmd = CMD_GETWR) OR (bus_cmd = CMD_GET_RO) THEN
						IF (hit_i = '1' AND hit_avail_i = '1') THEN
							IF (bus_cmd = CMD_GETWR) THEN
								avail_fields(hit_line_num_i) <= '0';
							ELSIF (bus_cmd = CMD_GETRD) OR (bus_cmd = CMD_GET_RO) THEN
								avail_fields(hit_line_num_i) <= '1';
							END IF;
							bus_data      <= data_fields(hit_line_num_i);
							bus_done      <= '1';
							can_clear_bus := FALSE;
						ELSIF (hit_i = '1') THEN
							IF (bus_cmd = CMD_GETWR) THEN
								-- Do nothing, the block will still be modified in the requesting L1
							ELSIF (bus_cmd = CMD_GETRD) THEN
								data_fields(hit_line_num_i)  <= bus_data;
								avail_fields(hit_line_num_i) <= '1';
							END IF;
						END IF;
						LRU_execute(lru_fields, hit_line_num_i);
					END IF;
				
				ELSIF state_nx_i = MEM_REQ THEN
					IF (hit_i = '0' AND repl_i = '1' AND is_not_instruction_line(repl_addr_i) = '1') THEN
						IF (repl_avail_i = '1') THEN
							priority_req_S <= '1';
							tmp_address    <= repl_addr_i;
						ELSE
							priority_req_M <= '1';
							tmp_address    <= repl_addr_i;
						END IF;
					END IF;
					mem_cmd  <= CMD_GETRD; -- Doesn't matter the intention, LLC-Mem connection
					mem_addr <= bus_addr;
					can_clear_mem := FALSE;
				
				ELSIF state_nx_i = EVICT_DIR THEN
					dir_evict <= '1';
					dir_addr  <= tmp_address;
				
				ELSIF state_nx_i = INVALIDATE THEN
					avail_fields(dir_inv_line_num_i) <= '0';
					dir_inv_ack                      <= '1';
				END IF;
			
			ELSIF state_i = MEM_REQ THEN
				IF state_nx_i = READY THEN
					tag_fields(lru_line_num_i)   <= bus_addr(31 DOWNTO 4);
					valid_fields(lru_line_num_i) <= '1';
					bus_data                     <= mem_data;
					bus_done                     <= '1';
					LRU_execute(lru_fields, lru_line_num_i);
					can_clear_bus := FALSE;
					
					IF (bus_cmd = CMD_GET_RO OR bus_cmd = CMD_GETRD) THEN
						data_fields(lru_line_num_i)  <= mem_data;
						avail_fields(lru_line_num_i) <= '1';
					ELSE
						avail_fields(lru_line_num_i) <= '0';
					END IF;
				ELSE
					can_clear_mem := FALSE;
				END IF;
			
			ELSIF state_i = EVICT_DIR THEN
				IF state_nx_i = READY THEN
					priority_req_S <= '0';
					dir_evict      <= '0';
				ELSIF state_nx_i = MEM_PUT THEN
					priority_req_M <= '0';
					dir_evict      <= '0';
					mem_cmd        <= CMD_PUT;
					mem_addr       <= tmp_address;
					mem_data       <= bus_data;
					can_clear_mem  := FALSE;
				END IF;
			
			ELSIF state_i = MEM_PUT THEN
				IF state_nx_i = READY THEN
					-- Do nothing
				ELSE
					can_clear_mem := FALSE;
				END IF;
			
			ELSIF state_i = INVALIDATE THEN
				dir_inv_ack <= '0';
			END IF;
			
			IF dir_c2c = '1' THEN
				IF bus_c2c = '1' AND bus_cmd = CMD_GETRD THEN
					data_fields(hit_line_num_i) <= bus_data;
					avail_fields(hit_line_num_i) <= '1';
				END IF;
			END IF;
			
			IF can_clear_mem THEN
				clear_mem(mem_cmd, mem_addr, mem_data);
			END IF;
			
			IF can_clear_bus THEN
				clear_bus(bus_cmd, bus_addr, bus_data, bus_done, bus_force_inv, bus_c2c);
			END IF;
		END IF;
	END PROCESS execution_process;
	
	-- Determine if the access has hit
	hit_i <= has_access_hit(bus_addr, tag_fields, valid_fields);
	
	-- Determine which line has hit
	hit_line_num_i <= line_hit(bus_addr, tag_fields, valid_fields);
	
	-- Determine which line has hit with the dir_inv_add
	dir_inv_line_num_i <= line_hit(dir_inv_addr, tag_fields, valid_fields);
	
	-- Determine if the hit is in an available block
	hit_avail_i <= (hit_i AND avail_fields(hit_line_num_i));

	-- Determine the least recently used line
	lru_line_num_i <= get_lru_line(lru_fields);

	-- Determine if a replacement is needed
	repl_i       <= replace_needed(hit_i, valid_fields);
	repl_addr_i  <= tag_fields(lru_line_num_i) & "0000";
	repl_avail_i <= (repl_i AND avail_fields(lru_line_num_i));
	
END cache_last_level_behavior;
