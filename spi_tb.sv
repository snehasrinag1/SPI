`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/30/2025 05:36:04 PM
// Design Name: 
// Module Name: spi_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
/////////////////////////////////////////////////////////////////////////////////class transaction;
   
    class transaction;
   rand bit newd;
   rand bit [11:0]din;
   bit cs;
   bit mosi;
   
   function void display(input string tag);
     $display("[%0s]: DATA_NEW:%0b, DIN:%0d, CS:%0b, MOSI:%0b",tag,newd,din,cs,mosi);
   endfunction
   
   function transaction copy();
     copy =new();
     copy.din = this.din;
     copy.newd = this.newd;
     copy.cs = this.cs;
     copy.mosi = this.mosi;
   endfunction
     endclass
 ///////////////////////////////////////////////////////////////////
     
  class generator;
  
    transaction tr;
    mailbox #(transaction) g2d;
    event done;
    event drvnext;
    event sconext;
    int count=0;
    
    function new(mailbox #(transaction) g2d);
     this.g2d= g2d;
      tr=new();
      endfunction
    
    task run();
      repeat(count) begin
        assert(tr.randomize()) else $error("Randomization unsuccessful");
        g2d.put(tr.copy);
        tr.display("GEN");
        @(drvnext);
        @(sconext);
      end
      ->done;
    endtask
  endclass
  
 ////////////////////////////////////////////////////////////////////
     // driver feeds the transaction through interface to DUT
     //driver also sends the transaction for comparison to scoreboard
     //driver also unpacks the transaction into signal level for DUT
     //driver also lets generator know that transaction has been fed to DUT
     //driver resets the DUT first
     
     class driver;
     
     virtual interface spi_if vif;
     transaction tr;
       mailbox #(transaction) g2d;
       mailbox #(bit[11:0]) d2s;
       
      event drvnext; 
   
       function new( mailbox #(transaction) g2d, mailbox #(bit[11:0])d2s);
         this.g2d = g2d;
         this.d2s = d2s;
       endfunction
       
       task reset();
       vif.rst <= 1'b1;
       vif.cs <= 1'b1;
       vif.newd <= 1'b0;
       vif.din <= 1'b0;
       vif.mosi <=1'b0;
       repeat(10) @(posedge vif.clk);
       vif.rst <=1'b0;
       repeat(10) @(posedge vif.clk);
         $display("[DRV]: RESET DONE");
         $display("----------------------------------------------");
       endtask
       
       task run();
       forever begin
         g2d.get(tr);
         @(posedge vif.sclk);
         vif.newd <=1'b1;
         vif.din <= tr.din;
         d2s.put(tr.din);
         @(posedge vif.sclk);
         vif.newd <= 1'b0;
         wait(vif.cs == 1'b1);
         $display("[DRV]:DATA SENT TO SLAVE:%0D",tr.din);
         ->drvnext;
       end
       endtask
       
       endclass
       
  /////////////////////////////////////////////////////////////////////////////
 
       //monitor sends the transaction to the scoreboard for comparison
       
  class monitor;
    transaction tr;
    mailbox #(bit[11:0])m2s; //monitor only sends 12-bit data to scoreboard
    bit [11:0]temp; 
  
   virtual spi_if vif;
    function new(mailbox #(bit[11:0]) m2s);
     this.m2s = m2s;
    endfunction
                 
   task run();              
   forever begin
     @(posedge vif.sclk);
     wait(vif.cs == 1'b0); //waits for chip-select to be low to start the transaction
     
     for(int i=0;i<=11;i++) begin
       @(posedge vif.sclk);
       temp[i]= vif.mosi;
     end
     $display("[MON]: DATA COLLECTED:%0d",temp); 
     wait(vif.cs == 1'b1); //waits for end of transaction
     $display("[MON]: DATA SENT TO SCOREBOARD:%0d",temp);
     m2s.put(temp);
   end
     endtask
 endclass    
      
 //////////////////////////////////////////////////////////////
                 
  class scoreboard;
    
    mailbox #(bit[11:0]) d2s,m2s;
    event sconext;
              
    bit[11:0] ds;
    bit [11:0]ms;
    function new(mailbox #(bit[11:0])d2s, mailbox #(bit[11:0])m2s);
       this.d2s =d2s;
       this.m2s=m2s;
    endfunction
  
   task run();
   forever begin
     d2s.get(ds);
     m2s.get(ms);
    
     $display("[SCO]: DRIVER DATA:%0d MONITOR DATA:%0d", ds,ms);
     
     if(ds == ms)
       $display("[SCO]: DATA MATCHED");
     else 
       $display("[SCO]: DATA MISMATCH");
     
     $display("------------------------------------------");
     ->sconext;
   end
   endtask
 endclass
                          
 //////////////////////////////////////////////////////////////
                          
 class environment;
  
 generator gen;
 driver drv;
 monitor mon;
 scoreboard sco;
 
 event nextgd; // gen->drv
 event nextgs; // gen->sco
   
   mailbox #(transaction) g2d; //gen->drv
   mailbox #(bit [11:0]) d2s; //drv->sco
   mailbox #(bit [11:0]) m2s; //mon->sco
   
   virtual spi_if vif;
   
   function new(virtual spi_if vif);
     g2d= new();
     d2s= new();
     m2s = new();
     gen = new(g2d);
     drv= new(g2d,d2s);
     mon = new(m2s);
     sco = new(d2s,m2s);
     
     this.vif =vif;
     drv.vif = this.vif;
     mon.vif = this.vif;
     
     gen.drvnext = nextgd;
     gen.sconext = nextgs;
     
     drv.drvnext = nextgd;
     sco.sconext = nextgs;
   endfunction
   
   task pre_test();
     drv.reset();
   endtask
   
   task test();
     fork
     gen.run();
     drv.run();
     mon.run();
     sco.run();
     join_any
   endtask
   
   task post_test();
     wait(gen.done.triggered);
     $finish();
   endtask
   
   
   task run();
    pre_test();
    test();
    post_test();
  endtask
 endclass
                 
 ///////////////////////////////////////////////////////////////////
  
 module spi_tb;
   
   spi_if vif();
   
   spi dut(vif.clk, vif.newd, vif.rst, vif.din, vif.sclk, vif.cs, vif.mosi);
   
   initial begin
     vif.clk <=0;
   end
   
   always #10 vif.clk <= ~vif.clk;
   
   environment env;
   
   initial begin
     env = new(vif);
     env.gen.count =20;
     env.run();
   end
   
   initial begin
     $dumpfile("dump.vcd");
     $dumpvars;
   end
   
 endmodule
   
 module spi(
input clk, newd,rst,
input [11:0] din, 
output reg sclk,cs,mosi
    );
  
  typedef enum bit [1:0] {idle = 2'b00, enable = 2'b01, send = 2'b10, comp = 2'b11 } state_type;
  state_type state = idle;
  
  int countc = 0;
  int count = 0;
 
  /////////////////////////generation of sclk
 always@(posedge clk)
  begin
    if(rst == 1'b1) begin
      countc <= 0;
      sclk <= 1'b0;
    end
    else begin 
      if(countc < 10 )   /// fclk / 20
          countc <= countc + 1;
      else
          begin
          countc <= 0;
          sclk <= ~sclk;
          end
    end
  end
  
  //////////////////state machine
    reg [11:0] temp;
    
  always@(posedge sclk)
  begin
    if(rst == 1'b1) begin
      cs <= 1'b1; 
      mosi <= 1'b0;
    end
    else begin
     case(state)
         idle:
             begin
               if(newd == 1'b1) begin
                 state <= send;
                 temp <= din; 
                 cs <= 1'b0;
               end
               else begin
                 state <= idle;
                 temp <= 8'h00;
               end
             end
       
       
       send : begin
         if(count <= 11) begin
           mosi <= temp[count]; /////sending lsb first
           count <= count + 1;
         end
         else
             begin
               count <= 0;
               state <= idle;
               cs <= 1'b1;
               mosi <= 1'b0;
             end
       end
       
                
      default : state <= idle; 
       
   endcase
  end 
 end
  
endmodule
///////////////////////////
 
interface spi_if;
 
  
  logic clk;
  logic newd;
  logic rst;
  logic [11:0] din;
  logic sclk;
  logic cs;
  logic mosi;
  
  
endinterface
 

   
     
   
     
    