$AppId = "3358129"
$MusicFolder = "d:\Music\_vk-music\"
$AuthFile = "auth.xml"
$ForbiddenCharsRegEx = "[\/\\\?\%\*\:\|\""\<\>\!\[\]]"

Set-Location $PSScriptRoot

function GetSavedAuthParams()
{
  try
  {
    [xml]$authInfo = Get-Content $AuthFile
    $expired = [DateTime]$authInfo.auth.expires
    $today = Get-Date
    if ($expired -gt $today)
    {
      @{ token = $authInfo.auth.token; id = $authInfo.auth.id }
    }
    else
    {
       @{ token = $null; id = $null }
    }
  }
  Catch
  {
    @{ token = $null; id = $null }
  }
}

function SaveAuthParams($token, $expires, $id)
{ 
  $expiresDateTime = [DateTime]::Now.AddSeconds([int]::Parse($expires))

  $text = "<auth>`n`t<token>{0}</token>`n`t<id>{1}</id>`n`t<expires>{2:yyyy-MM-dd HH:mm:ss}</expires>`n</auth>" -f $token, $id, $expiresDateTime
  $text | Set-Content $AuthFile
}

function GetAuthParams()
{
  $authUrl = ("https://oauth.vk.com/authorize?client_id={0}"`
          + "&scope=audio&redirect_uri=http://oauth.vk.com/blank.html"`
          + "&display=page&response_type=token") -f $AppId
  start $authUrl

  $redirectedUrl = Read-Host -Prompt 'Paste here url you were redirected'
  $token = ([regex]::Match($redirectedUrl, "(?<=access_token=)[^&]+")).Value
  $expires =  ([regex]::Match($redirectedUrl, "(?<=expires_in=)[^&]+")).Value
  $id =  ([regex]::Match($redirectedUrl, "(?<=user_id=)[^&]+")).Value

  SaveAuthParams $token $expires $id

  @{ token = $token; id = $id }
}

function GetTracksMetadata($token, $id)
{
  $url = ("https://api.vkontakte.ru/method/audio.get.json?uid={0}&access_token={1}") -f $id, $token
  $data = Invoke-WebRequest $url

  $json = ConvertFrom-Json $data.Content
  if (-not($json.error -eq $null)) 
  {
    Write-Error $json.error.error_msg
    Write-Host "Deletinng $AuthFile"
    Remove-Item -Path $AuthFile

    exit
  }

  if ($json.response -eq $null)
  {
    Write-Error "No response"
    exit
  }

  $json.response 
}

function GetTrackName($track)
{
  $artist = [System.Web.HttpUtility]::HtmlDecode($track.artist)
  $title = [System.Web.HttpUtility]::HtmlDecode($track.title)
  $fullName = "{0} - {1}" -f $artist, $title

  $fullName = $fullName -replace $ForbiddenCharsRegEx, ""
  $fullName = ($fullName -replace ' +', ' ').Trim()
  $fullName = $fullName + ".mp3"

  $fullName
}

#def download_track(t_url, t_name):
#    t_path = os.path.join(MUSIC_FOLDER or "", t_name)
#    if not os.path.exists(t_path):
#        print "Downloading {0}".format(t_name.encode('UTF-8', 'replace'))
#        urllib.urlretrieve(t_url, t_path)

function DownloadTrack($track)
{
  $fullName = GetTrackName $track
  $path = [System.IO.Path]::Combine($MusicFolder, $fullName)
  if (-not (Test-Path $path))
  {
    Write-Host "Downloading $fullName"
    Invoke-WebRequest -Uri $track.url -OutFile $path
  }
}

    
Write-Host "Start"
$authParams = GetSavedAuthParams

Write-Host "Check params"
if (($authParams.token -eq $null) -or  ($authParams.id -eq $null)) {
  $authParams = GetAuthParams
}

Write-Host "Get tracks"
$tracks = GetTracksMetadata $authParams.token $authParams.id
if ($MusicFolder -and -not (Test-Path $MusicFolder))
{
  Write-Host "Create directory $MusicFolder"
  New-Item -ItemType directory -Path $MusicFolder
}

Write-Host "Start download"

$tracks | foreach { DownloadTrack $_ }

Write-Host "End"