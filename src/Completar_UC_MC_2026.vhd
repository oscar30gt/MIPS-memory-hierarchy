---------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    13:38:18 05/15/2014 
-- Design Name: 
-- Module Name:    UC_slave - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: la UC incluye un contador de 2 bits para llevar la cuenta de las transferencias de bloque y una maquina de estados
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity UC_MC_CB is
    Port ( 	
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;

        -- Ordenes del MIPS
        RE : in STD_LOGIC;                  -- Solicitud de lectura del MIPS
        WE : in STD_LOGIC;                  -- Solicitud de escritura del MIPS

        -- Respuesta al MIPS
        ready : out  STD_LOGIC;             -- indica si podemos procesar la orden actual del MIPS en este ciclo. En caso contrario habra que detener el MIPs
        
        -- Señales de la MC
        hit0 : in STD_LOGIC;                -- Se activa si hay acierto en la via 0
        hit1 : in STD_LOGIC;                -- Se activa si hay acierto en la via 1
        via_2_rpl : in STD_LOGIC;           -- Indica que via se va a reemplazar
        addr_non_cacheable : in STD_LOGIC;  -- Indica que la direccion no debe almacenarse en MC. En este caso porque pertenece a la scratch
        internal_addr : in STD_LOGIC;       -- Indica que la direccion solicitada es de un registro de MC
        MC_WE0 : out STD_LOGIC;
        MC_WE1 : out STD_LOGIC;
        
        -- Señales para indicar la operacion que se quiere hacer en el bus
        MC_bus_Read : out STD_LOGIC;        -- para pedir el bus en acceso de lectura
        MC_bus_Write : out STD_LOGIC;       --  para pedir el bus en acceso de escritura
        MC_tags_WE : out STD_LOGIC;         -- para escribir la etiqueta en la memoria de etiquetas
        palabra : out STD_LOGIC_VECTOR (1 downto 0); -- Indica la palabra actual dentro de una transferencia de bloque (1, 2...)
        mux_origen : out STD_LOGIC;         -- Se utiliza para elegir si el origen de la direccion de la palabra y el dato es el Mips (cuando vale 0) o la UC y el bus (cuando vale 1)
        block_addr : out STD_LOGIC;         -- Indica si la direccion a enviar es la de bloque (rm) o la de palabra (w)
        mux_output : out std_logic_vector(1 downto 0); -- Para elegir si le mandamos al procesador la salida de MC (valor 0), los datos que hay en el bus (valor 1), o un registro interno(valor 2)
        
        -- Señales para los contadores de rendimiento de la MC
        inc_m : out STD_LOGIC;              -- indica que ha habido un fallo en MC
        inc_w : out STD_LOGIC;              -- indica que ha habido una escritura en MC
        inc_r : out STD_LOGIC;              -- indica que ha habido una lectura en MC
        inc_cb : out STD_LOGIC;             -- indica que ha habido un reemplazo sucio en MC
        
        -- Gestion de errores
        unaligned : in STD_LOGIC;           -- Indica que la direccion solicitada por el MIPS no esta alineada
        Mem_ERROR : out std_logic;          -- Se activa si en la ultima transferencia el esclavo no respondio a su direccion
        load_addr_error : out std_logic;    -- Para controlar el registro que guarda la direccion que causo error
        
        -- Gestion de los bloques sucios
        send_dirty : out std_logic;         -- Indica que hay que enviar la @ del bloque sucio
        Update_dirty : out STD_LOGIC;       -- Indica que hay que actualizar los bits dirty tanto por que se ha realizado una escritura, como porque se ha enviado el bloque sucio a memoria
        dirty_bit_rpl : in STD_LOGIC;       -- Indica si el bloque a reemplazar es sucio
        Block_copied_back : out STD_LOGIC;  -- Indica que se ha enviado a memoria un bloque que estaba sucio. Se usa para elegir la mascara que quita el bit de sucio
        
        -- Para gestionar las transferencias a traves del bus
        bus_TRDY : in STD_LOGIC;            -- Indica que la memoria puede realizar la operacion solicitada en este ciclo
        Bus_DevSel : in STD_LOGIC;          -- Indica que la memoria ha reconocido que la direccion esta dentro de su rango
        Bus_grant : in STD_LOGIC;           -- Indica la concesion del uso del bus
        MC_send_addr_ctrl : out STD_LOGIC;  -- Ordena que se envien la direccion y las señales de control al bus
        MC_send_data : out STD_LOGIC;       -- Ordena que se envien los datos
        Frame : out STD_LOGIC;              -- Indica que la operacion no ha terminado
        last_word : out STD_LOGIC;          -- Indica que es el ultimo dato de la transferencia
        Bus_req : out STD_LOGIC;            -- Indica la peticion al arbitro del uso del bus

        -- Señales para apartados optativos --
        
        is_idle : out std_logic;                    -- Se activa cuando la UC esta en el estado IDLE
        req_word : in std_logic_vector(1 downto 0); -- Indica que palabra del bloque se ha pedido en una lectura de bloque (1, 2, 3 o 4)
        background_read : out std_logic;            -- Indica que se esta realizando una lectura de bloque en segundo plano (se puede seguir atendiendo al MIPS mientras se hace la transferencia)
        background_write : out std_logic            -- Indica que se esta realizando una escritura writearound en segundo plano (se puede seguir atendiendo al MIPS mientras se hace la transferencia)
    );
