module delay_line_D4_O1_6P000 (clk_i,
    clk_o,
    delay_i,
    VSS,
    VDD);
 input clk_i;
 output [0:0] clk_o;
 input [3:0] delay_i;
 inout VSS;
 inout VDD;

 wire clk_l1m0o0;
 wire clk_l1m1o0;
 wire clk_l2m0o0;
 wire clk_l2m1o0;
 wire clk_l2m2o0;
 wire clk_l2m3o0;
 wire clk_l3m0o0;
 wire clk_l3m1o0;
 wire clk_l3m2o0;
 wire clk_l3m3o0;
 wire clk_l3m4o0;
 wire clk_l3m5o0;
 wire clk_l3m6o0;
 wire clk_l3m7o0;
 wire net40;
 wire net1;
 wire net10;
 wire net11;
 wire net12;
 wire net13;
 wire net14;
 wire net15;
 wire net16;
 wire net17;
 wire net18;
 wire net19;
 wire net20;
 wire net21;
 wire net22;
 wire net23;
 wire net24;
 wire net25;
 wire net28;
 wire net29;
 wire net3;
 wire net30;
 wire net32;
 wire net33;
 wire net34;
 wire net48;
 wire net39;
 wire net4;
 wire net41;
 wire net42;
 wire net44;
 wire net45;
 wire net49;
 wire net5;
 wire net50;
 wire net52;
 wire net51;
 wire net54;
 wire net55;
 wire net57;
 wire net58;
 wire net6;
 wire net47;
 wire net66;
 wire net69;
 wire net7;
 wire net70;
 wire net74;
 wire net75;
 wire net53;
 wire net26;
 wire net27;
 wire net31;
 wire net36;
 wire net37;
 wire net43;
 wire net46;

 sg13cmos5l_fill_8 FILLER_0_0 ();
 sg13cmos5l_fill_1 FILLER_0_21 ();
 sg13cmos5l_fill_4 FILLER_0_31 ();
 sg13cmos5l_fill_2 FILLER_0_35 ();
 sg13cmos5l_fill_8 FILLER_0_46 ();
 sg13cmos5l_fill_2 FILLER_0_54 ();
 sg13cmos5l_fill_8 FILLER_0_65 ();
 sg13cmos5l_fill_8 FILLER_0_73 ();
 sg13cmos5l_fill_4 FILLER_0_8 ();
 sg13cmos5l_fill_4 FILLER_0_81 ();
 sg13cmos5l_fill_2 FILLER_0_85 ();
 sg13cmos5l_fill_1 FILLER_0_87 ();
 sg13cmos5l_fill_8 FILLER_10_0 ();
 sg13cmos5l_fill_2 FILLER_10_46 ();
 sg13cmos5l_fill_2 FILLER_10_57 ();
 sg13cmos5l_fill_4 FILLER_10_68 ();
 sg13cmos5l_fill_1 FILLER_10_72 ();
 sg13cmos5l_fill_2 FILLER_10_8 ();
 sg13cmos5l_fill_4 FILLER_10_82 ();
 sg13cmos5l_fill_2 FILLER_10_86 ();
 sg13cmos5l_fill_2 FILLER_11_0 ();
 sg13cmos5l_fill_4 FILLER_11_27 ();
 sg13cmos5l_fill_8 FILLER_11_40 ();
 sg13cmos5l_fill_8 FILLER_11_48 ();
 sg13cmos5l_fill_2 FILLER_11_56 ();
 sg13cmos5l_fill_8 FILLER_11_67 ();
 sg13cmos5l_fill_8 FILLER_11_75 ();
 sg13cmos5l_fill_4 FILLER_11_83 ();
 sg13cmos5l_fill_1 FILLER_11_87 ();
 sg13cmos5l_fill_4 FILLER_1_0 ();
 sg13cmos5l_fill_4 FILLER_1_33 ();
 sg13cmos5l_fill_1 FILLER_1_37 ();
 sg13cmos5l_fill_2 FILLER_1_4 ();
 sg13cmos5l_fill_4 FILLER_1_56 ();
 sg13cmos5l_fill_2 FILLER_1_60 ();
 sg13cmos5l_fill_8 FILLER_1_80 ();
 sg13cmos5l_fill_4 FILLER_2_0 ();
 sg13cmos5l_fill_4 FILLER_2_35 ();
 sg13cmos5l_fill_1 FILLER_2_39 ();
 sg13cmos5l_fill_2 FILLER_2_4 ();
 sg13cmos5l_fill_2 FILLER_2_50 ();
 sg13cmos5l_fill_1 FILLER_2_6 ();
 sg13cmos5l_fill_4 FILLER_2_61 ();
 sg13cmos5l_fill_4 FILLER_2_84 ();
 sg13cmos5l_fill_1 FILLER_3_18 ();
 sg13cmos5l_fill_2 FILLER_3_28 ();
 sg13cmos5l_fill_1 FILLER_3_30 ();
 sg13cmos5l_fill_8 FILLER_3_49 ();
 sg13cmos5l_fill_8 FILLER_3_57 ();
 sg13cmos5l_fill_4 FILLER_3_83 ();
 sg13cmos5l_fill_1 FILLER_3_87 ();
 sg13cmos5l_fill_4 FILLER_4_0 ();
 sg13cmos5l_fill_1 FILLER_4_22 ();
 sg13cmos5l_fill_1 FILLER_4_33 ();
 sg13cmos5l_fill_1 FILLER_4_4 ();
 sg13cmos5l_fill_4 FILLER_4_62 ();
 sg13cmos5l_fill_1 FILLER_4_66 ();
 sg13cmos5l_fill_1 FILLER_4_87 ();
 sg13cmos5l_fill_2 FILLER_5_0 ();
 sg13cmos5l_fill_1 FILLER_5_2 ();
 sg13cmos5l_fill_1 FILLER_5_30 ();
 sg13cmos5l_fill_8 FILLER_5_49 ();
 sg13cmos5l_fill_2 FILLER_5_57 ();
 sg13cmos5l_fill_4 FILLER_5_82 ();
 sg13cmos5l_fill_2 FILLER_5_86 ();
 sg13cmos5l_fill_4 FILLER_6_0 ();
 sg13cmos5l_fill_2 FILLER_6_14 ();
 sg13cmos5l_fill_2 FILLER_6_4 ();
 sg13cmos5l_fill_4 FILLER_6_62 ();
 sg13cmos5l_fill_2 FILLER_6_66 ();
 sg13cmos5l_fill_1 FILLER_6_87 ();
 sg13cmos5l_fill_8 FILLER_7_0 ();
 sg13cmos5l_fill_1 FILLER_7_12 ();
 sg13cmos5l_fill_4 FILLER_7_23 ();
 sg13cmos5l_fill_8 FILLER_7_37 ();
 sg13cmos5l_fill_8 FILLER_7_45 ();
 sg13cmos5l_fill_8 FILLER_7_53 ();
 sg13cmos5l_fill_8 FILLER_7_61 ();
 sg13cmos5l_fill_1 FILLER_7_69 ();
 sg13cmos5l_fill_4 FILLER_7_8 ();
 sg13cmos5l_fill_8 FILLER_8_0 ();
 sg13cmos5l_fill_4 FILLER_8_46 ();
 sg13cmos5l_fill_2 FILLER_8_50 ();
 sg13cmos5l_fill_1 FILLER_8_52 ();
 sg13cmos5l_fill_8 FILLER_8_62 ();
 sg13cmos5l_fill_2 FILLER_8_70 ();
 sg13cmos5l_fill_1 FILLER_8_72 ();
 sg13cmos5l_fill_4 FILLER_8_8 ();
 sg13cmos5l_fill_4 FILLER_8_82 ();
 sg13cmos5l_fill_2 FILLER_8_86 ();
 sg13cmos5l_fill_4 FILLER_9_0 ();
 sg13cmos5l_fill_4 FILLER_9_29 ();
 sg13cmos5l_fill_2 FILLER_9_37 ();
 sg13cmos5l_fill_4 FILLER_9_57 ();
 sg13cmos5l_fill_1 FILLER_9_61 ();
 sg13cmos5l_fill_4 FILLER_9_81 ();
 sg13cmos5l_fill_2 FILLER_9_85 ();
 sg13cmos5l_fill_1 FILLER_9_87 ();
 sg13cmos5l_dlygate4sd2_1 hold1 (.A(net46),
    .X(net1));
 sg13cmos5l_dlygate4sd3_1 hold10 (.A(net11),
    .X(net10));
 sg13cmos5l_dlygate4sd3_1 hold11 (.A(net43),
    .X(net11));
 sg13cmos5l_dlygate4sd3_1 hold12 (.A(net13),
    .X(net12));
 sg13cmos5l_dlygate4sd3_1 hold13 (.A(net15),
    .X(net13));
 sg13cmos5l_dlygate4sd3_1 hold14 (.A(net12),
    .X(net14));
 sg13cmos5l_dlygate4sd2_1 hold15 (.A(net43),
    .X(net15));
 sg13cmos5l_dlygate4sd3_1 hold16 (.A(net18),
    .X(net16));
 sg13cmos5l_dlygate4sd3_1 hold17 (.A(net20),
    .X(net17));
 sg13cmos5l_dlygate4sd3_1 hold18 (.A(net21),
    .X(net18));
 sg13cmos5l_dlygate4sd3_1 hold19 (.A(net16),
    .X(net19));
 sg13cmos5l_dlygate4sd3_1 hold20 (.A(clk_l3m3o0),
    .X(net20));
 sg13cmos5l_dlygate4sd2_1 hold21 (.A(net48),
    .X(net21));
 sg13cmos5l_dlygate4sd3_1 hold22 (.A(net23),
    .X(net22));
 sg13cmos5l_dlygate4sd3_1 hold23 (.A(net25),
    .X(net23));
 sg13cmos5l_dlygate4sd3_1 hold24 (.A(net22),
    .X(net24));
 sg13cmos5l_dlygate4sd3_1 hold25 (.A(net43),
    .X(net25));
 sg13cmos5l_dlygate4sd3_1 hold26 (.A(clk_l3m7o0),
    .X(net26));
 sg13cmos5l_dlygate4sd3_1 hold27 (.A(net74),
    .X(net27));
 sg13cmos5l_dlygate4sd3_1 hold28 (.A(net32),
    .X(net28));
 sg13cmos5l_dlygate4sd3_1 hold29 (.A(net34),
    .X(net29));
 sg13cmos5l_dlygate4sd3_1 hold3 (.A(net46),
    .X(net3));
 sg13cmos5l_dlygate4sd3_1 hold30 (.A(net37),
    .X(net30));
 sg13cmos5l_dlygate4sd3_1 hold31 (.A(clk_l2m3o0),
    .X(net31));
 sg13cmos5l_dlygate4sd3_1 hold32 (.A(clk_l3m4o0),
    .X(net32));
 sg13cmos5l_dlygate4sd3_1 hold33 (.A(net28),
    .X(net33));
 sg13cmos5l_dlygate4sd3_1 hold34 (.A(clk_l2m2o0),
    .X(net34));
 sg13cmos5l_dlygate4sd3_1 hold36 (.A(net54),
    .X(net36));
 sg13cmos5l_dlygate4sd3_1 hold37 (.A(clk_l1m1o0),
    .X(net37));
 sg13cmos5l_dlygate4sd3_1 hold39 (.A(net45),
    .X(net39));
 sg13cmos5l_dlygate4sd3_1 hold4 (.A(net5),
    .X(net4));
 sg13cmos5l_buf_8 hold40 (.A(net40),
    .X(clk_o[0]));
 sg13cmos5l_dlygate4sd3_1 hold41 (.A(net44),
    .X(net41));
 sg13cmos5l_dlygate4sd3_1 hold42 (.A(net39),
    .X(net42));
 sg13cmos5l_dlygate4sd3_1 hold44 (.A(clk_l3m5o0),
    .X(net44));
 sg13cmos5l_dlygate4sd3_1 hold45 (.A(net41),
    .X(net45));
 sg13cmos5l_buf_16 hold46 (.X(net51),
    .A(clk_i));
 sg13cmos5l_dlygate4sd3_1 hold49 (.A(net58),
    .X(net49));
 sg13cmos5l_dlygate4sd3_1 hold5 (.A(net6),
    .X(net5));
 sg13cmos5l_dlygate4sd3_1 hold50 (.A(net36),
    .X(net50));
 sg13cmos5l_dlygate4sd3_1 hold52 (.A(net57),
    .X(net52));
 sg13cmos5l_dlygate4sd3_1 hold54 (.A(net31),
    .X(net54));
 sg13cmos5l_dlygate4sd3_1 hold55 (.A(net50),
    .X(net55));
 sg13cmos5l_dlygate4sd3_1 hold57 (.A(clk_l3m6o0),
    .X(net57));
 sg13cmos5l_dlygate4sd3_1 hold58 (.A(net52),
    .X(net58));
 sg13cmos5l_dlygate4sd2_1 hold6 (.A(net46),
    .X(net6));
 sg13cmos5l_dlygate4sd3_1 hold66 (.A(net75),
    .X(net66));
 sg13cmos5l_dlygate4sd3_1 hold69 (.A(net27),
    .X(net69));
 sg13cmos5l_dlygate4sd3_1 hold7 (.A(net10),
    .X(net7));
 sg13cmos5l_dlygate4sd3_1 hold70 (.A(net66),
    .X(net70));
 sg13cmos5l_dlygate4sd3_1 hold74 (.A(net26),
    .X(net74));
 sg13cmos5l_dlygate4sd3_1 hold75 (.A(net69),
    .X(net75));
 sg13cmos5l_mux2_2 i_mx_l0m0o0 (.A0(clk_l1m0o0),
    .A1(net30),
    .S(delay_i[0]),
    .X(net40));
 sg13cmos5l_mux2_1 i_mx_l1m0o0 (.A0(clk_l2m0o0),
    .A1(clk_l2m1o0),
    .S(delay_i[1]),
    .X(clk_l1m0o0));
 sg13cmos5l_mux2_1 i_mx_l1m1o0 (.A0(net29),
    .A1(net55),
    .S(delay_i[1]),
    .X(clk_l1m1o0));
 sg13cmos5l_mux2_1 i_mx_l2m0o0 (.A0(clk_l3m0o0),
    .A1(clk_l3m1o0),
    .S(delay_i[2]),
    .X(clk_l2m0o0));
 sg13cmos5l_mux2_1 i_mx_l2m1o0 (.A0(clk_l3m2o0),
    .A1(net17),
    .S(delay_i[2]),
    .X(clk_l2m1o0));
 sg13cmos5l_mux2_1 i_mx_l2m2o0 (.A0(net33),
    .A1(net42),
    .S(delay_i[2]),
    .X(clk_l2m2o0));
 sg13cmos5l_mux2_1 i_mx_l2m3o0 (.A0(net49),
    .A1(net70),
    .S(delay_i[2]),
    .X(clk_l2m3o0));
 sg13cmos5l_mux2_1 i_mx_l3m0o0 (.A0(net46),
    .A1(net1),
    .S(delay_i[3]),
    .X(clk_l3m0o0));
 sg13cmos5l_mux2_1 i_mx_l3m1o0 (.A0(net3),
    .A1(net4),
    .S(delay_i[3]),
    .X(clk_l3m1o0));
 sg13cmos5l_mux2_1 i_mx_l3m2o0 (.A0(net7),
    .A1(net14),
    .S(delay_i[3]),
    .X(clk_l3m2o0));
 sg13cmos5l_mux2_1 i_mx_l3m3o0 (.A0(net19),
    .A1(net24),
    .S(delay_i[3]),
    .X(clk_l3m3o0));
 sg13cmos5l_mux2_1 i_mx_l3m4o0 (.A0(net43),
    .A1(net43),
    .S(delay_i[3]),
    .X(clk_l3m4o0));
 sg13cmos5l_mux2_1 i_mx_l3m5o0 (.A0(net43),
    .A1(net43),
    .S(delay_i[3]),
    .X(clk_l3m5o0));
 sg13cmos5l_mux2_1 i_mx_l3m6o0 (.A0(net53),
    .A1(net53),
    .S(delay_i[3]),
    .X(clk_l3m6o0));
 sg13cmos5l_mux2_1 i_mx_l3m7o0 (.A0(net51),
    .A1(net47),
    .S(delay_i[3]),
    .X(clk_l3m7o0));
 sg13cmos5l_buf_8 rebuffer41 (.A(net48),
    .X(net43));
 sg13cmos5l_buf_16 rebuffer42 (.X(net46),
    .A(net47));
 sg13cmos5l_buf_16 rebuffer43 (.X(net47),
    .A(net51));
 sg13cmos5l_buf_1 rebuffer44 (.A(net46),
    .X(net48));
 sg13cmos5l_buf_1 rebuffer47 (.A(net46),
    .X(net53));
endmodule
