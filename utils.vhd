LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

PACKAGE utils IS
	FUNCTION to_std_logic(value : BOOLEAN) RETURN STD_LOGIC;
	FUNCTION is_cmd(cmd : STD_LOGIC_VECTOR(2 DOWNTO 0)) RETURN BOOLEAN;
	FUNCTION is_all_X(s : STD_LOGIC_VECTOR) RETURN BOOLEAN;
	
	TYPE data_cache_state_t       IS (READY, WAITSB, WAIT_DIR, ARBREQ, MEMREQ, FINISH_EVICT, EVICT_ARB, EVICT_MEM);
	TYPE obs_data_cache_state_t   IS (READY, WAITSB);
	TYPE inst_cache_state_t       IS (READY, ARBREQ, LINEREQ);
	TYPE store_buffer_state_t     IS (READY, FLUSHING, FLUSHED);
	TYPE memory_block_state_t     IS (AVAIL, NOTAVAIL);
	TYPE cache_last_level_state_t IS (READY, MEM_REQ, INVALIDATE, EVICT_DIR, MEM_PUT);
	TYPE directory_state_t        IS (READY, BUS_REQ, WAIT_BLOCK, WAIT_C2C, WAIT_INV, LLC_INV);
	
	CONSTANT REG_EXC_CODE : STD_LOGIC_VECTOR := x"1E";
	CONSTANT REG_EXC_DATA : STD_LOGIC_VECTOR := x"1F";
	
	CONSTANT INST_TYPE_NOP : STD_LOGIC_VECTOR := "00";
	CONSTANT INST_TYPE_ALU : STD_LOGIC_VECTOR := "01";
	CONSTANT INST_TYPE_MEM : STD_LOGIC_VECTOR := "10";
	CONSTANT INST_TYPE_MUL : STD_LOGIC_VECTOR := "11";
	
	CONSTANT MEMORY_BLOCKS      : INTEGER := 16384;
	CONSTANT MEMORY_BLOCKS_BITS : INTEGER := 14;
	
	CONSTANT CMD_NOP    : STD_LOGIC_VECTOR(2 DOWNTO 0) := "000";
	CONSTANT CMD_GETWR  : STD_LOGIC_VECTOR(2 DOWNTO 0) := "001"; -- Get with intention to Read
	CONSTANT CMD_GETRD  : STD_LOGIC_VECTOR(2 DOWNTO 0) := "010"; -- Get with intention to Write
	CONSTANT CMD_PUT    : STD_LOGIC_VECTOR(2 DOWNTO 0) := "011";
	CONSTANT CMD_GET_RO : STD_LOGIC_VECTOR(2 DOWNTO 0) := "100"; -- Get Read Only (instruction cache)
	
	CONSTANT CPU_NONE : STD_LOGIC_VECTOR(1 DOWNTO 0) := "00";
	CONSTANT CPU_ONE  : STD_LOGIC_VECTOR(1 DOWNTO 0) := "01";
	CONSTANT CPU_TWO  : STD_LOGIC_VECTOR(1 DOWNTO 0) := "10";
	
	CONSTANT STATE_INVALID  : STD_LOGIC_VECTOR := "00";
	CONSTANT STATE_MODIFIED : STD_LOGIC_VECTOR := "10";
	CONSTANT STATE_SHARED   : STD_LOGIC_VECTOR := "01";
	
	CONSTANT CODE_ZONE_LOWER_LIMIT : STD_LOGIC_VECTOR(31 DOWNTO 0) := x"00001000";
	CONSTANT CODE_ZONE_UPPER_LIMIT : STD_LOGIC_VECTOR(31 DOWNTO 0) := x"00002FFF";
	
	
END utils;

PACKAGE BODY utils IS
	FUNCTION to_std_logic(value : BOOLEAN) RETURN STD_LOGIC IS
	BEGIN
		IF value THEN
			RETURN('1');
		ELSE
			RETURN('0');
		END IF;
	END FUNCTION to_std_logic;

	FUNCTION is_cmd(cmd : STD_LOGIC_VECTOR(2 DOWNTO 0)) RETURN BOOLEAN IS
	BEGIN
		IF cmd(0) = 'Z' OR cmd (1) = 'Z' OR cmd(2) = 'Z' THEN
			RETURN(FALSE);
		ELSE
			RETURN(TRUE);
		END IF;
	END FUNCTION is_cmd;

	FUNCTION is_all_X(s : STD_LOGIC_VECTOR) RETURN BOOLEAN IS
    BEGIN
        FOR i IN s'RANGE LOOP
            CASE s(i) IS
                WHEN 'U' | 'X' | 'Z' | 'W' | '-' => NULL;
                WHEN OTHERS => RETURN FALSE;
            END CASE;
        END LOOP;
        RETURN TRUE;
    END;
END utils;
