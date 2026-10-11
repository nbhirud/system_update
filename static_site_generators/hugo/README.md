sudo dnf install hugo golang


hugo mod init sysupdate.nbhirud.com

hugo mod get github.com/nunocoracao/blowfish/v2

Create a hugo.toml file in your repository root with following content:
```
baseURL = 'https://sysupdate.nbhirud.com'
locale = 'en-us'
title = 'System Update'
theme = ['github.com/nunocoracao/blowfish/v2']
enableGitInfo = true

[frontmatter]
  date = [":git", ":fileModTime", "date"]
  lastmod = [":git", ":fileModTime", "lastmod"]
  
[params]
  defaultTheme = "dark"
  colorScheme = "default"
  defaultAppearance = "dark"
  autoSwitchAppearance = false
  enableSearch = true

[outputs]
  home = ["HTML", "RSS", "JSON"]

[module]
  [[module.imports]]
    path = "github.com/nunocoracao/blowfish/v2"
    disable = false
  [[module.mounts]]
    source = "linux"
    target = "content/linux"
  [[module.mounts]]
    source = "python"
    target = "content/python"
  [[module.mounts]]
    source = "python"
    target = "content/python"
  [[module.mounts]]
    source = "wsl"
    target = "content/wsl"
  [[module.mounts]]
    source = "windows"
    target = "content/windows"
  [[module.mounts]]
    source = "macos"
    target = "content/macos"
  [[module.mounts]]
    source = "data_recovery"
    target = "content/data_recovery"
  [[module.mounts]]
    source = "android"
    target = "content/android"
  [[module.mounts]]
    source = "misc"
    target = "content/misc"
  [[module.mounts]]
    source = "static_site_generators"
    target = "content/static_site_generators"


```

mkdir -p layouts/shortcodes

Create a  layouts/shortcodes/codeblock.html with following content:
```
{{ $file := .Get 0 }}
{{ $marker := .Get 1 }}
{{ $lang := .Get 2 | default "bash" }}
{{ $path := path.Join (path.Dir .Page.File.Path) $file }}
{{ $content := readFile $path }}
{{ if $marker }}
  {{ $pattern := printf "(?s)# --- \\[start: %s\\](.*?# --- \\[end: %s\\])" $marker $marker }}
  {{ $matches := findRE $pattern $content }}
  {{ if gt (len $matches) 0 }}
    {{ highlight (index $matches 0) $lang "" }}
  {{ else }}
    {{ errorf "Marker %s not found in %s" $marker $file }}
  {{ }}
{{ else }}
  {{ highlight $content $lang "" }}
{{ end }}
```

Start the local Hugo server with draft support enabled:
```
hugo server -D
```

After major changes, clear out the local Hugo cache to purge references to the old theme:
```
hugo --gc
```







