class program_image extends uvm_object;
    `uvm_object_utils(program_image)


    bit [31:0] PM [int unsigned];
    bit [31:0] linear_instr_q[$];
    int unsigned image_words;

    function new(string name = "program_image");
        super.new(name);
    endfunction

    virtual function void clear();
        PM.delete();
        linear_instr_q.delete();
        image_words = 0;
    endfunction

    function void put_instr(bit [31:0] pc, bit [31:0] instr);
        int unsigned word_addr;
        word_addr = pc >> 2;
        PM[word_addr] = instr;
        linear_instr_q.push_back(instr);
        if ((word_addr + 1) > image_words) begin
            image_words = word_addr + 1;
        end
    endfunction

    function bit [31:0] read_instr(bit [31:0] pc);
        if (PM.exists(pc >> 2)) begin
            return PM[pc >> 2];
        end
        else begin
            return 32'h0000_0013; // ADDI x0, x0, 0，NOP
        end
    endfunction

    function int unsigned instr_count();
        return image_words;
    endfunction

    task load_mem(string file_name);
        int fd;
        int code;
        int unsigned word_addr;
        bit [31:0] instr;
        string line;

        clear();
        fd = $fopen(file_name, "r");
        if (fd == 0) begin
            `uvm_fatal("PROGRAM_IMAGE", $sformatf("Failed to open mem file: %s", file_name))
        end

        word_addr = 0;
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%h", instr);
            if (code == 1) begin
                put_instr(word_addr << 2, instr);
                word_addr++;
            end
            else begin
                void'($fgets(line, fd));
            end
        end

        $fclose(fd);
        `uvm_info("PROGRAM_IMAGE", $sformatf(
            "Loaded %0d instruction words from %s", instr_count(), file_name), UVM_LOW)
    endtask

endclass
