using module C:\src\codespaces-service\src\service\tools\Powershell\codespaces-db
using module C:\src\codespaces-service\src\service\tools\Powershell\github-utils

. C:\src\codespaces-service\src\service\tools\Powershell\utils\value-cache.ps1

$env:PATH += ";C:\src\codespaces-service\src\service\tools\Powershell"

$src="c:\src"
$devenv="C:\Program Files\Microsoft Visual Studio\2022\Preview\Common7\IDE\devenv.exe"
$vsCmd="C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Visual Studio 2022\Visual Studio Tools\Developer Command Prompt for VS 2022 Int Preview.lnk"

$env:path="$env:path;C:\Program Files\OpenSSL\bin"
$env:OPENSSL_CONF="C:\openssl\openssl.cnf"

$gitBranchPrefix="dev/bcaleb"

$cascade="$src\Cascade"
$cascade2="$cascade-2"

$core="$src\vsclk-core"
$core2="$core-2"

$sdk="$src\vssaas-sdk"

$codespaces="$src\codespaces"
$cxc="$src\codespaces-service"

$cascadeRepos = @($cascade, ""), @($cascade2, "-2")
$coreRepos = @($core, ""), @($core2, "-2")
$sdkRepos = , @($sdk, "") # use the leading comma here because there is only 1 item
$codespacesRepos = , @($codespaces, "") # use the leading comma here because there is only 1 item
$cxcRepos = , @($cxc, "") # use the leading comma here because there is only 1 item

$codespacesSettingsDir="$home\codespaces-settings"
$codespacesSettingsFile="$home\codespaces-settings.json"

# Everything under here should be able to just be parameterized

$extDir="vscode\codespaces"
$extSln="codespaces.code-workspace"

$agentDir="src\VSOnline"
$agentSln="VSOnline.sln"

$portalDir="src\Portal\PortalWebsite\Src\Website"
$portalSln="." # No solution, just open the dir

$serviceDir="src"
$serviceSln="Ide\CloudEnvironmentsServices.sln"

$sdkDir="."
$sdkSln="vssaas-sdk.sln"

# All repos that go through __setup-project are added to this automatically
$knownRepos=@(
    @{ Path = "$src\vssaas-planning"; Name = "vssaas-planning" }
    @{ Path = "$src\cosmosdb-powershell"; Name = "cosmos-db" }
    @{ Path = "$src\vsclk-cluster"; Name = "cluster" }
)

Set-Alias -Name vsc -Value code-insiders
Set-Alias -Name vs -Value $devenv

Function global:prompt()
{
    $path=$pwd.Path
    $currentRepo=$knownRepos | where { $path -eq $_.Path -or $path -like $_.Path + "\*" } | select -First 1

    if ($currentRepo) 
    {
        $currentBranch=git rev-parse --abbrev-ref HEAD
        $relativeBranch=$currentBranch -replace ("^" + $gitBranchPrefix + "/"), ""

        git diff-index --quiet HEAD --
        $noGitChanges=$?
        $changeMarker=if ($noGitChanges) { "" } else { "*" }

        $repoDisplay="[{0}:{1}{2}] " -f $currentRepo.Name, $relativeBranch, $changeMarker
        Write-Host -Object $repoDisplay -NoNewline -ForegroundColor Green
        
        $relativePath=$path -replace ("^" + ($currentRepo.Path -replace "\\", "\\") + "\\?"), ""
        Write-Host -Object $relativePath -NoNewline
    } 
    else
    {
        Write-Host -Object "$path" -NoNewline
    }

    return "> "
}

Function start-src()  { start $src  }
Function goto-src()   { cd $src }
Function start-home()  { start $home }
Function goto-home()  { cd $home }

