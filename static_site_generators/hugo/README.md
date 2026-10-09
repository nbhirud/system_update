sudo dnf install hugo golang


hugo mod init github.com/nbhirud/system_update

hugo mod get github.com/nunocoracao/blowfish/v2

Create a hugo.toml file in your repository root with following content:
```
baseURL = 'https://github.com/nbhirud/system_update/'
locale = 'en-us'
title = 'System Update'
theme = ['github.com/nunocoracao/blowfish/v2']

[params]
  defaultTheme = "dark"
  colorScheme = "default"

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







