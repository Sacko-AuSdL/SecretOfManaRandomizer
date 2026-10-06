function Assert-SlimeDialogueReset([byte[]]$Rom,[byte[]]$Original) {
    if(-not ('SlimeDialogueMachine' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'SlimeDialogueMachine.cs') }
    if($Rom[0xBC45] -ne 0x22 -or $Rom[0xBC49] -ne 0xEA) { throw 'Shared stage dialogue hook missing.' }
    $hook=[int]$Rom[0xBC46]+([int]$Rom[0xBC47]-shl 8)+([int]$Rom[0xBC48]-shl 16)
    foreach($mapId in @(0x1FB,260,0x1FA,0x1F6,0x1E8,0x1E9,0xFA)) {
        $machine=[SlimeDialogueMachine]::new($Rom)
        $machine.A=0xBEEF; $machine.X=0x1234; $machine.Y=0x5678; $machine.P=0xA1
        $machine.Write(0x7E00DC,$mapId,2)
        $machine.Write(0x7EA162,1,1)  # compact inherited Mode-7 window
        $machine.Write(0x7EA15C,7,1)  # previous opener completed, NOT a fresh open
        $machine.Write(0x7EA15D,6,1)
        $machine.Write(0x7E1D00,0x80,1); $machine.Write(0x7E1D04,0x20,1)
        $machine.Write(0x7E1D12,0x20,1); $machine.Write(0x7E1D10,1,1)
        $machine.Write(0x7E039F,0xCA,1); $machine.Write(0x7EFE00,0xBA,1)
        $machine.Run($hook,$true)
        if($machine.A -ne 0xBEEF -or $machine.X -ne 0x34 -or $machine.Y -ne 0x78 -or $machine.P -ne 0xB1 -or $machine.DB -ne 0x7E) { throw 'Map hook register/status preservation differs from displaced STZ/SEP.' }
        if($machine.Read(0x7E1D04,1) -ne 0) { throw 'Displaced map-loader STZ was not replayed.' }
        if($machine.Read(0x7E039F,1) -ne 0xCA -or $machine.Read(0x7EFE00,1) -ne 0xBA) { throw 'Dialogue reset changed notification queue.' }
        if($mapId -eq 0x1FB) {
            foreach($address in @(0x7EA162,0x7EA15C,0x7EA15D,0x7E1D00,0x7E1D12,0x7E1D10)) {
                if($machine.Read($address,1) -ne 0) { throw ('Stale dialogue state after staging load: {0:X6}' -f $address) }
            }
            # Execute vanilla C0:0D8B: fresh regular descriptor has 3 lines,
            # 6 tile rows; it must NOT use compact descriptor's 1 line/2 rows.
            $machine.P=0x20; $machine.Write(0x7EA170,0x50,1)
            $machine.Run(0xC00D8B,$false)
            if($machine.Read(0x7EA169,1) -ne 3 -or $machine.Read(0x7EA16B,1) -ne 6) { throw 'Fresh stage did not select vanilla three-line geometry.' }
        } else {
            if($machine.Read(0x7EA162,1) -ne 1 -or $machine.Read(0x7EA15C,1) -ne 7 -or $machine.Read(0x7E1D12,1) -ne 0x20) { throw 'Dialogue hook changed an unrelated/native map.' }
        }
    }
}
