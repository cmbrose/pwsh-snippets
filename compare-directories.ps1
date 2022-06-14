param(
	[string]$expected,
	[string]$actual,
	[switch]$compareContent
)

function compare-directories-internal {
	param(
		[string]$expectedRoot,
		[string]$expectedRelative,
		[string]$actualRoot,
		[string]$actualRelative
	)
	
	Write-Host "$expectedRelative\"
	
	$fullExpected = Join-Path $expectedRoot $expectedRelative
	$fullActual = Join-Path $actualRoot $actualRelative
	
	$expectedFiles = Get-ChildItem -File -Path $fullExpected
	$actualFiles = Get-ChildItem -File -Path $fullActual
	
	$expectedFiles | % {
		$expectedFile = $_
		$actualFile = $actualFiles | ? { $_.Name -eq $expectedFile.Name }
		if ($actualFile) {
			if ($compareContent) {
				$expectedContent = (Get-Content $expectedFile) -join "`n"
				$actualContent = (Get-Content $actualFile) -join "`n"

				if ($expectedContent -ne $actualContent) {
					Write-Warning "$($expectedFile.Name) content differed"
				}
			}

			return
		}
		
		$actualDir = $actualDirs | ? { $_.Name -eq $expectedFile.Name }
		if ($actualDir) {
			Write-Warning "$($expectedFile.Name) should be a file, but is a directory"
			return
		}
		
		Write-Warning "File $($expectedFile.Name) is missing"
	}
	
	$expectedDirs = Get-ChildItem -Directory -Path $fullExpected
	$actualDirs = Get-ChildItem -Directory -Path $fullActual
		
	$expectedDirs | % {
		$expectedDir = $_
		$actualDir = $actualDirs | ? { $_.Name -eq $expectedDir.Name }
		if ($actualDir) {
			$newExpectedRelative = Join-Path $expectedRelative $expectedDir.Name
			$newActualRelative = Join-Path $actualRelative $expectedDir.Name
			
			compare-directories-internal $expectedRoot $newExpectedRelative $actualRoot $newActualRelative
			
			return
		}
		
		$actualFile = $actualFiles | ? { $_.Name -eq $expectedDir.Name }
		if ($actualFile) {
			Write-Warning "$($expectedDir.Name) should be a directory, but is a file"
			return
		}
		
		Write-Warning "Directory $($expectedDir.Name) is missing"
	}
}

compare-directories-internal $expected . $actual .