end UC_MC_CB;

architecture Behavioral of UC_MC_CB is

component counter is 
	generic (
	   size : integer := 10
	);
	Port ( 
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;
        count_enable : in STD_LOGIC;
        count : out STD_LOGIC_VECTOR (size-1 downto 0)
	);
end component;		 

-- Ctes. para los muxes
constant MUX_ORIGIN_MIPS : std_logic := '0'; -- Valor de mux_origen para elegir el MIPS como origen de la direccion y los datos
constant MUX_ORIGIN_UC : std_logic := '1'; -- Valor de mux_origen para elegir la UC y el bus como origen de la direccion y los datos
constant MUX_OUTPUT_MC : std_logic_vector(1 downto 0) := "00"; -- Valor de mux_output para elegir la salida de MC
constant MUX_OUTPUT_BUS : std_logic_vector(1 downto 0) := "01"; -- Valor de mux_output para elegir la salida del bus
constant MUX_OUTPUT_INTERNAL : std_logic_vector(1 downto 0) := "10"; -- Valor de mux_output para elegir la salida de un registro interno de la UC

-- Estados de la UC
type state_type is (IDLE, BUS_REQUEST, COPYBACK_ADDRESS, COPYBACK_TRANSFER, WORD_ADDRESS, WORD_TRANSFER, BLOCK_ADDRESS, BLOCK_TRANSFER); 
type error_type is (memory_error, No_error); 
signal state, next_state : state_type; 
signal error_state, next_error_state : error_type; 
signal last_word_block: STD_LOGIC;          -- Se activa cuando se esta pidiendo la ultima palabra de un bloque
signal one_word: STD_LOGIC;                 -- Se activa cuando solo se quiere transferir una palabra
signal next_one_word: STD_LOGIC;            -- Se asignara este valor a one_word en el siguiente ciclo de reloj.
signal count_enable: STD_LOGIC;             -- Se activa si se ha recibido una palabra de un bloque para que se incremente el contador de palabras
signal hit: std_logic;
signal palabra_UC : STD_LOGIC_VECTOR (1 downto 0);
signal internal_background_read : std_logic;
signal next_background_read : std_logic;
signal internal_background_write : std_logic;
signal next_background_write : std_logic;

begin

background_read <= internal_background_read;
background_write <= internal_background_write;

hit <= hit0 or hit1;	
 
-- el contador nos dice cuantas palabras hemos recibido. Se usa para saber cuando se termina la transferencia del bloque y para direccionar la palabra en la que se escribe el dato leido del bus en la MC
word_counter: counter generic map (size => 2)
					  port map (clk, reset, count_enable, palabra_UC); -- indica la palabra actual dentro de una transferencia de bloque (1, 2...)

last_word_block <= '1' when palabra_UC="11" else '0'; -- se activa cuando estamos pidiendo la ultima palabra