Function json() {
    param(
        [parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [AllowNull()]
        $object,
        [switch]$to,
        [switch]$from, 
        [int]$depth = 100
    )

    begin {
        if ($to -and $from) {
            throw "Don't give me both -to and -from, I mean c'mon"
        }

        $allStrings = $true
        $agg = @()
    }

    process {
        $allStrings = $allStrings -and ($object -is [string])

        $agg += $object
    }

    end {
        if ($agg.count -eq 0) {
            return
        }

        if ($from -or ((-not $to) -and $allStrings -and ($agg[0].Trim() -match "(\{|\[).*"))) {
            # Looks like Json (or they told us it was)

            $merged = [string]::Join("`n", $agg)
            return $merged | ConvertFrom-Json
        } else {
            $target = $agg
            if ($agg.count -eq 1) {
                $target = $agg[0]
            }

            return $target | ConvertTo-Json -Depth $depth
        }       
    }
}

Function prop() {
    param(
        [parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [AllowNull()]
        $object,
        [parameter(Mandatory = $true, Position=0)]
        [string]$path
    )

    begin {
        $fields = $path.Split(".") | % {
            # Always has to start with a name
            @{
                Type = "Property"
                Name = $_.Split('[')[0]
            }

            $index = $_.Split('[', 2)[1]
            while ($index) {
                $indexVal = $index.Split(']')[0]
                $index = $index.Split('[', 2)[1]

                @{
                    Type = "Index"
                    Value = $indexVal
                }
            }

            # TODO - what are function calls? :)
        }
    }

    process {
        $curr = $object
        $fields | % {
            $field = $_

            if ($field.Type -eq "Property") {
                $curr = $curr.($field.Name)
            } elseif ($field.Type -eq "Index") {
                $curr = $curr[$field.Value]
            }
        }

        $curr
    }
}

Function vs-cmd-do()
{
    $args -join " " | cmd /k "$vsCmd"
}

Function __setup-gh-cli-settings()
{
    $values = Get-Content $codespacesSettingsFile | json
    $env:VSCS_TARGET = $values.vscsTarget
    $env:VSCS_LOCATION = $values.vscsRegion
    $env:VSCS_TARGET_URL = $values.vscsTarget -eq "local" ? $values.vscsTargetUrl : ""
}
Function config-ext([string]$env) 
{
    -join (Get-Content -Raw                        `
        "$codespacesSettingsDir\__pre.json",       `
        "$codespacesSettingsDir\$env.json",        `
        "$codespacesSettingsDir\__post.json"       `
    ) | Set-Content $codespacesSettingsFile

    cat $codespacesSettingsFile

    __setup-gh-cli-settings
}
$getExtConfigOptions = { 
    param($commandName,$parameterName,$stringMatch)

    ls $codespacesSettingsDir           `
    | % Name                            `
    | where { -not ($_ -like "__*") }   `
    | % { $_.Split('.')[0] }            `
    | where { $_ -like "$stringMatch*" } 
}
Register-ArgumentCompleter -CommandName config-ext -ParameterName env -ScriptBlock $getExtConfigOptions
# Do this once immediately so new windows get the settings too
__setup-gh-cli-settings

$kubeClusters = @{
    "local" = "bcaleb-cluster";

    "dev-usw2" = "vsapi-cluster-dev-ci-usw2-v3-cluster";
    "dev-usw2-pf" = "vsclk-pf-dev-ci-usw2-cluster";
    "dev-use" = "vsclk-online-dev-ci-euw-cluster-2";
    "stg-usw2" = "vsclk-online-dev-stg-usw2-cluster-2";
}
Function config-kube([string]$name) { 
    $env = $kubeClusters[$name]
    if (-not $env) {
        throw "$name is not recognized, add it to the list in " + '$PROFILE'
    }
    kubectl config use-context $env
}
$getKubeConfigOptions = { 
    param($commandName,$parameterName,$stringMatch)

    $kubeClusters.Keys | where { $_ -like "$stringMatch*" } 
}
Register-ArgumentCompleter -CommandName config-kube -ParameterName name -ScriptBlock $getKubeConfigOptions

Function arm-token([switch]$Dogfood)
{
    $armTokenIsDogfood = Get-CachedValue "ArmTokenIsDogfood"

    if ($armTokenIsDogfood -eq $Dogfood)
    {
        $res=armclient token
        if (!$res.Contains("Please login"))
        {
            return
        }
    }
    
    if ($Dogfood)
    {
        armclient login Dogfood | out-null
    }
    else
    {
        armclient login | out-null
    }

    armclient token | out-null

    Set-CachedValue "ArmTokenIsDogfood" $Dogfood
}

Function ngrok-fe() { ngrok http 53760 }

Function vs-cmd() { start-process $vsCmd }

Function git-co([string]$branch)  { git checkout "$gitBranchPrefix/$branch" }
Function git-com([string]$branch) { git checkout main; git fetch; git pull; if ($branch) { git checkout -b "$gitBranchPrefix/$branch" } }
Function git-mm([string]$branch)  { git fetch; git merge origin/main }
Function git-acp([string]$message)  { git add .; git commit -am $message; git push }

$getDevBranchesBlock = { 
    param($commandName,$parameterName,$stringMatch)

    git branch                                              `
    | where { $_.Trim() -like ("$gitBranchPrefix/*") }      `
    | foreach { $_ -replace ("^\s+$gitBranchPrefix/"), "" } `
    | where { $_ -like "$stringMatch*" }
}
Register-ArgumentCompleter -CommandName git-co -ParameterName branch -ScriptBlock $getDevBranchesBlock

Function __create-func([string]$name, $block)
{
    new-item -path function:\ -name "global:$name" -value $block | out-null
}

Function __setup-project([string]$name, [string]$repo, [string]$directory, [string]$projectFile, [string]$ide)
{
    __create-func "start-$name" { start "$repo\$directory" }.GetNewClosure()
    __create-func "goto-$name"  { cd "$repo\$directory" }.GetNewClosure()
    __create-func "ide-$name"   { & $ide "$repo\$directory\$projectFile" }.GetNewClosure()
}

Function __setup-ext-base([string] $dir)
{
    pushd "$dir\.."
    yarn
    cd "$dir"
    yarn compile-all
    popd
}

Function __prepare-agent-base([string]$repo, [string]$extraArgs)
{
    $artifactLine=vs-cmd-do dotnet $repo\bin\Debug\VSOnline.DevTool\DevTool.dll generateArtifacts $repo $extraArgs `
    | where { $_ | Out-Default; $_ -match "Artifact located at" }
    
    $artifactLine.Split("\\")[-1]
}

Function __setup-cascade-repo([string]$path, [string]$suffix)
{
    $global:knownRepos += @{ Path = $path; Name = "cascade$suffix" }

    __setup-project "ext$suffix" $path $extDir $extSln "vsc"
    __create-func "setup-ext$suffix" { __setup-ext-base "$path\$extDir" }.GetNewClosure()

    __setup-project "agent$suffix" $path $agentDir $agentSln "vs"
    __create-func "prepare-agent$suffix" { __prepare-agent-base -repo "$path" ($args -join " ") }.GetNewClosure()
}
$cascadeRepos | % { __setup-cascade-repo @_ }

Function __run-portal-base([string] $dir)
{
    cd $dir
    yarn
    yarn setup
    yarn start
}

Function __prepare-devcli-base([string]$repo, [string]$version) 
{
    pushd "$repo\bin\Debug\VsoUtil"
    dotnet VsoUtil.dll preparedevcli --secret-from-app-config -v $version -c "$env:temp\$version"
    popd 
}

Function __setup-core-repo([string]$path, [string]$suffix)
{
    $global:knownRepos += @{ Path = $path; Name = "core$suffix"}

    __setup-project "portal$suffix" $path $portalDir $portalSln "vsc"
    __create-func "run-portal$suffix" { __run-portal-base "$path\$portalDir" }.GetNewClosure()

    __setup-project "service$suffix" $path $serviceDir $serviceSln "vs"
    __create-func "prepare-devcli$suffix" { param ([parameter(ValueFromPipeline)][string]$version) __prepare-devcli-base $path $version @args }.GetNewClosure()
}
$coreRepos | % { __setup-core-repo @_ }

Function __setup-sdk-repo([string]$path, [string]$suffix)
{
    $global:knownRepos += @{ Path = $path; Name = "sdk$suffix"}

    __setup-project "sdk$suffix" $path $sdkDir $sdkSln "vs"
}
$sdkRepos | % { __setup-sdk-repo @_ }

Function __setup-codespaces-repo([string]$path, [string]$suffix)
{
    $global:knownRepos += @{ Path = $path; Name = "codespaces$suffix"}

    __setup-project "cs$suffix" $path "./" "./" "vsc"
}
$codespacesRepos | % { __setup-codespaces-repo @_ }

Function __setup-cxc-repo([string]$path, [string]$suffix)
{
    $global:knownRepos += @{ Path = $path; Name = "cxc$suffix"}

    __setup-project "cxc$suffix" $path "./" "./" "vsc"
}
$cxcRepos | % { __setup-cxc-repo @_ }