
# MkDocs


## pymdownx.snippets


Once you enable snippets in your `mkdocs.yml`, you can pull any code file directly into a Markdown file using this syntax:

```
# My Script Documentation

Here is how the script works:

--8<-- "linux/my_script.sh"
```
MkDocs will automatically grab `linux/my_script.sh`, wrap it in a code block with proper syntax highlighting, and render it cleanly on the page.


### Script Example (linux/system_backup.sh)

This is your normal, executable shell script. You write, test, and run it directly from your terminal just like you always do:

```
#!/bin/bash
# Description: Automated system backup script
echo "Starting backup..."
tar -czf /backup/home.tar.gz /home/nbhirud
echo "Backup complete!"
```

### Your Markdown File (linux/system_backup.md)

In your corresponding Markdown file, you can write your explanations, notes, usage guides, and automatically embed the script using the `--8<--` snippet tag:

```
# System Backup Script

This script automates the process of backing up the home directory into a compressed archive.

## How to Run
Execute the script with root privileges:
```bash
sudo ./linux/system_backup.sh
```

### Source Code

The script source is pulled live from the repository below:
```
--8<-- "linux/system_backup.sh"
```

### Slicing
you do not have to fetch the whole file. MkDocs (via the `pymdownx.snippets` extension) supports slicing and pulling specific line ranges or named sections out of larger code files.

#### 1. Slice by Line Numbers
You can pull a specific range of lines (e.g., lines 10 through 25) from a larger script:
```
--8<-- "python/my_large_script.py:10:25"
```

#### 2. Slice by Named Sections (Recommended for Functions)

For a cleaner approach that doesn't break if you add or remove lines above your function, you can wrap specific functions or blocks in your code file with custom markers (`--- [start]` and `--- [end]`), and then target that slice in your Markdown:

In your code file (python/utils.py):
```
def helper_function():
    # --- [start: parse_config]
    print("Parsing configuration...")
    # --- [end: parse_config]
    pass
```

In your Markdown file:
```
--8<-- "python/utils.py:parse_config"
```