palabra <= palabra_UC;

-- Maquina de estados principal
State_reg: process (clk)
begin
    if (clk'event and clk = '1') then
        if (reset = '1') then
            state <= IDLE;
            one_word <= '0';
            internal_background_read <= '0';
            internal_background_write <= '0';
        else
            state <= next_state;
            one_word <= next_one_word;
            internal_background_read <= next_background_read;
            internal_background_write <= next_background_write;
        end if;        
    end if;
end process;
 
-- Maquina de estados para el bit de error
error_reg: process (clk)
begin
    if (clk'event and clk = '1') then
        if (reset = '1') then           
            error_state <= No_error;
        else
            error_state <= next_error_state;
        end if;   
    end if;
end process;
   
-- Salida Mem Error
Mem_ERROR <= '1' when (error_state = memory_error) else '0';
   
-- MEALY State-Machine - Outputs based on state and inputs
OUTPUT_DECODE: process (
    state, hit, last_word_block, bus_TRDY, RE, WE, Bus_DevSel, Bus_grant, via_2_rpl, palabra_UC,
    hit0, hit1, dirty_bit_rpl, addr_non_cacheable, internal_addr, unaligned, error_state, one_word
) begin
    
    -- DEFAULT VALUES
	MC_WE0 <= '0';
	MC_WE1 <= '0';
	MC_bus_Read <= '0';
	MC_bus_Write <= '0';
	MC_tags_WE <= '0';
    mux_origen <= MUX_ORIGIN_MIPS;
    MC_send_addr_ctrl <= '0';
    MC_send_data <= '0';
    next_state <= state;  
	count_enable <= '0';
	Frame <= '0';
	block_addr <= '0';
	inc_m <= '0';
	inc_w <= '0';
	inc_r <= '0';
	inc_cb <= '0';
	Bus_req <= '0';
	mux_output <= MUX_OUTPUT_MC;
	last_word <= '0';
	next_error_state <= error_state; 
	load_addr_error <= '0';
	send_dirty <= '0';
	Update_dirty <= '0';
	Block_copied_back <= '0';
    next_one_word <= '0';
    next_background_read <= '0';
    next_background_write <= '0';
    ready <= internal_background_read or internal_background_write;
    is_idle <= '0';

    CASE state is 

        ---------------------------------------------------------------------------------------
        ---- IDLE -----------------------------------------------------------------------------
        ---------------------------------------------------------------------------------------
		when IDLE => 			
            is_idle <= '1';

            -- T1: IDLE (no hay solicitud de lectura ni escritura)
            if (RE = '0' and WE = '0') then
                ready <= '1';
                next_state <= IDLE;

            -- T2: Error de alineamiento
            elsif (unaligned = '1') then
                ready <= '1';
                load_addr_error <= '1';
                next_error_state <= memory_error;
                next_state <= IDLE;

            -- T3: Lectura registro interno (Limpia error)
            elsif (RE = '1' and internal_addr = '1') then
                ready <= '1';
                mux_output <= MUX_OUTPUT_INTERNAL;
                next_error_state <= No_error;
                next_state <= IDLE;

            -- T4: Escritura registro interno (Error)
            elsif (WE = '1' and internal_addr = '1') then
                ready <= '1';
                next_error_state <= memory_error;
                load_addr_error <= '1';
                next_state <= IDLE;

            -- T5: Acierto en lectura
            elsif (RE = '1' and hit = '1') then
                ready <= '1';
                inc_r <= '1';
                mux_output <= MUX_OUTPUT_MC;
                next_state <= IDLE;

            -- T6: Acierto en escritura
            elsif (WE = '1' and hit = '1') then
                ready <= '1';
                inc_w <= '1';
                MC_WE0 <= hit0; -- Escribe en la via en la que se hace el hit
                MC_WE1 <= hit1;
                Update_dirty <= '1';
                next_state <= IDLE;

            -- T13: Acceso a scratch (No cacheable)
            elsif (addr_non_cacheable = '1') then
                next_one_word <= '1'; -- La scratch no trabaja con bloques, solo leemos o escribimos una palabra
                Bus_req <= '1';
                next_state <= BUS_REQUEST;
                inc_r <= RE;
                inc_w <= WE;

            -- T7: Fallo en lectura con bloque sucio (Copyback)
            elsif (RE = '1' and dirty_bit_rpl = '1') then
                inc_m <= '1';
                Bus_req <= '1';
                next_state <= COPYBACK_ADDRESS;
                inc_r <= '1';

            -- T14: Fallo con bloque limpio
            else
                inc_m <= '1';
                if (RE = '1') then
                    inc_r <= '1';
                elsif (WE = '1') then
                    inc_w <= '1';
                    next_one_word <= '1'; -- Al escribir, solo escribimos una palabra
                    
                    --------- Comentar para desactivar la extension "basic lockup-free cache" ---------
                    next_background_write <= '1';
                    ready <= '1';
                    -----------------------------------------------------------------------------------
                end if;
                Bus_req <= '1';
                next_state <= BUS_REQUEST;

            end if;
            
        ---------------------------------------------------------------------------------------
        ---- COPYBACK ADDRESS -----------------------------------------------------------------
        ---------------------------------------------------------------------------------------
        when COPYBACK_ADDRESS =>

            Bus_req <= '1';
            Frame <= '1';           -- Iniciamos fase de dirección
            MC_send_addr_ctrl <= '1';
            MC_bus_Write <= '1';
            block_addr <= '1';
            send_dirty <= '1';
            mux_origen <= MUX_ORIGIN_UC;

            -- T8: Volvemos al inicio porque ningun dispositivo responde a la direccion (fallo de memoria)
            if (Bus_DevSel = '0') then
                ready <= '1';
                next_error_state <= memory_error;
                load_addr_error <= '1';
                next_state <= IDLE;

            -- T9: Un dispositivo responde a la direccion (iniciar transferencia)
            else
                next_state <= COPYBACK_TRANSFER;

            end if;

        ----------------------------------------------------------------------------------------
        ---- COPYBACK TRANSFER -----------------------------------------------------------------
        ----------------------------------------------------------------------------------------
        when COPYBACK_TRANSFER =>

            mux_origen <= MUX_ORIGIN_UC;
            Frame <= '1';
            MC_bus_Write <= '1';
            Bus_req <= '1'; -- Mantenemos petición para el siguiente paso (la lectura)

            -- T10: Esperando a que el dispositivo esté listo para la transferencia
            if (bus_TRDY = '0') then
                next_state <= COPYBACK_TRANSFER;

            else
                count_enable <= '1';
                MC_send_data <= '1';

                -- T11: Todavia no se ha enviado la ultima palabra del bloque, seguimos en el ciclo de copyback
                if (last_word_block = '0') then
                    next_state <= COPYBACK_TRANSFER;


                -- T12: Se ha enviado la ultima palabra del bloque, pedimos el bus para la lectura del bloque nuevo
                else
                    last_word <= '1';
                    Block_copied_back <= '1';
                    Update_dirty <= '1';
                    inc_cb <= '1';
                    next_state <= BUS_REQUEST;
                end if;

            end if;

        ---------------------------------------------------------------------------------------
        ---- BUS REQUEST ----------------------------------------------------------------------
        ---------------------------------------------------------------------------------------
        when BUS_REQUEST =>

            next_one_word <= one_word;
            next_background_write <= internal_background_write;

            -- T15: Esperando el bus para la operación de carga/lectura
            if (Bus_grant = '0') then
                Bus_req <= '1';
                next_state <= BUS_REQUEST;

            -- T22: Bus concedido para palabra única
            elsif (one_word = '1' or addr_non_cacheable = '1') then
                Bus_req <= '1';
                MC_bus_Read <= RE;
                MC_bus_Write <= WE;
                next_state <= WORD_ADDRESS;

            -- T16: Bus concedido para bloque
            else
                Bus_req <= '1';
                MC_bus_Read <= '1';
                next_state <= BLOCK_ADDRESS;

            end if;

        ----------------------------------------------------------------------------------------
        ---- BLOCK ADDRESS ---------------------------------------------------------------------
        ----------------------------------------------------------------------------------------
        when BLOCK_ADDRESS =>

            Frame <= '1';
            MC_send_addr_ctrl <= '1';
            mux_origen <= MUX_ORIGIN_UC;
            block_addr <= '1';
            Bus_req <= '1';
            MC_bus_Read <= '1';

            -- T17: Ningún dispositivo responde a la dirección (fallo de memoria)
            if (Bus_DevSel = '0') then
                ready <= '1';
                next_error_state <= memory_error;
                load_addr_error <= '1';
                next_state <= IDLE;
               
            -- T18: Un dispositivo responde a la dirección (iniciar transferencia)
            else
                next_state <= BLOCK_TRANSFER;
            end if;
        
        ----------------------------------------------------------------------------------------
        ---- BLOCK TRANSFER --------------------------------------------------------------------
        ----------------------------------------------------------------------------------------
        when BLOCK_TRANSFER =>

            mux_output <= MUX_OUTPUT_BUS;
            mux_origen <= MUX_ORIGIN_UC;
            Frame <= '1';

            -------- Commentar para desactivar la extension "critical word forwarding" --------
            if ((bus_TRDY = '1' and palabra_UC = req_word) or palabra_UC > req_word) then
                ready <= '1';
                next_background_read <= '1';
            end if;
            -----------------------------------------------------------------------------------

            -- T19: Esperando a que el dispositivo esté listo para la transferencia
            if (bus_TRDY = '0') then
                MC_bus_Read <= '1';
                next_state <= BLOCK_TRANSFER;
                
            -- T20: Se ha recibido la ultima palabra del bloque, respondemos al MIPS
            elsif (last_word_block = '1') then
                last_word <= '1';
                count_enable <= '1';
                MC_WE0 <= not via_2_rpl;
                MC_WE1 <= via_2_rpl;
                MC_tags_WE <= '1';
                next_state <= IDLE;
                next_background_read <= '0';

            -- T21: Se ha recibido una palabra del bloque pero no es la ultima, continuamos con la transferencia
            else
                MC_bus_Read <= '1';
                count_enable <= '1';
                MC_WE0 <= not via_2_rpl;
                MC_WE1 <= via_2_rpl;
                next_state <= BLOCK_TRANSFER;

            end if;

        ---------------------------------------------------------------------------------------
        ---- WORD ADDRESS ---------------------------------------------------------------------
        ---------------------------------------------------------------------------------------
        when WORD_ADDRESS =>

            Frame <= '1';
            MC_send_addr_ctrl <= '1';
            Bus_req <= '1';
            MC_bus_Read <= RE;
            MC_bus_Write <= WE;
 
            -- T23: Ningún dispositivo responde a la dirección (fallo de memoria)
            if (Bus_DevSel = '0') then
                ready <= '1';
                next_error_state <= memory_error;
                load_addr_error <= '1';
                next_state <= IDLE;

            -- T24: Un dispositivo responde a la dirección (iniciar transferencia)
            else
                next_background_write <= internal_background_write;
                next_state <= WORD_TRANSFER;
            end if;

        ----------------------------------------------------------------------------------------
        ---- WORD TRANSFER ---------------------------------------------------------------------
        ----------------------------------------------------------------------------------------
        when WORD_TRANSFER =>

            Frame <= '1';
            MC_send_data <= WE;
        
            -- T27: Esperando a que el dispositivo esté listo para la transferencia
            if (bus_TRDY = '0') then
                MC_bus_Read <= RE;
                MC_bus_Write <= WE;
                next_state <= WORD_TRANSFER;
                next_background_write <= internal_background_write;
                
            else
                ready <= '1';
                last_word <= '1';
                next_state <= IDLE;
                next_background_write <= '0';
                
                -- T25: Lectura de scratch (el dato esta en el bus en este ciclo)
                if (RE = '1') then
                    mux_output <= MUX_OUTPUT_BUS;
                    
                -- T26: Fin escritura (writearound o escritura en scratch)
                else
                    mux_output <= MUX_OUTPUT_MC;

                end if;
            end if;

        -- Por defecto (no deberia ocurrir)
		WHEN others => next_state <= IDLE;
	end CASE;
	
end process; 
end Behavioral;